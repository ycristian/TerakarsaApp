using System.Globalization;
using System.Text.Json;
using ClosedXML.Excel;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 62: import personel PDH TNI AD dari export Google Form (.xlsx).
//
// TUGAS SERVICE INI HANYA: memetakan kolom berdasarkan NAMA HEADER (bukan posisi),
// membersihkan tipe data, dan menormalisasi gender. SELURUH aturan validasi ada di
// tni.SIS_Import_Stage -- jangan menambah aturan bisnis di sini.
//
// File Excel TIDAK disimpan ke disk; hanya dibaca dari stream.
public class TniImportService
{
    private readonly AppDbContext _db;

    // Nama field JSON harus sama dengan path OPENJSON di tni.SIS_Import_Stage.
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public TniImportService(AppDbContext db)
    {
        _db = db;
    }

    // ---------------- pemetaan header ----------------

    private const string HTimestamp = "Timestamp";
    private const string HEmail = "Email";
    private const string HGender = "Gender";
    private const string HPangkat = "Pangkat";
    private const string HNama = "NAMA";
    private const string HNrp = "NRP";
    private const string HNoHp = "No. HP";
    private const string HTb = "TB";
    private const string HBb = "BB";
    private const string HSizeBaju = "Size Baju";
    private const string HSizeCelana = "Size Celana";
    private const string HKategori = "KATEGORI";
    private const string HArea = "Area Rawatan";
    private const string HGroupBaju = "GROUPING SIZE BAJU";
    private const string HGroupCelana = "GROUPING SIZE CELANA";

    // Kolom satuan = artefak percabangan Google Form: tepat SATU yang terisi per
    // baris. Minimal satu dari ketiganya harus ada di file.
    private static readonly string[] SatuanHeaders = { "BOGOR", "Cimahi", "BANDUNG" };

    // 8 ukuran kemeja + 7 ukuran celana, header -> nama properti TniImportRow.
    private static readonly (string Header, string Prop)[] UkuranHeaders =
    {
        ("Lingkar Leher", nameof(TniImportRow.LingkarLeher)),
        ("Lebar Bahu", nameof(TniImportRow.LebarBahu)),
        ("Lingkar Dada", nameof(TniImportRow.LingkarDada)),
        ("Lingkar Perut", nameof(TniImportRow.LingkarPerut)),
        ("Panjang Badan Depan", nameof(TniImportRow.PanjangBadanDepan)),
        ("Panjang Lengan", nameof(TniImportRow.PanjangLengan)),
        ("Lingkar Lengan", nameof(TniImportRow.LingkarLengan)),
        ("Lingkar Ketiak", nameof(TniImportRow.LingkarKetiak)),
        ("Lingkar Pinggang Celana", nameof(TniImportRow.LingkarPinggangCelana)),
        ("Lingkar Pinggul", nameof(TniImportRow.LingkarPinggul)),
        ("Lingkar Pesak", nameof(TniImportRow.LingkarPesak)),
        ("Lingkar Paha", nameof(TniImportRow.LingkarPaha)),
        ("Lingkar Lutut", nameof(TniImportRow.LingkarLutut)),
        ("Lingkar Celana Bawah", nameof(TniImportRow.LingkarCelanaBawah)),
        ("Panjang Celana", nameof(TniImportRow.PanjangCelana))
    };

    // Header yang wajib ada. "Pernyataan 1/2" sengaja diabaikan, dan kolom satuan
    // dicek terpisah (cukup satu dari tiga).
    private static readonly string[] RequiredHeaders =
        new[]
        {
            HTimestamp, HEmail, HGender, HPangkat, HNama, HNrp, HNoHp, HTb, HBb,
            HSizeBaju, HSizeCelana, HKategori, HArea, HGroupBaju, HGroupCelana
        }
        .Concat(UkuranHeaders.Select(u => u.Header))
        .ToArray();

    // ---------------- parsing ----------------

    public List<TniImportRow> ParseExcel(Stream stream)
    {
        using var wb = new XLWorkbook(stream);

        // Sheet pertama file ini justru sheet tersembunyi, jadi "DATA MENTAH"
        // dicari lebih dulu berdasarkan nama.
        var ws = wb.Worksheets.FirstOrDefault(w =>
                     string.Equals(w.Name.Trim(), "DATA MENTAH", StringComparison.OrdinalIgnoreCase))
                 ?? wb.Worksheets.FirstOrDefault()
                 ?? throw new InvalidOperationException("File Excel tidak punya sheet.");

        // ---- baca header row 1 -> peta nama header (dinormalisasi) ke nomor kolom
        var headerRow = ws.Row(1);
        var lastCol = headerRow.LastCellUsed()?.Address.ColumnNumber ?? 0;

        var map = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var c = 1; c <= lastCol; c++)
        {
            var name = NormalizeHeader(headerRow.Cell(c).GetString());
            if (name.Length == 0) continue;
            // header pertama yang menang -- kolom duplikat diabaikan
            if (!map.ContainsKey(name)) map[name] = c;
        }

        var missing = RequiredHeaders
            .Where(h => !map.ContainsKey(NormalizeHeader(h)))
            .ToList();

        var satuanCols = SatuanHeaders
            .Where(h => map.ContainsKey(NormalizeHeader(h)))
            .Select(h => map[NormalizeHeader(h)])
            .ToList();

        if (satuanCols.Count == 0)
            missing.Add($"salah satu dari {string.Join(" / ", SatuanHeaders)}");

        if (missing.Count > 0)
            throw new InvalidOperationException(
                $"Header berikut tidak ditemukan di sheet \"{ws.Name}\": {string.Join(", ", missing)}.");

        int Col(string header) => map[NormalizeHeader(header)];

        var ukuranCols = UkuranHeaders.ToDictionary(u => u.Prop, u => Col(u.Header));

        // ---- baca baris data
        var rows = new List<TniImportRow>();
        var lastRow = ws.LastRowUsed()?.RowNumber() ?? 1;

        for (var rn = 2; rn <= lastRow; rn++)
        {
            var row = ws.Row(rn);

            var nama = CleanNama(row.Cell(Col(HNama)).GetString());
            var nrp = CleanNrp(row.Cell(Col(HNrp)));

            // Baris benar-benar kosong (sisa format di bawah data) dilewati, bukan
            // dilaporkan sebagai ditolak.
            if (nama.Length == 0 && nrp.Length == 0 && row.IsEmpty()) continue;

            // Satuan: ambil kolom percabangan yang terisi.
            string? satuan = null;
            foreach (var sc in satuanCols)
            {
                var v = row.Cell(sc).GetString().Trim();
                if (v.Length > 0) { satuan = v; break; }
            }

            var kodeKemeja = row.Cell(Col(HGroupBaju)).GetString().Trim();
            var kodeCelana = row.Cell(Col(HGroupCelana)).GetString().Trim();

            var item = new TniImportRow
            {
                BarisKe = rn,
                SubmittedAt = ReadDate(row.Cell(Col(HTimestamp))),
                EmailPengisi = NullIfEmpty(row.Cell(Col(HEmail)).GetString().Trim()),
                Gender = NormalizeGender(row.Cell(Col(HGender)).GetString(), kodeKemeja),
                Pangkat = NullIfEmpty(row.Cell(Col(HPangkat)).GetString().Trim()),
                Nama = nama,
                Nrp = nrp,
                NoHp = NullIfEmpty(ReadText(row.Cell(Col(HNoHp)))),
                TinggiBadan = ReadInt(row.Cell(Col(HTb))),
                BeratBadan = ReadInt(row.Cell(Col(HBb))),
                SizeBajuIsian = NullIfEmpty(ReadText(row.Cell(Col(HSizeBaju)))),
                SizeCelanaIsian = NullIfEmpty(ReadText(row.Cell(Col(HSizeCelana)))),
                Kategori = NormalizeKategori(row.Cell(Col(HKategori)).GetString()),
                AreaName = NullIfEmpty(row.Cell(Col(HArea)).GetString().Trim()),
                SatuanName = satuan,
                KodeKemeja = NullIfEmpty(kodeKemeja),
                KodeCelana = NullIfEmpty(kodeCelana)
            };

            // 15 ukuran badan -- 0 atau kosong jadi NULL.
            item.LingkarLeher = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarLeher));
            item.LebarBahu = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LebarBahu));
            item.LingkarDada = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarDada));
            item.LingkarPerut = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarPerut));
            item.PanjangBadanDepan = ReadUkuran(row, ukuranCols, nameof(TniImportRow.PanjangBadanDepan));
            item.PanjangLengan = ReadUkuran(row, ukuranCols, nameof(TniImportRow.PanjangLengan));
            item.LingkarLengan = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarLengan));
            item.LingkarKetiak = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarKetiak));
            item.LingkarPinggangCelana = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarPinggangCelana));
            item.LingkarPinggul = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarPinggul));
            item.LingkarPesak = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarPesak));
            item.LingkarPaha = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarPaha));
            item.LingkarLutut = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarLutut));
            item.LingkarCelanaBawah = ReadUkuran(row, ukuranCols, nameof(TniImportRow.LingkarCelanaBawah));
            item.PanjangCelana = ReadUkuran(row, ukuranCols, nameof(TniImportRow.PanjangCelana));

            rows.Add(item);
        }

        return rows;
    }

    // ---------------- pembersih tipe data ----------------

    private static string NormalizeHeader(string raw) =>
        System.Text.RegularExpressions.Regex.Replace(raw ?? string.Empty, @"\s+", " ").Trim();

    private static string? NullIfEmpty(string? v) =>
        string.IsNullOrWhiteSpace(v) ? null : v;

    // Nama: trim + spasi ganda dirapikan.
    private static string CleanNama(string raw) =>
        System.Text.RegularExpressions.Regex.Replace(raw ?? string.Empty, @"\s+", " ").Trim();

    // NRP dibaca sebagai TEKS: buang apostrof di depan & seluruh spasi, dan jangan
    // sampai jadi notasi ilmiah atau berakhiran ".0" (NRP bisa 16 digit).
    private static string CleanNrp(IXLCell cell)
    {
        var text = ReadText(cell);
        text = text.Replace("'", string.Empty);
        text = System.Text.RegularExpressions.Regex.Replace(text, @"\s+", string.Empty);
        return text;
    }

    // Angka dikembalikan sebagai string bulat tanpa pemisah ribuan / notasi ilmiah.
    private static string ReadText(IXLCell cell)
    {
        if (cell.IsEmpty()) return string.Empty;

        if (cell.DataType == XLDataType.Number)
        {
            var d = cell.GetValue<decimal>();
            return d == decimal.Truncate(d)
                ? decimal.Truncate(d).ToString("0", CultureInfo.InvariantCulture)
                : d.ToString("0.##########", CultureInfo.InvariantCulture);
        }

        return cell.GetString().Trim();
    }

    private static DateTime? ReadDate(IXLCell cell)
    {
        if (cell.IsEmpty()) return null;

        try
        {
            if (cell.DataType == XLDataType.DateTime) return cell.GetDateTime();

            // Google Form export kadang menyimpan timestamp sebagai serial Excel.
            if (cell.DataType == XLDataType.Number)
            {
                var serial = cell.GetValue<double>();
                if (serial > 0 && serial < 2958466) return DateTime.FromOADate(serial);
                return null;
            }

            var s = cell.GetString().Trim();
            return DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt)
                ? dt : null;
        }
        catch
        {
            return null;
        }
    }

    // TB / BB: kosong -> NULL. 0 juga dianggap NULL (tinggi/berat 0 tidak bermakna,
    // dan angka ini memang tidak divalidasi di mana pun).
    private static int? ReadInt(IXLCell cell)
    {
        var d = ReadDecimal(cell);
        if (d is null or 0) return null;
        return (int)Math.Round(d.Value, MidpointRounding.AwayFromZero);
    }

    private static decimal? ReadDecimal(IXLCell cell)
    {
        if (cell.IsEmpty()) return null;

        if (cell.DataType == XLDataType.Number)
            return cell.GetValue<decimal>();

        var s = cell.GetString().Trim().Replace(',', '.');
        return decimal.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var v) ? v : null;
    }

    // Ukuran bernilai 0 atau kosong -> NULL (keputusan owner: rentangnya tidak divalidasi).
    //
    // Batas decimal(5,1): data mentah form berisi beberapa salah ketik yang mustahil
    // (mis. Lingkar Dada 125121, Lebar Bahu 46105 -- 12 sel di 10 baris pada file
    // Juli 2026) dan nilai sebesar itu TIDAK MUNGKIN disimpan di kolom
    // decimal(5,1) yang ditetapkan Prompt 60. Nilai di luar jangkauan dijadikan
    // NULL -- disamakan dengan "tidak diukur", persis seperti personel TU_SIZING,
    // yang acuan potongnya memang murni dari pola. Ini pembersihan TIPE DATA
    // (tugas API), bukan validasi rentang: tidak ada baris yang ditolak atau
    // ditandai perlu review karenanya.
    private const decimal UkuranMax = 9999.9m;

    private static decimal? ReadUkuran(IXLRow row, Dictionary<string, int> cols, string prop)
    {
        var v = ReadDecimal(row.Cell(cols[prop]));
        if (v is null or 0) return null;
        if (Math.Abs(v.Value) > UkuranMax) return null;
        return v;
    }

    private static string NormalizeKategori(string raw)
    {
        var s = NormalizeHeader(raw).ToUpperInvariant().Replace(" ", string.Empty);
        // "T.U : Sizing" -> TU_SIZING; selain itu UKUR.
        return s.Contains("T.U") && s.Contains("SIZING") ? "TU_SIZING" : "UKUR";
    }

    // "Pria" -> PRIA; "Wanita - Hijab" -> WANITA_HIJAB; "Wanita - Non Hijab" ->
    // WANITA_NON_HIJAB. "Wanita" saja (form versi lama) diturunkan dari akhiran
    // pola kemeja: _WH... -> hijab, _W... -> non-hijab.
    private static string NormalizeGender(string raw, string kodeKemeja)
    {
        var s = NormalizeHeader(raw).ToUpperInvariant();

        if (s.StartsWith("PRIA")) return "PRIA";

        if (s.StartsWith("WANITA"))
        {
            if (s.Contains("NON")) return "WANITA_NON_HIJAB";
            if (s.Contains("HIJAB")) return "WANITA_HIJAB";

            var k = (kodeKemeja ?? string.Empty).ToUpperInvariant();
            if (k.Contains("_WH")) return "WANITA_HIJAB";
            if (k.Contains("_W")) return "WANITA_NON_HIJAB";

            // tidak bisa ditentukan -- biarkan non-hijab, SP akan menandai REVIEW
            // kalau polanya ternyata tidak cocok.
            return "WANITA_NON_HIJAB";
        }

        // Gender tidak dikenal: pakai pola kemeja sebagai petunjuk terakhir.
        var kk = (kodeKemeja ?? string.Empty).ToUpperInvariant();
        if (kk.Contains("_WH")) return "WANITA_HIJAB";
        if (kk.Contains("_W")) return "WANITA_NON_HIJAB";
        return "PRIA";
    }

    // ---------------- panggilan SP ----------------

    public async Task<int> StageAsync(int orderId, string namaFile, List<TniImportRow> rows, int userId)
    {
        var json = JsonSerializer.Serialize(rows, JsonOpts);

        var result = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC tni.SIS_Import_Stage @OrderId = @OrderId, @NamaFile = @NamaFile, @Rows = @Rows, @UserId = @UserId",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@NamaFile", namaFile),
                new SqlParameter("@Rows", json),
                new SqlParameter("@UserId", userId))
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<TniImportHasilDto> GetBatchAsync(int batchId)
    {
        // Dua result set dari satu SP -> dibaca dua kali (pola yang dipakai service
        // lain di proyek ini: EF SqlQueryRaw hanya membaca result set pertama).
        var batch = await _db.Database
            .SqlQueryRaw<TniImportBatchDto>(
                "EXEC tni.SIS_Import_GetBatch @BatchId = @BatchId",
                new SqlParameter("@BatchId", batchId))
            .ToListAsync();

        var baris = await _db.Database
            .SqlQueryRaw<TniImportBarisDto>(
                @"SELECT st.baris_ke AS BarisKe, st.nrp AS Nrp, st.nama AS Nama,
                         st.hasil_validasi AS Hasil, st.aksi AS Aksi, st.pesan_error AS Pesan
                  FROM tni.import_staging st
                  WHERE st.batch_id = @BatchId AND st.hasil_validasi IN ('TOLAK','REVIEW')
                  ORDER BY CASE st.hasil_validasi WHEN 'TOLAK' THEN 0 ELSE 1 END, st.baris_ke",
                new SqlParameter("@BatchId", batchId))
            .ToListAsync();

        return new TniImportHasilDto
        {
            Batch = batch.FirstOrDefault(),
            Baris = baris
        };
    }

    public async Task<List<TniImportBatchDto>> GetBatchListAsync(int orderId)
    {
        return await _db.Database
            .SqlQueryRaw<TniImportBatchDto>(
                "EXEC tni.SIS_Import_BatchList @OrderId = @OrderId",
                new SqlParameter("@OrderId", orderId))
            .ToListAsync();
    }

    public async Task<(bool Success, string Error, TniImportCommitHasilDto? Hasil)> CommitAsync(int batchId, int userId)
    {
        try
        {
            var result = await _db.Database
                .SqlQueryRaw<TniImportCommitHasilDto>(
                    "EXEC tni.SIS_Import_Commit @BatchId = @BatchId, @UserId = @UserId",
                    new SqlParameter("@BatchId", batchId),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }
}

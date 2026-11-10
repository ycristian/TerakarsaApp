using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 65: Perintah Kerja & saran prioritas PDH TNI AD.
//
// ALGORITMA GREEDY ADA DI SINI, bukan di SP -- ini SARAN, bukan validasi.
// Cara hitung "bisa dibuat": salin stok bebas kemeja & celana, telusuri kandidat
// urut kode_ref; seseorang terhitung bila stok bebas pola kemejanya DAN pola
// celananya masing-masing > 0, lalu kurangi keduanya 1. Kalau salah satu kosong,
// orang itu masuk "belum bisa" dengan alasan pola yang kurang.
//
// Hitungan PER SATUAN memakai salinan stok bebas yang SEGAR untuk tiap satuan --
// jadi angka antarsatuan bisa saling tumpang tindih (UI memberi keterangan ini).
// Hitungan PER RAWATAN = greedy atas seluruh kandidat rawatan itu, urut
// satuan_code lalu kode_ref.
// Filter size prioritas (per perangkat, disimpan di localStorage klien): size kemeja/celana
// yang fisiknya sedang dekat, masing-masing dengan QTY tumpukan di dekat (null = semua stok
// bebas). Tujuannya MENGHABISKAN tumpukan itu: greedy dua tahap di TniPerintahKerjaService.Bagi
// -- tahap 1 hanya personel yang masih kebagian kuota size terpilih, tahap 2 sisanya.
public sealed class TniSizePrioritas
{
    // pola_id -> qty di dekat (null = semua stok bebas)
    public Dictionary<int, int?> Kemeja { get; }
    public Dictionary<int, int?> Celana { get; }

    public TniSizePrioritas(Dictionary<int, int?>? kemeja, Dictionary<int, int?>? celana)
    {
        Kemeja = kemeja ?? new();
        Celana = celana ?? new();
    }

    public static readonly TniSizePrioritas Kosong = new(null, null);

    // Query string "12:20,15" = pola 12 qty 20, pola 15 semua stok. Item tidak valid diabaikan.
    public static TniSizePrioritas Parse(string? kemeja, string? celana) => new(Items(kemeja), Items(celana));

    private static Dictionary<int, int?> Items(string? csv)
    {
        var hasil = new Dictionary<int, int?>();
        foreach (var bagian in (csv ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var kv = bagian.Split(':');
            if (!int.TryParse(kv[0], out var id) || id <= 0) continue;
            int? qty = kv.Length > 1 && int.TryParse(kv[1], out var q) && q > 0 ? q : null;
            hasil[id] = qty;
        }
        return hasil;
    }

    public bool Aktif => Kemeja.Count > 0 || Celana.Count > 0;

    // 0, 1, atau 2 barang size terpilih yang dipakai satu set orang ini.
    public int JumlahCocok(TniKandidatDto p) =>
        (Kemeja.ContainsKey(p.PolaKemejaId) ? 1 : 0) + (Celana.ContainsKey(p.PolaCelanaId) ? 1 : 0);

    // Kuota awal per pola = qty di dekat, dibatasi stok bebas (minus dianggap 0).
    public Dictionary<int, int> KuotaKemeja(Dictionary<int, int> stok) => Kuota(Kemeja, stok);
    public Dictionary<int, int> KuotaCelana(Dictionary<int, int> stok) => Kuota(Celana, stok);

    private static Dictionary<int, int> Kuota(Dictionary<int, int?> pilih, Dictionary<int, int> stok) =>
        pilih.ToDictionary(x => x.Key, x =>
        {
            var bebas = Math.Max(0, stok.GetValueOrDefault(x.Key));
            return x.Value is int q ? Math.Min(q, bebas) : bebas;
        });
}

public class TniPerintahKerjaService
{
    private readonly AppDbContext _db;
    private readonly string _qrBaseUrl;

    public TniPerintahKerjaService(AppDbContext db, IConfiguration config)
    {
        _db = db;
        // JANGAN pakai App:PublicBaseUrl -- itu alamat LAN untuk label bundle.
        _qrBaseUrl = (config["Tni:QrBaseUrl"] ?? "https://app.terakarsa.id").TrimEnd('/');
    }

    // ---------------- data mentah (3 result set) ----------------

    private sealed class DataMentah
    {
        public List<TniKandidatDto> Kandidat { get; set; } = new();
        public Dictionary<int, int> StokKemeja { get; set; } = new();   // polaId -> stok bebas
        public Dictionary<int, int> StokCelana { get; set; } = new();
        public Dictionary<int, string> KodeKemeja { get; set; } = new();
        public Dictionary<int, string> KodeCelana { get; set; } = new();
    }

    // SIS_PerintahKerja_Data mengembalikan 3 result set -- EF Core SqlQueryRaw hanya
    // mendukung satu, jadi pakai SqlCommand mentah + reader.NextResultAsync()
    // (pola sama dengan ReportBundleService.GetArticleProgressAsync).
    private async Task<DataMentah> GetDataAsync(int orderId, int? areaId, int? satuanId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "tni.SIS_PerintahKerja_Data";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.CommandTimeout = 120;
            cmd.Parameters.Add(new SqlParameter("@OrderId", orderId));
            cmd.Parameters.Add(new SqlParameter("@AreaId", areaId ?? (object)DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@SatuanId", satuanId ?? (object)DBNull.Value));

            var result = new DataMentah();
            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                result.Kandidat.Add(new TniKandidatDto
                {
                    PersonelId = reader.GetInt32(reader.GetOrdinal("PersonelId")),
                    KodeRef = reader.GetString(reader.GetOrdinal("KodeRef")),
                    Pangkat = reader.IsDBNull(reader.GetOrdinal("Pangkat")) ? null : reader.GetString(reader.GetOrdinal("Pangkat")),
                    Nama = reader.GetString(reader.GetOrdinal("Nama")),
                    AreaId = reader.GetInt32(reader.GetOrdinal("AreaId")),
                    AreaCode = reader.GetString(reader.GetOrdinal("AreaCode")),
                    AreaName = reader.GetString(reader.GetOrdinal("AreaName")),
                    SatuanId = reader.GetInt32(reader.GetOrdinal("SatuanId")),
                    SatuanCode = reader.GetString(reader.GetOrdinal("SatuanCode")),
                    SatuanName = reader.GetString(reader.GetOrdinal("SatuanName")),
                    PolaKemejaId = reader.GetInt32(reader.GetOrdinal("PolaKemejaId")),
                    PolaKemejaKode = reader.GetString(reader.GetOrdinal("PolaKemejaKode")),
                    PolaCelanaId = reader.GetInt32(reader.GetOrdinal("PolaCelanaId")),
                    PolaCelanaKode = reader.GetString(reader.GetOrdinal("PolaCelanaKode"))
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                var id = reader.GetInt32(reader.GetOrdinal("PolaId"));
                result.StokKemeja[id] = reader.GetInt32(reader.GetOrdinal("StokBebas"));
                result.KodeKemeja[id] = reader.GetString(reader.GetOrdinal("Kode"));
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                var id = reader.GetInt32(reader.GetOrdinal("PolaId"));
                result.StokCelana[id] = reader.GetInt32(reader.GetOrdinal("StokBebas"));
                result.KodeCelana[id] = reader.GetString(reader.GetOrdinal("Kode"));
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // ---------------- greedy ----------------

    // Menelusuri kandidat (urut sesuai urutan list yang diberikan) atas SALINAN
    // stok bebas. Mengembalikan siapa yang bisa dibuat dan siapa yang belum bisa.
    private static (List<TniKandidatDto> Bisa, List<TniBelumBisaDto> Belum) Greedy(
        IEnumerable<TniKandidatDto> kandidat,
        Dictionary<int, int> stokKemeja,
        Dictionary<int, int> stokCelana)
    {
        // salinan -- stok asli tidak disentuh supaya bisa dipakai ulang per satuan
        var k = new Dictionary<int, int>(stokKemeja);
        var c = new Dictionary<int, int>(stokCelana);

        var bisa = new List<TniKandidatDto>();
        var belum = new List<TniBelumBisaDto>();

        foreach (var p in kandidat)
        {
            var adaKemeja = k.TryGetValue(p.PolaKemejaId, out var sk) && sk > 0;
            var adaCelana = c.TryGetValue(p.PolaCelanaId, out var sc) && sc > 0;

            if (adaKemeja && adaCelana)
            {
                k[p.PolaKemejaId] = sk - 1;
                c[p.PolaCelanaId] = sc - 1;
                bisa.Add(p);
            }
            else
            {
                belum.Add(new TniBelumBisaDto
                {
                    Personel = p,
                    KemejaKurang = !adaKemeja,
                    CelanaKurang = !adaCelana
                });
            }
        }

        return (bisa, belum);
    }

    private sealed record HasilBagi(
        List<TniKandidatDto> Bisa, List<TniBelumBisaDto> Belum,
        int BisaPrioritas, int PakaiPrioritas, int StokPrioritas);

    // Greedy dengan size prioritas (dua tahap):
    //   1. Personel yang memakai size terpilih -- 2 barang cocok dulu, lalu 1 -- diambil
    //      SELAMA kuota (qty di dekat) size-nya masih ada dan pasangannya ada di stok bebas.
    //   2. Sisanya (termasuk yang cocok tapi kuotanya sudah habis) dengan greedy biasa
    //      atas stok yang tersisa, urutan asli.
    // Filter kosong = persis Greedy biasa.
    private static HasilBagi Bagi(
        List<TniKandidatDto> kandidat,
        Dictionary<int, int> stokKemeja,
        Dictionary<int, int> stokCelana,
        TniSizePrioritas size)
    {
        foreach (var p in kandidat) p.IsSizePrioritas = false;

        if (!size.Aktif)
        {
            var (b, bl) = Greedy(kandidat, stokKemeja, stokCelana);
            return new HasilBagi(b, bl, 0, 0, 0);
        }

        var k = new Dictionary<int, int>(stokKemeja);
        var c = new Dictionary<int, int>(stokCelana);
        var kuotaK = size.KuotaKemeja(stokKemeja);
        var kuotaC = size.KuotaCelana(stokCelana);
        var stokPrioritas = kuotaK.Values.Sum() + kuotaC.Values.Sum();

        var tahap1 = new List<TniKandidatDto>();
        var diambil = new HashSet<int>();
        var pakai = 0;

        foreach (var p in kandidat.Where(x => size.JumlahCocok(x) > 0).OrderByDescending(size.JumlahCocok))
        {
            var sisaK = kuotaK.TryGetValue(p.PolaKemejaId, out var qk) && qk > 0;
            var sisaC = kuotaC.TryGetValue(p.PolaCelanaId, out var qc) && qc > 0;
            if (!sisaK && !sisaC) continue;   // kuota size-nya sudah habis -> tahap 2

            if (k.GetValueOrDefault(p.PolaKemejaId) <= 0 || c.GetValueOrDefault(p.PolaCelanaId) <= 0)
                continue;                      // pasangannya kosong -> tahap 2 (akan masuk "belum bisa")

            k[p.PolaKemejaId]--;
            c[p.PolaCelanaId]--;
            if (sisaK) { kuotaK[p.PolaKemejaId] = qk - 1; pakai++; }
            if (sisaC) { kuotaC[p.PolaCelanaId] = qc - 1; pakai++; }

            p.IsSizePrioritas = true;
            tahap1.Add(p);
            diambil.Add(p.PersonelId);
        }

        var (tahap2, belum) = Greedy(kandidat.Where(x => !diambil.Contains(x.PersonelId)), k, c);

        return new HasilBagi(tahap1.Concat(tahap2).ToList(), belum, tahap1.Count, pakai, stokPrioritas);
    }

    // ---------------- per rawatan ----------------

    public async Task<List<TniRawatanDto>> GetRawatanAsync(int orderId, TniSizePrioritas? size = null)
    {
        size ??= TniSizePrioritas.Kosong;
        var data = await GetDataAsync(orderId, null, null);

        // total & sudah masuk box per area, dari view (bukan dari kandidat).
        var statistik = await _db.Database
            .SqlQueryRaw<AreaStatistik>(
                @"SELECT v.area_id AS AreaId, v.area_code AS AreaCode, v.area_name AS AreaName,
                         COUNT(*) AS TotalPersonel,
                         SUM(CASE WHEN v.status_progres IN ('MASUK_BOX','TERKIRIM') THEN 1 ELSE 0 END) AS SudahMasukBox
                  FROM tni.v_personel v
                  WHERE v.order_id = @OrderId
                  GROUP BY v.area_id, v.area_code, v.area_name
                  ORDER BY v.area_code",
                new SqlParameter("@OrderId", orderId))
            .ToListAsync();

        var hasil = new List<TniRawatanDto>();

        foreach (var s in statistik)
        {
            var kandidatArea = data.Kandidat
                .Where(x => x.AreaId == s.AreaId)
                .OrderBy(x => x.SatuanCode).ThenBy(x => x.KodeRef)
                .ToList();

            // per rawatan: greedy atas SELURUH kandidat rawatan itu
            // (size prioritas didahulukan sampai qty di dekat habis)
            var bagi = Bagi(kandidatArea, data.StokKemeja, data.StokCelana, size);

            // jumlah satuan yang bisa tuntas: tiap satuan dihitung dengan salinan
            // stok bebas yang SEGAR (angka antarsatuan bisa tumpang tindih)
            var satuanBisaTuntas = kandidatArea
                .GroupBy(x => x.SatuanId)
                .Count(g =>
                {
                    var (b, _) = Greedy(g.OrderBy(x => x.KodeRef), data.StokKemeja, data.StokCelana);
                    return g.Count() > 0 && b.Count == g.Count();
                });

            hasil.Add(new TniRawatanDto
            {
                AreaId = s.AreaId,
                AreaCode = s.AreaCode,
                AreaName = s.AreaName,
                TotalPersonel = s.TotalPersonel,
                SudahMasukBox = s.SudahMasukBox,
                Sisa = kandidatArea.Count,
                BisaDibuat = bagi.Bisa.Count,
                SatuanBisaTuntas = satuanBisaTuntas,
                BisaSizePrioritas = bagi.BisaPrioritas,
                PakaiSizePrioritas = bagi.PakaiPrioritas,
                StokSizePrioritas = bagi.StokPrioritas
            });
        }

        return hasil;
    }

    private sealed class AreaStatistik
    {
        public int AreaId { get; set; }
        public string AreaCode { get; set; } = string.Empty;
        public string AreaName { get; set; } = string.Empty;
        public int TotalPersonel { get; set; }
        public int SudahMasukBox { get; set; }
    }

    private sealed class SatuanStatistik
    {
        public int SatuanId { get; set; }
        public string SatuanCode { get; set; } = string.Empty;
        public string SatuanName { get; set; } = string.Empty;
        public int TotalPersonel { get; set; }
        public int SudahMasukBox { get; set; }
        public int SudahDicetak { get; set; }
        public int SudahSetJadi { get; set; }
        public bool IsPrioritas { get; set; }
    }

    // ---------------- daftar satuan satu rawatan ----------------

    // Urutan daftar:
    //   1. BISA TUNTAS dulu, dari sisa paling SEDIKIT
    //   2. sisanya dari BISA DIBUAT terbanyak
    //   3. satuan tanpa kandidat (sisa 0) paling bawah
    public async Task<List<TniSatuanSaranDto>> GetSatuanAsync(int orderId, int areaId, TniSizePrioritas? size = null)
    {
        size ??= TniSizePrioritas.Kosong;
        var data = await GetDataAsync(orderId, areaId, null);

        var statistik = await _db.Database
            .SqlQueryRaw<SatuanStatistik>(
                @"SELECT v.satuan_id AS SatuanId, v.satuan_code AS SatuanCode, v.satuan_name AS SatuanName,
                         COUNT(*) AS TotalPersonel,
                         SUM(CASE WHEN v.status_progres IN ('MASUK_BOX','TERKIRIM') THEN 1 ELSE 0 END) AS SudahMasukBox,
                         SUM(CASE WHEN v.status_progres <> 'BELUM_CETAK' THEN 1 ELSE 0 END) AS SudahDicetak,
                         SUM(CASE WHEN v.status_progres IN ('SET_JADI','MASUK_BOX','TERKIRIM') THEN 1 ELSE 0 END) AS SudahSetJadi,
                         CAST(CASE WHEN s.prioritas_at IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsPrioritas
                  FROM tni.v_personel v
                  JOIN tni.satuan s ON s.satuan_id = v.satuan_id
                  WHERE v.order_id = @OrderId AND v.area_id = @AreaId
                  GROUP BY v.satuan_id, v.satuan_code, v.satuan_name, s.prioritas_at",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@AreaId", areaId))
            .ToListAsync();

        var hasil = new List<TniSatuanSaranDto>();

        foreach (var s in statistik)
        {
            var kandidat = data.Kandidat
                .Where(x => x.SatuanId == s.SatuanId)
                .OrderBy(x => x.KodeRef)
                .ToList();

            // salinan stok bebas yang SEGAR untuk tiap satuan
            var bagi = Bagi(kandidat, data.StokKemeja, data.StokCelana, size);

            hasil.Add(new TniSatuanSaranDto
            {
                SatuanId = s.SatuanId,
                SatuanCode = s.SatuanCode,
                SatuanName = s.SatuanName,
                TotalPersonel = s.TotalPersonel,
                SudahMasukBox = s.SudahMasukBox,
                SudahDicetak = s.SudahDicetak,
                SudahSetJadi = s.SudahSetJadi,
                IsPrioritas = s.IsPrioritas,
                Sisa = kandidat.Count,
                BisaDibuat = bagi.Bisa.Count,
                BisaSizePrioritas = bagi.BisaPrioritas,
                PakaiSizePrioritas = bagi.PakaiPrioritas,
                StokSizePrioritas = bagi.StokPrioritas
            });
        }

        return hasil
            .OrderByDescending(x => x.IsPrioritas)             // 0. berbintang selalu paling atas
            .ThenByDescending(x => x.BisaTuntas)               // 1. bisa tuntas dulu
            .ThenByDescending(x => x.PakaiSizePrioritas)       //    lalu yang paling banyak menghabiskan stok size terpilih (0 bila filter kosong)
            .ThenBy(x => x.BisaTuntas ? x.Sisa : int.MaxValue) //    sisa paling sedikit
            .ThenBy(x => x.Sisa == 0)                          // 3. tanpa kandidat di bawah
            .ThenByDescending(x => x.BisaDibuat)               // 2. bisa dibuat terbanyak
            .ThenBy(x => x.SatuanCode)
            .ToList();
    }

    // ---------------- detail satu satuan ----------------

    public async Task<TniSatuanDetailDto> GetSatuanDetailAsync(int orderId, int satuanId, TniSizePrioritas? size = null)
    {
        size ??= TniSizePrioritas.Kosong;
        var data = await GetDataAsync(orderId, null, satuanId);

        // size prioritas di depan (sampai qty di dekat habis); IsSizePrioritas diisi Bagi
        var kandidat = data.Kandidat.OrderBy(x => x.KodeRef).ToList();
        var bagi = Bagi(kandidat, data.StokKemeja, data.StokCelana, size);
        var (bisa, belum) = (bagi.Bisa, bagi.Belum);

        // Ringkasan kekurangan per pola: berapa orang yang tertahan karena pola itu.
        var kekurangan = belum
            .Where(b => b.KemejaKurang)
            .GroupBy(b => b.Personel.PolaKemejaId)
            .Select(g => new TniKekuranganDto
            {
                JenisItem = "KEMEJA",
                Kode = data.KodeKemeja.TryGetValue(g.Key, out var k) ? k : g.First().Personel.PolaKemejaKode,
                Kurang = g.Count()
            })
            .Concat(belum
                .Where(b => b.CelanaKurang)
                .GroupBy(b => b.Personel.PolaCelanaId)
                .Select(g => new TniKekuranganDto
                {
                    JenisItem = "CELANA",
                    Kode = data.KodeCelana.TryGetValue(g.Key, out var c) ? c : g.First().Personel.PolaCelanaKode,
                    Kurang = g.Count()
                }))
            .OrderByDescending(x => x.Kurang)
            .ThenBy(x => x.Kode)
            .ToList();

        var contoh = kandidat.FirstOrDefault();

        return new TniSatuanDetailDto
        {
            SatuanId = satuanId,
            SatuanCode = contoh?.SatuanCode ?? string.Empty,
            SatuanName = contoh?.SatuanName ?? string.Empty,
            AreaName = contoh?.AreaName ?? string.Empty,
            BisaDibuat = bisa,
            PakaiSizePrioritas = bagi.PakaiPrioritas,
            StokSizePrioritas = bagi.StokPrioritas,
            BelumBisa = belum,
            Kekurangan = kekurangan
        };
    }

    public async Task<List<TniDijatahDto>> GetDijatahAsync(int orderId, int satuanId)
    {
        return await _db.Database
            .SqlQueryRaw<TniDijatahDto>(
                "EXEC tni.SIS_PerintahKerja_Dijatah @OrderId = @OrderId, @SatuanId = @SatuanId",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@SatuanId", satuanId))
            .ToListAsync();
    }

    // ---------------- cetak & lepas ----------------

    public async Task<(bool Success, string Error, TniCetakHasilDto? Hasil)> CetakAsync(
        List<int> personelIds, int userId, int? perangkatId = null)
    {
        try
        {
            var result = await _db.Database
                .SqlQueryRaw<TniCetakHasilDto>(
                    @"EXEC tni.SIS_Personel_Cetak @PersonelIds = @PersonelIds,
                        @QrBaseUrl = @QrBaseUrl, @UserId = @UserId, @PerangkatId = @PerangkatId",
                    new SqlParameter("@PersonelIds", JsonSerializer.Serialize(personelIds)),
                    new SqlParameter("@QrBaseUrl", _qrBaseUrl),
                    new SqlParameter("@UserId", userId),
                    new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value))
                .ToListAsync();

            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error, TniLepasHasilDto? Hasil)> LepasAsync(
        List<int> personelIds, int userId)
    {
        try
        {
            var result = await _db.Database
                .SqlQueryRaw<TniLepasHasilDto>(
                    "EXEC tni.SIS_Personel_LepasCetak @PersonelIds = @PersonelIds, @UserId = @UserId",
                    new SqlParameter("@PersonelIds", JsonSerializer.Serialize(personelIds)),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    // Bintang prioritas satuan (alter_78). Tidak bergantung order -- melekat di satuan.
    public async Task<(bool Success, string Error)> SetPrioritasAsync(
        int satuanId, bool prioritas, int userId, int? perangkatId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Satuan_Manage @Action = 'PRIORITAS', @Id = @Id,
                    @Prioritas = @Prioritas, @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@Id", satuanId),
                new SqlParameter("@Prioritas", prioritas),
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Total stok bebas untuk catatan kecil di layar "Pilih rawatan".
    public async Task<(int Kemeja, int Celana)> GetTotalStokBebasAsync(int orderId)
    {
        var rows = await _db.Database
            .SqlQueryRaw<JenisTotal>(
                @"SELECT v.jenis_item AS JenisItem, SUM(CASE WHEN v.stok_bebas > 0 THEN v.stok_bebas ELSE 0 END) AS Total
                  FROM tni.v_stok_pola v
                  WHERE v.order_id = @OrderId
                  GROUP BY v.jenis_item",
                new SqlParameter("@OrderId", orderId))
            .ToListAsync();

        return (rows.FirstOrDefault(x => x.JenisItem == "KEMEJA")?.Total ?? 0,
                rows.FirstOrDefault(x => x.JenisItem == "CELANA")?.Total ?? 0);
    }

    private sealed class JenisTotal
    {
        public string JenisItem { get; set; } = string.Empty;
        public int Total { get; set; }
    }
}

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
//
// KUNCI STOK (2026-11-11, alter_81): satuan bergembok menyisihkan stok bebas untuk
// kebutuhan BELUM_CETAK-nya (pembagian di SQL, tni.v_stok_kunci). Semua hitungan di
// sini memakai StokPool: satuan bergembok boleh memakai jatah kuncinya SENDIRI +
// stok bebas yang tidak dikunci siapa pun; satuan lain hanya yang tidak dikunci.
// Jadi set satuan bergembok langsung "bisa dibuat" begitu pasangannya masuk, dan
// stoknya tidak terhitung untuk satuan lain.
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
        public Dictionary<int, PolaUrut> UrutKemeja { get; set; } = new();
        public Dictionary<int, PolaUrut> UrutCelana { get; set; } = new();

        // satuanId -> (polaId -> qty dikunci). Semua satuan bergembok di order ini.
        public Dictionary<int, Dictionary<int, int>> KunciKemeja { get; set; } = new();
        public Dictionary<int, Dictionary<int, int>> KunciCelana { get; set; } = new();

        // Stok yang boleh dipakai kumpulan satuan ini: stok bebas yang tidak dikunci
        // siapa pun + jatah kunci satuan-satuan itu sendiri (per satuan, terpisah).
        public StokPool Pool(IEnumerable<int> satuanIds)
        {
            var ids = satuanIds.ToHashSet();
            return new StokPool(
                TanpaKunci(StokKemeja, KunciKemeja), TanpaKunci(StokCelana, KunciCelana),
                Jatah(KunciKemeja, ids), Jatah(KunciCelana, ids));
        }

        public int DikunciKemeja(int satuanId) => KunciKemeja.TryGetValue(satuanId, out var d) ? d.Values.Sum() : 0;
        public int DikunciCelana(int satuanId) => KunciCelana.TryGetValue(satuanId, out var d) ? d.Values.Sum() : 0;

        // stok bebas (minus = 0) dikurangi semua kunci -- tidak pernah < 0 karena
        // kunci di SQL dibatasi stok bebas.
        private static Dictionary<int, int> TanpaKunci(Dictionary<int, int> stok, Dictionary<int, Dictionary<int, int>> kunci)
        {
            var hasil = stok.ToDictionary(x => x.Key, x => Math.Max(0, x.Value));
            foreach (var per in kunci.Values)
                foreach (var (pola, qty) in per)
                    hasil[pola] = Math.Max(0, hasil.GetValueOrDefault(pola) - qty);
            return hasil;
        }

        private static Dictionary<int, Dictionary<int, int>> Jatah(Dictionary<int, Dictionary<int, int>> kunci, HashSet<int> ids) =>
            kunci.Where(x => ids.Contains(x.Key)).ToDictionary(x => x.Key, x => new Dictionary<int, int>(x.Value));
    }

    // Stok yang sedang dibagi greedy. Satu orang mengambil dari jatah kunci satuannya
    // dulu, baru dari stok tanpa kunci. Satuan tanpa gembok hanya punya stok tanpa kunci.
    private sealed class StokPool
    {
        private readonly Dictionary<int, int> _bebasK, _bebasC;
        private readonly Dictionary<int, Dictionary<int, int>> _kunciK, _kunciC;

        public StokPool(Dictionary<int, int> bebasK, Dictionary<int, int> bebasC,
            Dictionary<int, Dictionary<int, int>> kunciK, Dictionary<int, Dictionary<int, int>> kunciC)
        {
            _bebasK = bebasK; _bebasC = bebasC; _kunciK = kunciK; _kunciC = kunciC;
        }

        public StokPool Salin() => new(
            new(_bebasK), new(_bebasC),
            _kunciK.ToDictionary(x => x.Key, x => new Dictionary<int, int>(x.Value)),
            _kunciC.ToDictionary(x => x.Key, x => new Dictionary<int, int>(x.Value)));

        public int Kemeja(TniKandidatDto p) => Ada(_bebasK, _kunciK, p.SatuanId, p.PolaKemejaId);
        public int Celana(TniKandidatDto p) => Ada(_bebasC, _kunciC, p.SatuanId, p.PolaCelanaId);

        public void Ambil(TniKandidatDto p)
        {
            Kurangi(_bebasK, _kunciK, p.SatuanId, p.PolaKemejaId);
            Kurangi(_bebasC, _kunciC, p.SatuanId, p.PolaCelanaId);
        }

        // Total per pola yang bisa dipakai kumpulan satuan di pool ini.
        public Dictionary<int, int> TotalKemeja() => Total(_bebasK, _kunciK);
        public Dictionary<int, int> TotalCelana() => Total(_bebasC, _kunciC);

        private static int Ada(Dictionary<int, int> bebas, Dictionary<int, Dictionary<int, int>> kunci, int satuanId, int polaId) =>
            bebas.GetValueOrDefault(polaId)
            + (kunci.TryGetValue(satuanId, out var d) ? d.GetValueOrDefault(polaId) : 0);

        private static void Kurangi(Dictionary<int, int> bebas, Dictionary<int, Dictionary<int, int>> kunci, int satuanId, int polaId)
        {
            if (kunci.TryGetValue(satuanId, out var d) && d.GetValueOrDefault(polaId) > 0)
                d[polaId]--;
            else
                bebas[polaId] = bebas.GetValueOrDefault(polaId) - 1;
        }

        private static Dictionary<int, int> Total(Dictionary<int, int> bebas, Dictionary<int, Dictionary<int, int>> kunci)
        {
            var hasil = new Dictionary<int, int>(bebas);
            foreach (var per in kunci.Values)
                foreach (var (pola, qty) in per)
                    hasil[pola] = hasil.GetValueOrDefault(pola) + qty;
            return hasil;
        }
    }

    // Grup gender + urutan tampilan pola, sama dengan halaman Stok (tni.v_pola_urut).
    private sealed record PolaUrut(string Grup, int UrutGender, int UrutVarian, decimal UrutSize);

    private static PolaUrut BacaUrut(SqlDataReader r)
    {
        int Ord(string n) { try { return r.GetOrdinal(n); } catch (IndexOutOfRangeException) { return -1; } }
        var g = Ord("GrupGender");
        if (g < 0) return new PolaUrut(string.Empty, 9, 0, 0);   // SP lama: tanpa kolom urut
        var ug = Ord("UrutGender");
        var uv = Ord("UrutVarian");
        var us = Ord("UrutSize");
        return new PolaUrut(
            r.IsDBNull(g) ? string.Empty : r.GetString(g),
            r.IsDBNull(ug) ? 9 : Convert.ToInt32(r.GetValue(ug)),
            r.IsDBNull(uv) ? 0 : Convert.ToInt32(r.GetValue(uv)),
            r.IsDBNull(us) ? 0 : Convert.ToDecimal(r.GetValue(us)));
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
                result.UrutKemeja[id] = BacaUrut(reader);
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                var id = reader.GetInt32(reader.GetOrdinal("PolaId"));
                result.StokCelana[id] = reader.GetInt32(reader.GetOrdinal("StokBebas"));
                result.KodeCelana[id] = reader.GetString(reader.GetOrdinal("Kode"));
                result.UrutCelana[id] = BacaUrut(reader);
            }

            // (4) stok dikunci satuan (alter_81). SP lama tanpa result set ini = tanpa kunci.
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    var satuan = reader.GetInt32(reader.GetOrdinal("SatuanId"));
                    var pola = reader.GetInt32(reader.GetOrdinal("PolaId"));
                    var qty = Convert.ToInt32(reader.GetValue(reader.GetOrdinal("Dikunci")));
                    var target = reader.GetString(reader.GetOrdinal("JenisItem")) == "KEMEJA"
                        ? result.KunciKemeja : result.KunciCelana;
                    if (!target.TryGetValue(satuan, out var per)) target[satuan] = per = new();
                    per[pola] = per.GetValueOrDefault(pola) + qty;
                }
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
    // stok pool. Mengembalikan siapa yang bisa dibuat dan siapa yang belum bisa.
    private static (List<TniKandidatDto> Bisa, List<TniBelumBisaDto> Belum) Greedy(
        IEnumerable<TniKandidatDto> kandidat,
        StokPool pool)
    {
        var (bisa, belum, _) = GreedySisa(kandidat, pool);
        return (bisa, belum);
    }

    // Sama dengan Greedy, plus sisa stok setelah semua yang "bisa" diambil.
    private static (List<TniKandidatDto> Bisa, List<TniBelumBisaDto> Belum, StokPool Sisa) GreedySisa(
        IEnumerable<TniKandidatDto> kandidat,
        StokPool pool)
    {
        // salinan -- pool asli tidak disentuh supaya bisa dipakai ulang
        var stok = pool.Salin();

        var bisa = new List<TniKandidatDto>();
        var belum = new List<TniBelumBisaDto>();

        foreach (var p in kandidat)
        {
            var adaKemeja = stok.Kemeja(p) > 0;
            var adaCelana = stok.Celana(p) > 0;

            if (adaKemeja && adaCelana)
            {
                stok.Ambil(p);
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

        return (bisa, belum, stok);
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
        StokPool pool,
        TniSizePrioritas size)
    {
        foreach (var p in kandidat) p.IsSizePrioritas = false;

        if (!size.Aktif)
        {
            var (b, bl) = Greedy(kandidat, pool);
            return new HasilBagi(b, bl, 0, 0, 0);
        }

        var stok = pool.Salin();
        // kuota dibatasi stok yang memang boleh dipakai kandidat ini (kunci satuan lain tidak)
        var kuotaK = size.KuotaKemeja(pool.TotalKemeja());
        var kuotaC = size.KuotaCelana(pool.TotalCelana());
        var stokPrioritas = kuotaK.Values.Sum() + kuotaC.Values.Sum();

        var tahap1 = new List<TniKandidatDto>();
        var diambil = new HashSet<int>();
        var pakai = 0;

        foreach (var p in kandidat.Where(x => size.JumlahCocok(x) > 0).OrderByDescending(size.JumlahCocok))
        {
            var sisaK = kuotaK.TryGetValue(p.PolaKemejaId, out var qk) && qk > 0;
            var sisaC = kuotaC.TryGetValue(p.PolaCelanaId, out var qc) && qc > 0;
            if (!sisaK && !sisaC) continue;   // kuota size-nya sudah habis -> tahap 2

            if (stok.Kemeja(p) <= 0 || stok.Celana(p) <= 0)
                continue;                      // pasangannya kosong -> tahap 2 (akan masuk "belum bisa")

            stok.Ambil(p);
            if (sisaK) { kuotaK[p.PolaKemejaId] = qk - 1; pakai++; }
            if (sisaC) { kuotaC[p.PolaCelanaId] = qc - 1; pakai++; }

            p.IsSizePrioritas = true;
            tahap1.Add(p);
            diambil.Add(p.PersonelId);
        }

        var (tahap2, belum) = Greedy(kandidat.Where(x => !diambil.Contains(x.PersonelId)), stok);

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
            // (satuan bergembok di rawatan ini memakai jatah kuncinya; kunci rawatan lain tidak terpakai)
            var satuanArea = kandidatArea.Select(x => x.SatuanId).Distinct().ToList();
            var bagi = Bagi(kandidatArea, data.Pool(satuanArea), size);

            // jumlah satuan yang bisa tuntas: tiap satuan dihitung dengan salinan
            // stok bebas yang SEGAR (angka antarsatuan bisa tumpang tindih)
            var satuanBisaTuntas = kandidatArea
                .GroupBy(x => x.SatuanId)
                .Count(g =>
                {
                    var (b, _) = Greedy(g.OrderBy(x => x.KodeRef), data.Pool(new[] { g.Key }));
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
                StokSizePrioritas = bagi.StokPrioritas,
                DikunciKemeja = satuanArea.Sum(data.DikunciKemeja),
                DikunciCelana = satuanArea.Sum(data.DikunciCelana)
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
        public bool IsKunciStok { get; set; }
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
                         CAST(CASE WHEN s.prioritas_at IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsPrioritas,
                         CAST(CASE WHEN s.kunci_stok_at IS NOT NULL THEN 1 ELSE 0 END AS bit) AS IsKunciStok
                  FROM tni.v_personel v
                  JOIN tni.satuan s ON s.satuan_id = v.satuan_id
                  WHERE v.order_id = @OrderId AND v.area_id = @AreaId
                  GROUP BY v.satuan_id, v.satuan_code, v.satuan_name, s.prioritas_at, s.kunci_stok_at",
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

            // salinan stok bebas yang SEGAR untuk tiap satuan (+ jatah kuncinya sendiri)
            var bagi = Bagi(kandidat, data.Pool(new[] { s.SatuanId }), size);

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
                IsKunciStok = s.IsKunciStok,
                DikunciKemeja = data.DikunciKemeja(s.SatuanId),
                DikunciCelana = data.DikunciCelana(s.SatuanId),
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
        var pool = data.Pool(new[] { satuanId });
        var bagi = Bagi(kandidat, pool, size);
        var (bisa, belum) = (bagi.Bisa, bagi.Belum);

        var kekurangan = HitungKekurangan(kandidat, data, pool);

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
            Kekurangan = kekurangan,
            TersediaKemeja = pool.TotalKemeja().Where(x => x.Value > 0).ToDictionary(x => x.Key, x => x.Value),
            TersediaCelana = pool.TotalCelana().Where(x => x.Value > 0).ToDictionary(x => x.Key, x => x.Value)
        };
    }

    // Kekurangan GABUNGAN beberapa satuan (mis. semua satuan berbintang satu rawatan).
    // Kebutuhan seluruh satuan DIJUMLAH DULU per pola, baru dikurangi stok bebas SEKALI --
    // BUKAN jumlah kekurangan per satuan (tiap satuan memakai stok bebas yang sama, jadi
    // menjumlah per satuan akan terlalu kecil). Satu panggilan SP saja.
    public async Task<List<TniKekuranganDto>> GetKekuranganGabunganAsync(int orderId, int areaId, IReadOnlyCollection<int> satuanIds)
    {
        if (satuanIds.Count == 0) return new();

        var data = await GetDataAsync(orderId, areaId, null);
        var kandidat = data.Kandidat.Where(x => satuanIds.Contains(x.SatuanId)).ToList();
        return HitungKekurangan(kandidat, data, data.Pool(satuanIds));
    }

    // Ringkasan kekurangan per pola = kebutuhan sisa (semua kandidat BELUM_CETAK yang diberikan)
    // dikurangi stok yang boleh mereka pakai (stok bebas tanpa kunci + jatah kunci satuan-satuan
    // itu sendiri). Tidak dihitung dari daftar "belum bisa", karena orang yang tertahan oleh
    // barang pasangannya tetap butuh pola ini.
    // Urutan = halaman Stok: kemeja dulu, lalu grup gender (P, PG, W, WH), varian, size.
    //
    // AdaPasangan (bintang, 2026-11-11): greedy dulu, lalu dari SISA stok -- orang yang tertahan
    // karena kemejanya kosong padahal celananya masih ada di sisa -> kemeja pola itu berbintang
    // (begitu kemeja itu masuk, setnya langsung jadi). Sebaliknya untuk celana. Sisa = setelah
    // semua yang "bisa dibuat" mengambil barangnya, jadi pasangan tidak dihitung dua kali.
    private static List<TniKekuranganDto> HitungKekurangan(List<TniKandidatDto> kandidat, DataMentah data, StokPool pool)
    {
        var tanpaUrut = new PolaUrut(string.Empty, 9, 0, 0);
        var stokK = pool.TotalKemeja();
        var stokC = pool.TotalCelana();

        var (_, belum, sisa) = GreedySisa(kandidat.OrderBy(x => x.SatuanCode).ThenBy(x => x.KodeRef), pool);
        var pasanganK = belum.Where(b => b.KemejaKurang && sisa.Celana(b.Personel) > 0)
                             .Select(b => b.Personel.PolaKemejaId).ToHashSet();
        var pasanganC = belum.Where(b => b.CelanaKurang && sisa.Kemeja(b.Personel) > 0)
                             .Select(b => b.Personel.PolaCelanaId).ToHashSet();

        return kandidat
            .GroupBy(p => p.PolaKemejaId)
            .Select(g => (Urut: data.UrutKemeja.GetValueOrDefault(g.Key) ?? tanpaUrut, Dto: new TniKekuranganDto
            {
                JenisItem = "KEMEJA",
                Kode = data.KodeKemeja.TryGetValue(g.Key, out var k) ? k : g.First().PolaKemejaKode,
                Kurang = g.Count() - Math.Max(0, stokK.GetValueOrDefault(g.Key)),
                AdaPasangan = pasanganK.Contains(g.Key)
            }))
            .Concat(kandidat
                .GroupBy(p => p.PolaCelanaId)
                .Select(g => (Urut: data.UrutCelana.GetValueOrDefault(g.Key) ?? tanpaUrut, Dto: new TniKekuranganDto
                {
                    JenisItem = "CELANA",
                    Kode = data.KodeCelana.TryGetValue(g.Key, out var c) ? c : g.First().PolaCelanaKode,
                    Kurang = g.Count() - Math.Max(0, stokC.GetValueOrDefault(g.Key)),
                    AdaPasangan = pasanganC.Contains(g.Key)
                })))
            .Where(x => x.Dto.Kurang > 0)
            .OrderBy(x => x.Dto.JenisItem == "KEMEJA" ? 0 : 1)
            .ThenBy(x => x.Urut.UrutGender)
            .ThenBy(x => x.Urut.UrutVarian)
            .ThenBy(x => x.Urut.UrutSize)
            .ThenBy(x => x.Dto.Kode)
            .Select(x => { x.Dto.GrupGender = x.Urut.Grup; return x.Dto; })
            .ToList();
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

    // Kunci stok satuan (alter_81): stok bebas disisihkan untuk kebutuhan satuan ini.
    public async Task<(bool Success, string Error)> SetKunciStokAsync(
        int satuanId, bool kunci, int userId, int? perangkatId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Satuan_Manage @Action = 'KUNCI_STOK', @Id = @Id,
                    @Kunci = @Kunci, @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@Id", satuanId),
                new SqlParameter("@Kunci", kunci),
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

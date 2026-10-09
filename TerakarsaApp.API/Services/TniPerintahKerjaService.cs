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

    // ---------------- per rawatan ----------------

    public async Task<List<TniRawatanDto>> GetRawatanAsync(int orderId)
    {
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
            var (bisa, _) = Greedy(kandidatArea, data.StokKemeja, data.StokCelana);

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
                BisaDibuat = bisa.Count,
                SatuanBisaTuntas = satuanBisaTuntas
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
    }

    // ---------------- daftar satuan satu rawatan ----------------

    // Urutan daftar:
    //   1. BISA TUNTAS dulu, dari sisa paling SEDIKIT
    //   2. sisanya dari BISA DIBUAT terbanyak
    //   3. satuan tanpa kandidat (sisa 0) paling bawah
    public async Task<List<TniSatuanSaranDto>> GetSatuanAsync(int orderId, int areaId)
    {
        var data = await GetDataAsync(orderId, areaId, null);

        var statistik = await _db.Database
            .SqlQueryRaw<SatuanStatistik>(
                @"SELECT v.satuan_id AS SatuanId, v.satuan_code AS SatuanCode, v.satuan_name AS SatuanName,
                         COUNT(*) AS TotalPersonel,
                         SUM(CASE WHEN v.status_progres IN ('MASUK_BOX','TERKIRIM') THEN 1 ELSE 0 END) AS SudahMasukBox
                  FROM tni.v_personel v
                  WHERE v.order_id = @OrderId AND v.area_id = @AreaId
                  GROUP BY v.satuan_id, v.satuan_code, v.satuan_name",
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
            var (bisa, _) = Greedy(kandidat, data.StokKemeja, data.StokCelana);

            hasil.Add(new TniSatuanSaranDto
            {
                SatuanId = s.SatuanId,
                SatuanCode = s.SatuanCode,
                SatuanName = s.SatuanName,
                TotalPersonel = s.TotalPersonel,
                SudahMasukBox = s.SudahMasukBox,
                Sisa = kandidat.Count,
                BisaDibuat = bisa.Count
            });
        }

        return hasil
            .OrderByDescending(x => x.BisaTuntas)              // 1. bisa tuntas dulu
            .ThenBy(x => x.BisaTuntas ? x.Sisa : int.MaxValue) //    sisa paling sedikit
            .ThenBy(x => x.Sisa == 0)                          // 3. tanpa kandidat di bawah
            .ThenByDescending(x => x.BisaDibuat)               // 2. bisa dibuat terbanyak
            .ThenBy(x => x.SatuanCode)
            .ToList();
    }

    // ---------------- detail satu satuan ----------------

    public async Task<TniSatuanDetailDto> GetSatuanDetailAsync(int orderId, int satuanId)
    {
        var data = await GetDataAsync(orderId, null, satuanId);

        var kandidat = data.Kandidat.OrderBy(x => x.KodeRef).ToList();
        var (bisa, belum) = Greedy(kandidat, data.StokKemeja, data.StokCelana);

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

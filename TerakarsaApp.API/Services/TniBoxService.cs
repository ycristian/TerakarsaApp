using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 67: box & scan "Masuk Box" PDH TNI AD.
// Status box selalu dari SP (turunan packed_at/shipped_at) -- service tidak
// menghitung status sendiri.
public class TniBoxService
{
    private readonly AppDbContext _db;

    public TniBoxService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<TniBoxListItemDto>> GetListAsync(
        int orderId, int? areaId, int? satuanId, string? status, bool? gabungan, string? cari = null)
    {
        return await _db.Database
            .SqlQueryRaw<TniBoxListItemDto>(
                @"EXEC tni.SIS_Box_List @OrderId = @OrderId, @AreaId = @AreaId,
                    @SatuanId = @SatuanId, @Status = @Status, @Gabungan = @Gabungan, @Cari = @Cari",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@AreaId", areaId ?? (object)DBNull.Value),
                new SqlParameter("@SatuanId", satuanId ?? (object)DBNull.Value),
                new SqlParameter("@Status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status),
                new SqlParameter("@Gabungan", gabungan.HasValue ? gabungan.Value : (object)DBNull.Value),
                new SqlParameter("@Cari", string.IsNullOrWhiteSpace(cari) ? DBNull.Value : cari.Trim()))
            .ToListAsync();
    }

    public async Task<List<TniBoxListItemDto>> GetTerbukaAsync(int orderId, int? areaId, int? satuanId)
        => await GetListAsync(orderId, areaId, satuanId, "TERBUKA", null);

    // SIS_Box_GetById mengembalikan 3 result set -- EF Core SqlQueryRaw hanya mendukung
    // satu, jadi pakai SqlCommand mentah + reader.NextResultAsync()
    // (pola sama dengan ReportBundleService.GetArticleProgressAsync).
    public async Task<TniBoxDetailDto> GetByIdAsync(int boxId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "tni.SIS_Box_GetById";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@BoxId", boxId));

            var result = new TniBoxDetailDto();
            using var reader = await cmd.ExecuteReaderAsync();

            // (1) header
            if (await reader.ReadAsync())
            {
                result.Header = new TniBoxHeaderDto
                {
                    BoxId = reader.GetInt32(reader.GetOrdinal("BoxId")),
                    BoxCode = reader.GetString(reader.GetOrdinal("BoxCode")),
                    BoxNo = reader.GetInt32(reader.GetOrdinal("BoxNo")),
                    OrderId = reader.GetInt32(reader.GetOrdinal("OrderId")),
                    OrderName = reader.GetString(reader.GetOrdinal("OrderName")),
                    Instansi = Str(reader, "Instansi"),
                    AreaId = reader.GetInt32(reader.GetOrdinal("AreaId")),
                    AreaCode = reader.GetString(reader.GetOrdinal("AreaCode")),
                    AreaName = reader.GetString(reader.GetOrdinal("AreaName")),
                    SatuanId = Int(reader, "SatuanId"),
                    SatuanCode = Str(reader, "SatuanCode"),
                    SatuanName = reader.GetString(reader.GetOrdinal("SatuanName")),
                    Gabungan = reader.GetBoolean(reader.GetOrdinal("Gabungan")),
                    Kapasitas = reader.GetInt32(reader.GetOrdinal("Kapasitas")),
                    Isi = reader.GetInt32(reader.GetOrdinal("Isi")),
                    JumlahSatuan = reader.GetInt32(reader.GetOrdinal("JumlahSatuan")),
                    PackedAt = Dt(reader, "PackedAt"),
                    PackedByNama = Str(reader, "PackedByNama"),
                    ShippedAt = Dt(reader, "ShippedAt"),
                    ShippedByNama = Str(reader, "ShippedByNama"),
                    Keterangan = Str(reader, "Keterangan"),
                    Status = reader.GetString(reader.GetOrdinal("Status"))
                };
            }

            // (2) isi
            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Isi.Add(new TniBoxIsiDto
                {
                    PersonelId = reader.GetInt32(reader.GetOrdinal("PersonelId")),
                    UrutDalamBox = Int(reader, "UrutDalamBox"),
                    KodeRef = reader.GetString(reader.GetOrdinal("KodeRef")),
                    Pangkat = Str(reader, "Pangkat"),
                    Nama = reader.GetString(reader.GetOrdinal("Nama")),
                    Nrp = reader.GetString(reader.GetOrdinal("Nrp")),
                    SatuanCode = reader.GetString(reader.GetOrdinal("SatuanCode")),
                    SatuanName = reader.GetString(reader.GetOrdinal("SatuanName")),
                    PolaKemejaKode = reader.GetString(reader.GetOrdinal("PolaKemejaKode")),
                    PolaCelanaKode = reader.GetString(reader.GetOrdinal("PolaCelanaKode")),
                    BoxedAt = Dt(reader, "BoxedAt"),
                    AreaCode = reader.GetString(reader.GetOrdinal("AreaCode")),
                    AreaName = reader.GetString(reader.GetOrdinal("AreaName"))
                });
            }

            // (3) rekap pola
            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Rekap.Add(new TniBoxRekapDto
                {
                    JenisItem = reader.GetString(reader.GetOrdinal("JenisItem")),
                    Kode = reader.GetString(reader.GetOrdinal("Kode")),
                    Jumlah = reader.GetInt32(reader.GetOrdinal("Jumlah"))
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    private static string? Str(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetString(i);
    }

    private static int? Int(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetInt32(i);
    }

    private static DateTime? Dt(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetDateTime(i);
    }

    // ---------------- mutasi ----------------

    public async Task<(bool Success, string Error, TniBoxCreateHasilDto? Hasil)> CreateAsync(
        int orderId, TniBoxCreateRequest request, int userId)
    {
        try
        {
            var result = await _db.Database
                .SqlQueryRaw<TniBoxCreateHasilDto>(
                    @"EXEC tni.SIS_Box_Manage @Action = 'CREATE', @OrderId = @OrderId,
                        @SatuanId = @SatuanId, @AreaId = @AreaId, @Kapasitas = @Kapasitas, @UserId = @UserId",
                    new SqlParameter("@OrderId", orderId),
                    new SqlParameter("@SatuanId", request.SatuanId ?? (object)DBNull.Value),
                    new SqlParameter("@AreaId", request.AreaId ?? (object)DBNull.Value),
                    new SqlParameter("@Kapasitas", request.Kapasitas ?? (object)DBNull.Value),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error)> TutupAsync(int boxId, int userId, int? perangkatId = null)
        => await AksiAsync("CLOSE", boxId, userId, perangkatId);

    public async Task<(bool Success, string Error)> KirimAsync(int boxId, int userId, int? perangkatId = null)
        => await AksiAsync("SHIP", boxId, userId, perangkatId);

    // Batal kirim: TERKIRIM -> TERTUTUP. Alasan wajib (ditegakkan SP).
    public Task<(bool Success, string Error)> BatalKirimAsync(
        int boxId, string? alasan, int userId, int? perangkatId = null)
        => BatalAsync("UNSHIP", boxId, alasan, userId, perangkatId);

    // Batal tutup (2026-10-07): TERTUTUP -> TERBUKA, bisa discan lagi. Alasan wajib.
    public Task<(bool Success, string Error)> BatalTutupAsync(
        int boxId, string? alasan, int userId, int? perangkatId = null)
        => BatalAsync("UNCLOSE", boxId, alasan, userId, perangkatId);

    private async Task<(bool Success, string Error)> BatalAsync(
        string action, int boxId, string? alasan, int userId, int? perangkatId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Box_Manage @Action = @Action, @BoxId = @BoxId, @Alasan = @Alasan,
                    @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@Action", action),
                new SqlParameter("@BoxId", boxId),
                new SqlParameter("@Alasan", (object?)alasan ?? DBNull.Value),
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", (object?)perangkatId ?? DBNull.Value));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> HapusAsync(int boxId, string? alasan, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC tni.SIS_Box_Manage @Action = 'DELETE', @BoxId = @BoxId, @Alasan = @Alasan, @UserId = @UserId",
                new SqlParameter("@BoxId", boxId),
                new SqlParameter("@Alasan", (object?)alasan ?? DBNull.Value),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    private async Task<(bool Success, string Error)> AksiAsync(
        string action, int boxId, int userId, int? perangkatId = null)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Box_Manage @Action = @Action, @BoxId = @BoxId,
                    @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@Action", action),
                new SqlParameter("@BoxId", boxId),
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // ---------------- scan masuk box ----------------

    public async Task<TniScanHasilDto> MasukBoxAsync(
        string kode, int boxId, int userId, int? perangkatId = null, bool paksa = false)
    {
        // paksa = petugas sudah konfirmasi beda satuan/rawatan (Hasil KONFIRMASI, 2026-10-07)
        var result = await _db.Database
            .SqlQueryRaw<TniScanHasilDto>(
                @"EXEC tni.SIS_Scan_MasukBox @Kode = @Kode, @BoxId = @BoxId,
                    @UserId = @UserId, @PerangkatId = @PerangkatId, @Paksa = @Paksa",
                new SqlParameter("@Kode", kode ?? string.Empty),
                new SqlParameter("@BoxId", boxId),
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value),
                new SqlParameter("@Paksa", paksa))
            .ToListAsync();

        return result.FirstOrDefault() ?? new TniScanHasilDto
        {
            Hasil = "TIDAK_DIKENAL",
            Pesan = "Kode tidak dikenal."
        };
    }
}

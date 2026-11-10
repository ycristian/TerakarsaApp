using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 63: beranda module & halaman Personel PDH TNI AD.
// Status selalu dari tni.v_personel lewat SP -- service tidak menghitung status.
public class TniPersonelService
{
    private readonly AppDbContext _db;

    public TniPersonelService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<TniBerandaSummaryDto?> GetSummaryAsync(int orderId)
    {
        var result = await _db.Database
            .SqlQueryRaw<TniBerandaSummaryDto>(
                "EXEC tni.SIS_Beranda_Summary @OrderId = @OrderId",
                new SqlParameter("@OrderId", orderId))
            .ToListAsync();

        return result.FirstOrDefault();
    }

    // Kartu stok beranda. SIS_Beranda_Stok punya 2 result set -> reader mentah.
    // "Bisa di-set" = greedy atas saldo per pola (sama seperti Perintah Kerja):
    // personel DICETAK dulu (stoknya sudah dijatah = lock), lalu BELUM_CETAK dari sisanya.
    public async Task<TniBerandaStokDto> GetBerandaStokAsync(int orderId)
    {
        var hasil = new TniBerandaStokDto();
        var saldoK = new Dictionary<int, int>();
        var saldoC = new Dictionary<int, int>();

        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "tni.SIS_Beranda_Stok";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.CommandTimeout = 120;
            cmd.Parameters.Add(new SqlParameter("@OrderId", orderId));

            using var reader = await cmd.ExecuteReaderAsync();

            // (1) per pola
            while (await reader.ReadAsync())
            {
                var kemeja = reader.GetString(0) == "KEMEJA";
                var polaId = reader.GetInt32(1);
                var masuk = reader.GetInt32(2);
                var keluarLain = reader.GetInt32(3);
                var saldo = Math.Max(reader.GetInt32(4), 0);
                var dijatah = reader.GetInt32(5);

                var j = kemeja ? hasil.Kemeja : hasil.Celana;
                j.Masuk += masuk + keluarLain;
                j.Lock += Math.Min(saldo, dijatah);
                j.Unlock += Math.Max(saldo - dijatah, 0);
                (kemeja ? saldoK : saldoC)[polaId] = saldo;
            }

            // (2) personel belum dapat set, DICETAK dulu
            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                var k = reader.GetInt32(0);
                var c = reader.GetInt32(1);
                if (saldoK.GetValueOrDefault(k) <= 0 || saldoC.GetValueOrDefault(c) <= 0) continue;

                saldoK[k]--;
                saldoC[c]--;
                if (reader.GetBoolean(2)) hasil.BisaDisetLock++;
                else hasil.BisaDisetUnlock++;
            }
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }

        return hasil;
    }

    public async Task<TniPersonelListResult> GetListAsync(
        int orderId, string? search, int? areaId, int? satuanId, string? status,
        bool perluReview, int pageNumber, int pageSize,
        int? polaKemejaId = null, int? polaCelanaId = null)
    {
        var items = await _db.Database
            .SqlQueryRaw<TniPersonelListItemDto>(
                @"EXEC tni.SIS_Personel_List
                    @OrderId = @OrderId, @Search = @Search, @AreaId = @AreaId,
                    @SatuanId = @SatuanId, @Status = @Status, @PerluReview = @PerluReview,
                    @PageNumber = @PageNumber, @PageSize = @PageSize,
                    @PolaKemejaId = @PolaKemejaId, @PolaCelanaId = @PolaCelanaId",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@Search", string.IsNullOrWhiteSpace(search) ? DBNull.Value : search),
                new SqlParameter("@AreaId", areaId ?? (object)DBNull.Value),
                new SqlParameter("@SatuanId", satuanId ?? (object)DBNull.Value),
                new SqlParameter("@Status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status),
                new SqlParameter("@PerluReview", perluReview),
                new SqlParameter("@PageNumber", pageNumber),
                new SqlParameter("@PageSize", pageSize),
                new SqlParameter("@PolaKemejaId", polaKemejaId ?? (object)DBNull.Value),
                new SqlParameter("@PolaCelanaId", polaCelanaId ?? (object)DBNull.Value))
            .ToListAsync();

        return new TniPersonelListResult
        {
            Items = items,
            // SP mengulang total di tiap baris (COUNT(*) OVER ()); halaman kosong = 0.
            TotalCount = items.FirstOrDefault()?.TotalCount ?? 0
        };
    }

    // Prompt 89: data laporan PDF. tni.SIS_LaporanPersonel punya 3 result set --
    // SqlQueryRaw hanya membaca satu, jadi pakai reader + NextResultAsync()
    // (pola sama dengan TniBoxService.GetByIdAsync).
    public async Task<TniLaporanPersonelDto> GetLaporanAsync(
        int orderId, string? search, int? areaId, int? satuanId, string? status, bool perluReview,
        int? polaKemejaId = null, int? polaCelanaId = null)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "tni.SIS_LaporanPersonel";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@OrderId", orderId));
            cmd.Parameters.Add(new SqlParameter("@Search", string.IsNullOrWhiteSpace(search) ? DBNull.Value : search));
            cmd.Parameters.Add(new SqlParameter("@AreaId", areaId ?? (object)DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@SatuanId", satuanId ?? (object)DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@Status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status));
            cmd.Parameters.Add(new SqlParameter("@PerluReview", perluReview));
            cmd.Parameters.Add(new SqlParameter("@PolaKemejaId", polaKemejaId ?? (object)DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@PolaCelanaId", polaCelanaId ?? (object)DBNull.Value));

            var result = new TniLaporanPersonelDto
            {
                Status = string.IsNullOrWhiteSpace(status) ? null : status,
                Search = string.IsNullOrWhiteSpace(search) ? null : search.Trim(),
                PerluReview = perluReview
            };

            using var reader = await cmd.ExecuteReaderAsync();

            // (1) header
            if (await reader.ReadAsync())
            {
                result.Header = new TniLaporanPersonelHeaderDto
                {
                    OrderName = reader.GetString(reader.GetOrdinal("OrderName")),
                    Instansi = Str(reader, "Instansi"),
                    AreaCode = Str(reader, "AreaCode"),
                    AreaName = Str(reader, "AreaName"),
                    SatuanCode = Str(reader, "SatuanCode"),
                    SatuanName = Str(reader, "SatuanName"),
                    TotalBaris = reader.GetInt32(reader.GetOrdinal("TotalBaris")),
                    JumlahSatuan = reader.GetInt32(reader.GetOrdinal("JumlahSatuan")),
                    PolaKemejaKode = Str(reader, "PolaKemejaKode"),
                    PolaCelanaKode = Str(reader, "PolaCelanaKode")
                };
            }

            // (2) baris personel
            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Baris.Add(new TniLaporanPersonelBarisDto
                {
                    KodeRef = reader.GetString(reader.GetOrdinal("KodeRef")),
                    SatuanCode = reader.GetString(reader.GetOrdinal("SatuanCode")),
                    SatuanName = reader.GetString(reader.GetOrdinal("SatuanName")),
                    Pangkat = Str(reader, "Pangkat"),
                    Nama = reader.GetString(reader.GetOrdinal("Nama")),
                    Nrp = reader.GetString(reader.GetOrdinal("Nrp")),
                    NoHp = Str(reader, "NoHp"),
                    Gender = reader.GetString(reader.GetOrdinal("Gender")),
                    PolaKemejaKode = reader.GetString(reader.GetOrdinal("PolaKemejaKode")),
                    PolaCelanaKode = reader.GetString(reader.GetOrdinal("PolaCelanaKode")),
                    BoxNo = Int(reader, "BoxNo"),
                    BoxCode = Str(reader, "BoxCode")
                });
            }

            // (3) rekap box
            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Box.Add(new TniLaporanPersonelBoxDto
                {
                    BoxNo = reader.GetInt32(reader.GetOrdinal("BoxNo")),
                    BoxCode = reader.GetString(reader.GetOrdinal("BoxCode")),
                    Gabungan = reader.GetBoolean(reader.GetOrdinal("Gabungan")),
                    Status = reader.GetString(reader.GetOrdinal("Status")),
                    Isi = reader.GetInt32(reader.GetOrdinal("Isi")),
                    IsiDariLingkup = reader.GetInt32(reader.GetOrdinal("IsiDariLingkup")),
                    PackedAt = Dt(reader, "PackedAt"),
                    ShippedAt = Dt(reader, "ShippedAt")
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

    public async Task<TniPersonelDetailDto?> GetByIdAsync(int id)
    {
        var result = await _db.Database
            .SqlQueryRaw<TniPersonelDetailDto>(
                "EXEC tni.SIS_Personel_GetById @Id = @Id",
                new SqlParameter("@Id", id))
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<List<TniWilayahRowDto>> GetWilayahAsync(int orderId)
    {
        return await _db.Database
            .SqlQueryRaw<TniWilayahRowDto>(
                "EXEC tni.SIS_Wilayah_List @OrderId = @OrderId",
                new SqlParameter("@OrderId", orderId))
            .ToListAsync();
    }

    public async Task<(bool Success, string Error)> UpdateAsync(int id, TniPersonelUpdateRequest req, int userId)
        => await ExecAsync(
            @"EXEC tni.SIS_Personel_Manage @Action = 'UPDATE', @Id = @Id, @Nrp = @Nrp,
                @Nama = @Nama, @Pangkat = @Pangkat, @NoHp = @NoHp, @Gender = @Gender, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@Nrp", req.Nrp ?? string.Empty),
            new SqlParameter("@Nama", req.Nama ?? string.Empty),
            new SqlParameter("@Pangkat", (object?)req.Pangkat ?? DBNull.Value),
            new SqlParameter("@NoHp", (object?)req.NoHp ?? DBNull.Value),
            new SqlParameter("@Gender", req.Gender ?? string.Empty),
            new SqlParameter("@UserId", userId));

    public async Task<(bool Success, string Error)> SetPolaAsync(int id, TniPersonelSetPolaRequest req, int userId)
        => await ExecAsync(
            @"EXEC tni.SIS_Personel_Manage @Action = 'SET_POLA', @Id = @Id,
                @PolaKemejaId = @PolaKemejaId, @PolaCelanaId = @PolaCelanaId, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@PolaKemejaId", req.PolaKemejaId),
            new SqlParameter("@PolaCelanaId", req.PolaCelanaId),
            new SqlParameter("@UserId", userId));

    public async Task<(bool Success, string Error)> MarkReviewedAsync(int id, string? catatan, int userId)
        => await ExecAsync(
            "EXEC tni.SIS_Personel_Manage @Action = 'MARK_REVIEWED', @Id = @Id, @Catatan = @Catatan, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@Catatan", (object?)catatan ?? DBNull.Value),
            new SqlParameter("@UserId", userId));

    public async Task<(bool Success, string Error)> DeleteAsync(int id, string? alasan, int userId)
        => await ExecAsync(
            "EXEC tni.SIS_Personel_Manage @Action = 'DELETE', @Id = @Id, @Catatan = @Catatan, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@Catatan", (object?)alasan ?? DBNull.Value),
            new SqlParameter("@UserId", userId));

    private async Task<(bool Success, string Error)> ExecAsync(string sql, params SqlParameter[] p)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(sql, p);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}

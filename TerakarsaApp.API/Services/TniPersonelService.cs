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

    public async Task<TniPersonelListResult> GetListAsync(
        int orderId, string? search, int? areaId, int? satuanId, string? status,
        bool perluReview, int pageNumber, int pageSize)
    {
        var items = await _db.Database
            .SqlQueryRaw<TniPersonelListItemDto>(
                @"EXEC tni.SIS_Personel_List
                    @OrderId = @OrderId, @Search = @Search, @AreaId = @AreaId,
                    @SatuanId = @SatuanId, @Status = @Status, @PerluReview = @PerluReview,
                    @PageNumber = @PageNumber, @PageSize = @PageSize",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@Search", string.IsNullOrWhiteSpace(search) ? DBNull.Value : search),
                new SqlParameter("@AreaId", areaId ?? (object)DBNull.Value),
                new SqlParameter("@SatuanId", satuanId ?? (object)DBNull.Value),
                new SqlParameter("@Status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status),
                new SqlParameter("@PerluReview", perluReview),
                new SqlParameter("@PageNumber", pageNumber),
                new SqlParameter("@PageSize", pageSize))
            .ToListAsync();

        return new TniPersonelListResult
        {
            Items = items,
            // SP mengulang total di tiap baris (COUNT(*) OVER ()); halaman kosong = 0.
            TotalCount = items.FirstOrDefault()?.TotalCount ?? 0
        };
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

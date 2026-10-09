using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 68: pengajuan & persetujuan pembatalan scan PDH TNI AD.
//
// Semua validasi (termasuk pemeriksaan ULANG saat SETUJUI) ada di
// tni.SIS_Pembatalan_Manage; service hanya menerjemahkan RAISERROR SP menjadi
// pesan yang bisa ditampilkan UI.
public class TniPembatalanService
{
    private readonly AppDbContext _db;

    public TniPembatalanService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<TniPembatalanDto>> GetListAsync(
        int orderId, string? status, int pageNumber, int pageSize)
    {
        return await _db.Database
            .SqlQueryRaw<TniPembatalanDto>(
                @"EXEC tni.SIS_Pembatalan_List @OrderId = @OrderId, @Status = @Status,
                    @PageNumber = @PageNumber, @PageSize = @PageSize",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@Status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status),
                new SqlParameter("@PageNumber", pageNumber <= 0 ? 1 : pageNumber),
                new SqlParameter("@PageSize", pageSize <= 0 ? 30 : pageSize))
            .ToListAsync();
    }

    public async Task<List<TniPembatalanDto>> GetByPersonelAsync(int personelId)
    {
        return await _db.Database
            .SqlQueryRaw<TniPembatalanDto>(
                "EXEC tni.SIS_Pembatalan_ByPersonel @PersonelId = @PersonelId",
                new SqlParameter("@PersonelId", personelId))
            .ToListAsync();
    }

    public async Task<TniPembatalanAksiHasil> AjukanAsync(
        TniPembatalanAjukanRequest request, int userId, int? perangkatId = null)
        => await ManageAsync(
            @"EXEC tni.SIS_Pembatalan_Manage @Action = 'AJUKAN', @PersonelId = @PersonelId,
                @Jenis = @Jenis, @Alasan = @Alasan, @UserId = @UserId, @PerangkatId = @PerangkatId",
            new SqlParameter("@PersonelId", request.PersonelId),
            new SqlParameter("@Jenis", request.Jenis ?? string.Empty),
            new SqlParameter("@Alasan", request.Alasan ?? string.Empty),
            new SqlParameter("@UserId", userId),
            new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value));

    public async Task<TniPembatalanAksiHasil> SetujuiAsync(int id, string? catatan, int userId)
        => await ManageAsync(
            @"EXEC tni.SIS_Pembatalan_Manage @Action = 'SETUJUI', @Id = @Id,
                @Catatan = @Catatan, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@Catatan", (object?)catatan ?? DBNull.Value),
            new SqlParameter("@UserId", userId));

    public async Task<TniPembatalanAksiHasil> TolakAsync(int id, string? catatan, int userId)
        => await ManageAsync(
            @"EXEC tni.SIS_Pembatalan_Manage @Action = 'TOLAK', @Id = @Id,
                @Catatan = @Catatan, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@Catatan", (object?)catatan ?? DBNull.Value),
            new SqlParameter("@UserId", userId));

    private async Task<TniPembatalanAksiHasil> ManageAsync(string sql, params SqlParameter[] parameters)
    {
        try
        {
            var result = await _db.Database
                .SqlQueryRaw<TniPembatalanHasilDto>(sql, parameters)
                .ToListAsync();

            return new TniPembatalanAksiHasil
            {
                Ok = true,
                Data = result.FirstOrDefault()
            };
        }
        catch (SqlException ex)
        {
            return new TniPembatalanAksiHasil { Ok = false, Pesan = ex.Message };
        }
    }
}

using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.ManualOutputs;

namespace TerakarsaApp.API.Services;

// Prompt 83: output manual (manual_outputs).
//
// Semua aturan ditegakkan di SP (deskripsi wajib, catatan wajib kalau qty minus, baris
// sudah lock tidak boleh diubah, divisi diambil dari resource, dst) -- service ini hanya
// meneruskan parameter dan mengembalikan pesan error SP APA ADANYA supaya prefix 'LOCKED|'
// sampai ke client tanpa diubah (pola sama dengan WorkflowLockService).
//
// TIDAK ADA parameter harga di seluruh class ini, dan memang tidak boleh ada: harga melekat
// ke lock item dan hanya bisa diubah lewat PayrollRekapService.UpdateLockItemPriceAsync.
//
// Lihat sql/sp_ManualOutput_Manage.sql & sql/sp_ManualOutput_Select.sql.
public class ManualOutputService
{
    private readonly AppDbContext _db;

    public ManualOutputService(AppDbContext db)
    {
        _db = db;
    }

    // ---- Tab OUT stasiun: baris satu divisi (belum lock + yang sudah lock, 90 hari) ----
    public async Task<List<ManualOutputRowDto>> GetStationListAsync(int divisionId, int daysBack = 90)
    {
        var parameters = new[]
        {
            new SqlParameter("@DivisionId", divisionId),
            new SqlParameter("@DaysBack", daysBack)
        };

        return await _db.Database
            .SqlQueryRaw<ManualOutputRowDto>(
                "EXEC SIS_ManualOutput_StationList @DivisionId = @DivisionId, @DaysBack = @DaysBack",
                parameters)
            .ToListAsync();
    }

    // ---- Halaman admin "Output Manual" ----
    public async Task<List<ManualOutputAdminRowDto>> GetAdminListAsync(
        bool onlyUnlinked, int? divisionId, int? payrollPeriodId, int? resourceId, string? search)
    {
        var parameters = new[]
        {
            new SqlParameter("@OnlyUnlinked", onlyUnlinked),
            new SqlParameter("@DivisionId", (object?)divisionId ?? DBNull.Value),
            new SqlParameter("@PayrollPeriodId", (object?)payrollPeriodId ?? DBNull.Value),
            new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value),
            new SqlParameter("@Search", (object?)search ?? DBNull.Value)
        };

        return await _db.Database
            .SqlQueryRaw<ManualOutputAdminRowDto>(
                "EXEC SIS_ManualOutput_List @OnlyUnlinked = @OnlyUnlinked, @DivisionId = @DivisionId, " +
                "@PayrollPeriodId = @PayrollPeriodId, @ResourceId = @ResourceId, @Search = @Search",
                parameters)
            .ToListAsync();
    }

    // ---- Simpan dari stasiun ----
    // @ResourceId = operator sesi stasiun, @UserId = user sistem station_system. Divisi
    // TIDAK dikirim: SP menyalinnya dari resources.division_id.
    public async Task<(bool Success, string Error)> SaveAsync(
        ManualOutputSaveRequest request, int resourceId, int userId)
    {
        var isUpdate = request.ManualOutputId.HasValue && request.ManualOutputId.Value > 0;

        var parameters = new[]
        {
            new SqlParameter("@Action", isUpdate ? "UPDATE" : "CREATE"),
            new SqlParameter("@ManualOutputId", (object?)request.ManualOutputId ?? DBNull.Value),
            new SqlParameter("@ResourceId", resourceId),
            new SqlParameter("@ArticleId", (object?)request.ArticleId ?? DBNull.Value),
            new SqlParameter("@WorkDescription", (object?)request.WorkDescription ?? DBNull.Value),
            new SqlParameter("@SizeName", (object?)request.SizeName ?? DBNull.Value),
            new SqlParameter("@Qty", request.Qty),
            new SqlParameter("@RejectQty", request.RejectQty),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_ManualOutput_Manage @Action = @Action, @ManualOutputId = @ManualOutputId, " +
                "@ResourceId = @ResourceId, @ArticleId = @ArticleId, @WorkDescription = @WorkDescription, " +
                "@SizeName = @SizeName, @Qty = @Qty, @RejectQty = @RejectQty, @Note = @Note, @UserId = @UserId",
                parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int manualOutputId, int resourceId, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "DELETE"),
            new SqlParameter("@ManualOutputId", manualOutputId),
            new SqlParameter("@ResourceId", resourceId),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_ManualOutput_Manage @Action = @Action, @ManualOutputId = @ManualOutputId, " +
                "@ResourceId = @ResourceId, @UserId = @UserId",
                parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // ---- "Hubungkan ke Artikel" massal (admin) ----
    // Boleh untuk baris yang SUDAH lock -- menempelkan artikel tidak mengubah fakta qty.
    public async Task<(ManualOutputLinkArticleResultDto? Result, string Error)> LinkArticleAsync(
        IEnumerable<int> manualOutputIds, int articleId, int userId)
    {
        var csv = string.Join(",", manualOutputIds.Distinct());

        var parameters = new[]
        {
            new SqlParameter("@ManualOutputIds", csv),
            new SqlParameter("@ArticleId", articleId),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<ManualOutputLinkArticleResultDto>(
                    "EXEC SIS_ManualOutput_LinkArticle @ManualOutputIds = @ManualOutputIds, " +
                    "@ArticleId = @ArticleId, @UserId = @UserId",
                    parameters)
                .ToListAsync();

            return (rows.FirstOrDefault() ?? new ManualOutputLinkArticleResultDto(), string.Empty);
        }
        catch (SqlException ex)
        {
            return (null, ex.Message);
        }
    }
}

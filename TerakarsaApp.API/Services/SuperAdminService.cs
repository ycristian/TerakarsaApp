using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.SuperAdmin;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.API.Services;

// Prompt 29: koreksi data langsung bundle & workflow log yang melewati guard normal --
// lihat sql/sp_SuperAdmin_Manage.sql. SENGAJA tidak menyentuh BundleService/WorkflowLogService
// (SIS_Bundle_Manage/SIS_WorkflowLog_Manage) sama sekali -- semua mutasi di sini lewat SP baru.
public class SuperAdminService
{
    private readonly AppDbContext _db;

    public SuperAdminService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<SuperAdminBundleSearchResultDto>> SearchBundlesAsync(string? search)
    {
        var searchParam = new SqlParameter("@Search", (object?)search ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<SuperAdminBundleSearchResultDto>(
                "EXEC SIS_SuperAdmin_BundleSearch @Search = @Search", searchParam)
            .ToListAsync();
    }

    // SIS_SuperAdmin_BundleDetail mengembalikan 3 result set (info, opsi ukuran, log) --
    // sama pola dengan BundleService.GetScanInfoAsync (EF Core SqlQueryRaw hanya mendukung
    // satu result set per panggilan).
    public async Task<SuperAdminBundleDetailDto?> GetBundleDetailAsync(int bundleId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_SuperAdmin_BundleDetail";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@BundleId", bundleId));

            using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return null;

            var bundle = new SuperAdminBundleInfoDto
            {
                BundleId = reader.GetInt32(reader.GetOrdinal("BundleId")),
                ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                ArticleSizeId = reader.GetInt32(reader.GetOrdinal("ArticleSizeId")),
                SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                Serial = reader.GetString(reader.GetOrdinal("Serial")),
                BundleNo = reader.GetInt32(reader.GetOrdinal("BundleNo")),
                BundleLetter = reader.IsDBNull(reader.GetOrdinal("BundleLetter")) ? null : reader.GetString(reader.GetOrdinal("BundleLetter")),
                Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                Style = reader.IsDBNull(reader.GetOrdinal("Style")) ? null : reader.GetString(reader.GetOrdinal("Style")),
                Color = reader.IsDBNull(reader.GetOrdinal("Color")) ? null : reader.GetString(reader.GetOrdinal("Color")),
            };

            await reader.NextResultAsync();
            var sizeOptions = new List<ArticleSizeOptionDto>();
            while (await reader.ReadAsync())
            {
                sizeOptions.Add(new ArticleSizeOptionDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                });
            }

            await reader.NextResultAsync();
            var logs = new List<WorkflowLogDto>();
            while (await reader.ReadAsync())
            {
                logs.Add(new WorkflowLogDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    BundleId = reader.IsDBNull(reader.GetOrdinal("BundleId")) ? null : reader.GetInt32(reader.GetOrdinal("BundleId")),
                    BundleSerial = reader.IsDBNull(reader.GetOrdinal("BundleSerial")) ? null : reader.GetString(reader.GetOrdinal("BundleSerial")),
                    ArticleSizeId = reader.IsDBNull(reader.GetOrdinal("ArticleSizeId")) ? null : reader.GetInt32(reader.GetOrdinal("ArticleSizeId")),
                    SizeName = reader.IsDBNull(reader.GetOrdinal("SizeName")) ? null : reader.GetString(reader.GetOrdinal("SizeName")),
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    ResourceId = reader.IsDBNull(reader.GetOrdinal("ResourceId")) ? null : reader.GetInt32(reader.GetOrdinal("ResourceId")),
                    ResourceName = reader.IsDBNull(reader.GetOrdinal("ResourceName")) ? null : reader.GetString(reader.GetOrdinal("ResourceName")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyRejectPrint = reader.GetInt32(reader.GetOrdinal("QtyRejectPrint")),
                    QtyRejectFabric = reader.GetInt32(reader.GetOrdinal("QtyRejectFabric")),
                    QtyRejectSewing = reader.GetInt32(reader.GetOrdinal("QtyRejectSewing")),
                    QtyRejectRework = reader.GetInt32(reader.GetOrdinal("QtyRejectRework")),
                    QtyLost = reader.GetInt32(reader.GetOrdinal("QtyLost")),
                    LogType = reader.GetString(reader.GetOrdinal("LogType")),
                    Remark = reader.IsDBNull(reader.GetOrdinal("Remark")) ? null : reader.GetString(reader.GetOrdinal("Remark")),
                    TargetDivisionId = reader.IsDBNull(reader.GetOrdinal("TargetDivisionId")) ? null : reader.GetInt32(reader.GetOrdinal("TargetDivisionId")),
                    TargetDivisionName = reader.IsDBNull(reader.GetOrdinal("TargetDivisionName")) ? null : reader.GetString(reader.GetOrdinal("TargetDivisionName")),
                    ReceivedAt = reader.IsDBNull(reader.GetOrdinal("ReceivedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("ReceivedAt")),
                    ReceivedByResourceName = reader.IsDBNull(reader.GetOrdinal("ReceivedByResourceName")) ? null : reader.GetString(reader.GetOrdinal("ReceivedByResourceName")),
                    ReceivedRemark = reader.IsDBNull(reader.GetOrdinal("ReceivedRemark")) ? null : reader.GetString(reader.GetOrdinal("ReceivedRemark")),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    CreatedBy = reader.GetInt32(reader.GetOrdinal("CreatedBy")),
                    CreatedByName = reader.IsDBNull(reader.GetOrdinal("CreatedByName")) ? null : reader.GetString(reader.GetOrdinal("CreatedByName")),
                    UpdatedAt = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                    UpdatedByName = reader.IsDBNull(reader.GetOrdinal("UpdatedByName")) ? null : reader.GetString(reader.GetOrdinal("UpdatedByName")),
                    UpdatedByResourceName = reader.IsDBNull(reader.GetOrdinal("UpdatedByResourceName")) ? null : reader.GetString(reader.GetOrdinal("UpdatedByResourceName")),
                });
            }

            return new SuperAdminBundleDetailDto { Bundle = bundle, SizeOptions = sizeOptions, Logs = logs };
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<(bool Success, string Error)> UpdateBundleAsync(int bundleId, SuperAdminBundleUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "BUNDLE_UPDATE");
        var bundleIdParam = new SqlParameter("@BundleId", bundleId);
        var articleSizeIdParam = new SqlParameter("@ArticleSizeId", request.ArticleSizeId);
        var qtyParam = new SqlParameter("@Qty", request.Qty);
        var bundleNoParam = new SqlParameter("@BundleNo", request.BundleNo);
        var serialParam = new SqlParameter("@Serial", request.Serial);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_SuperAdmin_Manage @Action = @Action, @BundleId = @BundleId, @ArticleSizeId = @ArticleSizeId, @Qty = @Qty, @BundleNo = @BundleNo, @Serial = @Serial, @UserId = @UserId",
                actionParam, bundleIdParam, articleSizeIdParam, qtyParam, bundleNoParam, serialParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteBundleAsync(int bundleId, string reason, int userId)
    {
        var actionParam = new SqlParameter("@Action", "BUNDLE_DELETE");
        var bundleIdParam = new SqlParameter("@BundleId", bundleId);
        var reasonParam = new SqlParameter("@DeleteReason", reason);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_SuperAdmin_Manage @Action = @Action, @BundleId = @BundleId, @DeleteReason = @DeleteReason, @UserId = @UserId",
                actionParam, bundleIdParam, reasonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateLogAsync(int workflowLogId, SuperAdminLogUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "LOG_UPDATE");
        var workflowLogIdParam = new SqlParameter("@WorkflowLogId", workflowLogId);
        var qtyOkParam = new SqlParameter("@QtyOk", request.QtyOk);
        var qtyRejectPrintParam = new SqlParameter("@QtyRejectPrint", request.QtyRejectPrint);
        var qtyRejectFabricParam = new SqlParameter("@QtyRejectFabric", request.QtyRejectFabric);
        var qtyRejectSewingParam = new SqlParameter("@QtyRejectSewing", request.QtyRejectSewing);
        var qtyRejectReworkParam = new SqlParameter("@QtyRejectRework", request.QtyRejectRework);
        var qtyLostParam = new SqlParameter("@QtyLost", request.QtyLost);
        var remarkParam = new SqlParameter("@Remark", (object?)request.Remark ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_SuperAdmin_Manage @Action = @Action, @WorkflowLogId = @WorkflowLogId, @QtyOk = @QtyOk, @QtyRejectPrint = @QtyRejectPrint, @QtyRejectFabric = @QtyRejectFabric, @QtyRejectSewing = @QtyRejectSewing, @QtyRejectRework = @QtyRejectRework, @QtyLost = @QtyLost, @Remark = @Remark, @UserId = @UserId",
                actionParam, workflowLogIdParam, qtyOkParam, qtyRejectPrintParam, qtyRejectFabricParam,
                qtyRejectSewingParam, qtyRejectReworkParam, qtyLostParam, remarkParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteLogAsync(int workflowLogId, string reason, int userId)
    {
        var actionParam = new SqlParameter("@Action", "LOG_DELETE");
        var workflowLogIdParam = new SqlParameter("@WorkflowLogId", workflowLogId);
        var reasonParam = new SqlParameter("@DeleteReason", reason);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_SuperAdmin_Manage @Action = @Action, @WorkflowLogId = @WorkflowLogId, @DeleteReason = @DeleteReason, @UserId = @UserId",
                actionParam, workflowLogIdParam, reasonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}

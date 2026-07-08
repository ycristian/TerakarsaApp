using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.API.Services;

// UserId dari sql/seed_station_system_user.sql, dipakai sebagai created_by untuk
// log yang dibuat dari endpoint stasiun (tidak ada JWT di sana).
public class StationOptions
{
    public int SystemUserId { get; set; }
}

public class WorkflowLogCreateInput
{
    public int ArticleWorkflowId { get; set; }
    public int? BundleId { get; set; }
    public int ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRework { get; set; }
    public string? Remark { get; set; }
    public int? TargetDivisionId { get; set; }
    public string Status { get; set; } = string.Empty;
}

public class WorkflowLogService
{
    private readonly AppDbContext _db;

    public WorkflowLogService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<WorkflowLogDto>> ListByArticleAsync(int articleId)
    {
        var articleIdParam = new SqlParameter("@ArticleId", articleId);

        return await _db.Database
            .SqlQueryRaw<WorkflowLogDto>("EXEC SIS_WorkflowLog_ListByArticle @ArticleId = @ArticleId", articleIdParam)
            .ToListAsync();
    }

    public async Task<List<StationPendingReceiveDto>> GetPendingReceivesAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        return await _db.Database
            .SqlQueryRaw<StationPendingReceiveDto>("EXEC SIS_Station_PendingReceives @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();
    }

    public async Task<List<StationActiveWorkDto>> GetActiveWorkAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        return await _db.Database
            .SqlQueryRaw<StationActiveWorkDto>("EXEC SIS_Station_ActiveWork @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();
    }

    public async Task<(bool Success, string Error)> CreateAsync(WorkflowLogCreateInput input, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var articleWorkflowIdParam = new SqlParameter("@ArticleWorkflowId", input.ArticleWorkflowId);
        var bundleIdParam = new SqlParameter("@BundleId", (object?)input.BundleId ?? DBNull.Value);
        var resourceIdParam = new SqlParameter("@ResourceId", input.ResourceId);
        var qtyOkParam = new SqlParameter("@QtyOk", input.QtyOk);
        var qtyRejectPrintParam = new SqlParameter("@QtyRejectPrint", input.QtyRejectPrint);
        var qtyRejectFabricParam = new SqlParameter("@QtyRejectFabric", input.QtyRejectFabric);
        var qtyRejectSewingParam = new SqlParameter("@QtyRejectSewing", input.QtyRejectSewing);
        var qtyReworkParam = new SqlParameter("@QtyRework", input.QtyRework);
        var remarkParam = new SqlParameter("@Remark", (object?)input.Remark ?? DBNull.Value);
        var targetDivisionIdParam = new SqlParameter("@TargetDivisionId", (object?)input.TargetDivisionId ?? DBNull.Value);
        var statusParam = new SqlParameter("@Status", input.Status);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @ArticleWorkflowId = @ArticleWorkflowId, @BundleId = @BundleId, @ResourceId = @ResourceId, @QtyOk = @QtyOk, @QtyRejectPrint = @QtyRejectPrint, @QtyRejectFabric = @QtyRejectFabric, @QtyRejectSewing = @QtyRejectSewing, @QtyRework = @QtyRework, @Remark = @Remark, @TargetDivisionId = @TargetDivisionId, @Status = @Status, @UserId = @UserId",
                actionParam, articleWorkflowIdParam, bundleIdParam, resourceIdParam, qtyOkParam, qtyRejectPrintParam,
                qtyRejectFabricParam, qtyRejectSewingParam, qtyReworkParam, remarkParam, targetDivisionIdParam, statusParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int id, string reason, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var reasonParam = new SqlParameter("@DeleteReason", reason);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @Id = @Id, @DeleteReason = @DeleteReason, @UserId = @UserId",
                actionParam, idParam, reasonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}

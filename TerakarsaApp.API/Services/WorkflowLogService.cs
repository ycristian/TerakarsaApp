using System.Text.Json;
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
    public int? ArticleSizeId { get; set; }
    // Nullable sejak Prompt 12c: input dari /workflow-input membuat resource pencatat opsional
    // (stasiun tetap mewajibkan operator dipilih, divalidasi di StationDeviceController).
    public int? ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    public int? ActingDivisionId { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini (hanya berarti utk step ber-bundle).
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini (baris susulan
    // menyusul kemudian) -- juga hanya berarti utk step ber-bundle.
    public bool ConfirmShort { get; set; }
}

public class WorkflowLogReceiveInput
{
    public int WorkflowLogId { get; set; }
    public int ReceivedByResourceId { get; set; }
    public string? ReceivedRemark { get; set; }
    public int? ActingDivisionId { get; set; }
}

// Prompt 15: pembatalan penerimaan -- hanya divisi penerima, jendela sempit (belum ada
// hasil tercatat di step berikutnya). Lihat sp_WorkflowLog_Manage.sql action UNRECEIVE.
public class WorkflowLogUnreceiveInput
{
    public int Id { get; set; }
    public int? ActingDivisionId { get; set; }
    public int UpdatedByResourceId { get; set; }
}

// Revisi data SEBELUM diterima (received_at masih NULL) -- dipakai divisi PEMBUAT baris,
// bukan divisi tujuan. Lihat sp_WorkflowLog_Manage.sql action UPDATE.
public class WorkflowLogUpdateInput
{
    public int Id { get; set; }
    public int? ArticleSizeId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    public int? ActingDivisionId { get; set; }
    // Pelaksana (operator sesi aktif) saat revisi dari stasiun -- Prompt 12d.
    public int? UpdatedByResourceId { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini (hanya berarti utk step ber-bundle).
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini.
    public bool ConfirmShort { get; set; }
}

public class WorkflowLogService
{
    private readonly AppDbContext _db;

    public WorkflowLogService(AppDbContext db)
    {
        _db = db;
    }

    private class StationPendingHandoverRow
    {
        public int WorkflowLogId { get; set; }
        public int ArticleWorkflowId { get; set; }
        public string ProjectName { get; set; } = string.Empty;
        public string ArticleName { get; set; } = string.Empty;
        public string? Style { get; set; }
        public string? Color { get; set; }
        public string StepName { get; set; } = string.Empty;
        public int? BundleId { get; set; }
        public int? BundleNo { get; set; }
        public string? Serial { get; set; }
        public int? ArticleSizeId { get; set; }
        public string? SizeName { get; set; }
        public int QtyOk { get; set; }
        public int QtyRejectPrint { get; set; }
        public int QtyRejectFabric { get; set; }
        public int QtyRejectSewing { get; set; }
        public string? Remark { get; set; }
        public string TargetDivisionName { get; set; } = string.Empty;
        public string? ResourceName { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? SizesJson { get; set; }
    }

    public async Task<List<WorkflowLogDto>> ListByArticleAsync(int articleId)
    {
        var articleIdParam = new SqlParameter("@ArticleId", articleId);

        return await _db.Database
            .SqlQueryRaw<WorkflowLogDto>("EXEC SIS_WorkflowLog_ListByArticle @ArticleId = @ArticleId", articleIdParam)
            .ToListAsync();
    }

    // Prompt 14: info kuota qty step ber-bundle utk UI ("Masuk / Tercatat / Sisa") sebelum submit.
    public async Task<WorkflowQuotaInfoDto?> GetQuotaInfoAsync(int articleWorkflowId, int bundleId)
    {
        var articleWorkflowIdParam = new SqlParameter("@ArticleWorkflowId", articleWorkflowId);
        var bundleIdParam = new SqlParameter("@BundleId", bundleId);

        var rows = await _db.Database
            .SqlQueryRaw<WorkflowQuotaInfoDto>(
                "EXEC SIS_WorkflowLog_QuotaInfo @ArticleWorkflowId = @ArticleWorkflowId, @BundleId = @BundleId",
                articleWorkflowIdParam, bundleIdParam)
            .ToListAsync();

        return rows.FirstOrDefault();
    }

    public async Task<List<StationPendingReceiveDto>> GetPendingReceivesAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        return await _db.Database
            .SqlQueryRaw<StationPendingReceiveDto>("EXEC SIS_Station_PendingReceives @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();
    }

    public async Task<List<StationPendingHandoverDto>> GetPendingHandoverAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        var rows = await _db.Database
            .SqlQueryRaw<StationPendingHandoverRow>("EXEC SIS_Station_PendingHandover @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();

        return rows.Select(row => new StationPendingHandoverDto
        {
            WorkflowLogId = row.WorkflowLogId,
            ArticleWorkflowId = row.ArticleWorkflowId,
            ProjectName = row.ProjectName,
            ArticleName = row.ArticleName,
            Style = row.Style,
            Color = row.Color,
            StepName = row.StepName,
            BundleId = row.BundleId,
            BundleNo = row.BundleNo,
            Serial = row.Serial,
            ArticleSizeId = row.ArticleSizeId,
            SizeName = row.SizeName,
            QtyOk = row.QtyOk,
            QtyRejectPrint = row.QtyRejectPrint,
            QtyRejectFabric = row.QtyRejectFabric,
            QtyRejectSewing = row.QtyRejectSewing,
            Remark = row.Remark,
            TargetDivisionName = row.TargetDivisionName,
            ResourceName = row.ResourceName,
            CreatedAt = row.CreatedAt,
            UpdatedAt = row.UpdatedAt,
            Sizes = string.IsNullOrEmpty(row.SizesJson)
                ? new()
                : JsonSerializer.Deserialize<List<ArticleSizeOptionDto>>(row.SizesJson) ?? new()
        }).ToList();
    }

    public async Task<(bool Success, string Error)> CreateAsync(WorkflowLogCreateInput input, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var articleWorkflowIdParam = new SqlParameter("@ArticleWorkflowId", input.ArticleWorkflowId);
        var bundleIdParam = new SqlParameter("@BundleId", (object?)input.BundleId ?? DBNull.Value);
        var articleSizeIdParam = new SqlParameter("@ArticleSizeId", (object?)input.ArticleSizeId ?? DBNull.Value);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)input.ResourceId ?? DBNull.Value);
        var qtyOkParam = new SqlParameter("@QtyOk", input.QtyOk);
        var qtyRejectPrintParam = new SqlParameter("@QtyRejectPrint", input.QtyRejectPrint);
        var qtyRejectFabricParam = new SqlParameter("@QtyRejectFabric", input.QtyRejectFabric);
        var qtyRejectSewingParam = new SqlParameter("@QtyRejectSewing", input.QtyRejectSewing);
        var remarkParam = new SqlParameter("@Remark", (object?)input.Remark ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);
        var actingDivisionIdParam = new SqlParameter("@ActingDivisionId", (object?)input.ActingDivisionId ?? DBNull.Value);
        var confirmExceedParam = new SqlParameter("@ConfirmExceed", input.ConfirmExceed);
        var confirmShortParam = new SqlParameter("@ConfirmShort", input.ConfirmShort);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @ArticleWorkflowId = @ArticleWorkflowId, @BundleId = @BundleId, @ArticleSizeId = @ArticleSizeId, @ResourceId = @ResourceId, @QtyOk = @QtyOk, @QtyRejectPrint = @QtyRejectPrint, @QtyRejectFabric = @QtyRejectFabric, @QtyRejectSewing = @QtyRejectSewing, @Remark = @Remark, @UserId = @UserId, @ActingDivisionId = @ActingDivisionId, @ConfirmExceed = @ConfirmExceed, @ConfirmShort = @ConfirmShort",
                actionParam, articleWorkflowIdParam, bundleIdParam, articleSizeIdParam, resourceIdParam, qtyOkParam,
                qtyRejectPrintParam, qtyRejectFabricParam, qtyRejectSewingParam, remarkParam,
                userIdParam, actingDivisionIdParam, confirmExceedParam, confirmShortParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(WorkflowLogUpdateInput input, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", input.Id);
        var articleSizeIdParam = new SqlParameter("@ArticleSizeId", (object?)input.ArticleSizeId ?? DBNull.Value);
        var qtyOkParam = new SqlParameter("@QtyOk", input.QtyOk);
        var qtyRejectPrintParam = new SqlParameter("@QtyRejectPrint", input.QtyRejectPrint);
        var qtyRejectFabricParam = new SqlParameter("@QtyRejectFabric", input.QtyRejectFabric);
        var qtyRejectSewingParam = new SqlParameter("@QtyRejectSewing", input.QtyRejectSewing);
        var remarkParam = new SqlParameter("@Remark", (object?)input.Remark ?? DBNull.Value);
        var actingDivisionIdParam = new SqlParameter("@ActingDivisionId", (object?)input.ActingDivisionId ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);
        var updatedByResourceIdParam = new SqlParameter("@UpdatedByResourceId", (object?)input.UpdatedByResourceId ?? DBNull.Value);
        var confirmExceedParam = new SqlParameter("@ConfirmExceed", input.ConfirmExceed);
        var confirmShortParam = new SqlParameter("@ConfirmShort", input.ConfirmShort);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @Id = @Id, @ArticleSizeId = @ArticleSizeId, @QtyOk = @QtyOk, @QtyRejectPrint = @QtyRejectPrint, @QtyRejectFabric = @QtyRejectFabric, @QtyRejectSewing = @QtyRejectSewing, @Remark = @Remark, @ActingDivisionId = @ActingDivisionId, @UserId = @UserId, @UpdatedByResourceId = @UpdatedByResourceId, @ConfirmExceed = @ConfirmExceed, @ConfirmShort = @ConfirmShort",
                actionParam, idParam, articleSizeIdParam, qtyOkParam, qtyRejectPrintParam,
                qtyRejectFabricParam, qtyRejectSewingParam, remarkParam, actingDivisionIdParam,
                userIdParam, updatedByResourceIdParam, confirmExceedParam, confirmShortParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> ReceiveAsync(WorkflowLogReceiveInput input)
    {
        var actionParam = new SqlParameter("@Action", "RECEIVE");
        var idParam = new SqlParameter("@Id", input.WorkflowLogId);
        var receivedByParam = new SqlParameter("@ReceivedByResourceId", input.ReceivedByResourceId);
        var receivedRemarkParam = new SqlParameter("@ReceivedRemark", (object?)input.ReceivedRemark ?? DBNull.Value);
        var actingDivisionIdParam = new SqlParameter("@ActingDivisionId", (object?)input.ActingDivisionId ?? DBNull.Value);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @Id = @Id, @ReceivedByResourceId = @ReceivedByResourceId, @ReceivedRemark = @ReceivedRemark, @ActingDivisionId = @ActingDivisionId",
                actionParam, idParam, receivedByParam, receivedRemarkParam, actingDivisionIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<List<StationRecentReceivedDto>> GetRecentReceivedAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        return await _db.Database
            .SqlQueryRaw<StationRecentReceivedDto>("EXEC SIS_Station_RecentReceived @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();
    }

    public async Task<(bool Success, string Error)> UnreceiveAsync(WorkflowLogUnreceiveInput input, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UNRECEIVE");
        var idParam = new SqlParameter("@Id", input.Id);
        var userIdParam = new SqlParameter("@UserId", userId);
        var actingDivisionIdParam = new SqlParameter("@ActingDivisionId", (object?)input.ActingDivisionId ?? DBNull.Value);
        var updatedByResourceIdParam = new SqlParameter("@UpdatedByResourceId", input.UpdatedByResourceId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @Id = @Id, @UserId = @UserId, @ActingDivisionId = @ActingDivisionId, @UpdatedByResourceId = @UpdatedByResourceId",
                actionParam, idParam, userIdParam, actingDivisionIdParam, updatedByResourceIdParam);
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

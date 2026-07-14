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

    private class StationActiveWorkRow
    {
        public int ArticleWorkflowId { get; set; }
        public int ArticleId { get; set; }
        public string ProjectName { get; set; } = string.Empty;
        public string ArticleName { get; set; } = string.Empty;
        public string? Style { get; set; }
        public string? Color { get; set; }
        public string StepName { get; set; } = string.Empty;
        public bool IsBundling { get; set; }
        public bool IsLastStep { get; set; }
        public int? NextDivisionId { get; set; }
        public string? NextDivisionName { get; set; }
        public string? SizesJson { get; set; }
        public int? BundleCount { get; set; }
        public int? TotalBundleQty { get; set; }
        public int? TotalOrderQty { get; set; }
        // Dipakai hanya utk ORDER BY di SQL (UNION ActiveWork + kartu Buat Bundle) -- tidak
        // diteruskan ke StationActiveWorkDto.
        public int SortOrder { get; set; }
    }

    private class StationPendingHandoverRow
    {
        public int WorkflowLogId { get; set; }
        public int ArticleWorkflowId { get; set; }
        public int ArticleId { get; set; }
        public string ProjectName { get; set; } = string.Empty;
        public string ArticleName { get; set; } = string.Empty;
        public string? Style { get; set; }
        public string? Color { get; set; }
        public string StepName { get; set; } = string.Empty;
        public bool IsBundling { get; set; }
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
        public string? TargetDivisionName { get; set; }
        public bool IsLastStep { get; set; }
        public string? ResourceName { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? SizesJson { get; set; }
        public string? TargetDivisionOptionsJson { get; set; }
        public int? BundleResourceId { get; set; }
        public string? BundleResourceName { get; set; }
        public string? BundleResourcePersonName { get; set; }
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

    // Prompt 22b: lineResourceId = EffectiveResourceId(operator sesi) dari
    // StationDeviceController -- resource stasiun kalau terkunci, else operator yang
    // sedang login di perangkat (NULL kalau belum ada operator terpilih).
    public async Task<List<StationPendingReceiveDto>> GetPendingReceivesAsync(int divisionId, int? lineResourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)lineResourceId ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<StationPendingReceiveDto>(
                "EXEC SIS_Station_PendingReceives @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
            .ToListAsync();
    }

    // Prompt 22b: lineResourceId, lihat komentar GetPendingReceivesAsync (di sini dicocokkan
    // ke awl.resource_id -- Line PENGIRIM, bukan bundles.resource_id).
    public async Task<List<StationPendingHandoverDto>> GetPendingHandoverAsync(int divisionId, int? lineResourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)lineResourceId ?? DBNull.Value);

        var rows = await _db.Database
            .SqlQueryRaw<StationPendingHandoverRow>(
                "EXEC SIS_Station_PendingHandover @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
            .ToListAsync();

        return rows.Select(row => new StationPendingHandoverDto
        {
            WorkflowLogId = row.WorkflowLogId,
            ArticleWorkflowId = row.ArticleWorkflowId,
            ArticleId = row.ArticleId,
            ProjectName = row.ProjectName,
            ArticleName = row.ArticleName,
            Style = row.Style,
            Color = row.Color,
            StepName = row.StepName,
            IsBundling = row.IsBundling,
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
            IsLastStep = row.IsLastStep,
            ResourceName = row.ResourceName,
            CreatedAt = row.CreatedAt,
            UpdatedAt = row.UpdatedAt,
            Sizes = string.IsNullOrEmpty(row.SizesJson)
                ? new()
                : JsonSerializer.Deserialize<List<ArticleSizeOptionDto>>(row.SizesJson) ?? new(),
            TargetDivisionOptions = string.IsNullOrEmpty(row.TargetDivisionOptionsJson)
                ? new()
                : JsonSerializer.Deserialize<List<DivisionOptionDto>>(row.TargetDivisionOptionsJson) ?? new(),
            BundleResourceId = row.BundleResourceId,
            BundleResourceName = row.BundleResourceName,
            BundleResourcePersonName = row.BundleResourcePersonName
        }).ToList();
    }

    // Prompt 23: kartu permanen (artikel x step non-bundle) di tab WIP -- lihat
    // SIS_Station_ActiveWork. Tanpa filter Line (kartu ini tidak terikat bundle/Line).
    public async Task<List<StationActiveWorkDto>> GetActiveWorkAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        var rows = await _db.Database
            .SqlQueryRaw<StationActiveWorkRow>("EXEC SIS_Station_ActiveWork @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();

        return rows.Select(row => new StationActiveWorkDto
        {
            ArticleWorkflowId = row.ArticleWorkflowId,
            ArticleId = row.ArticleId,
            ProjectName = row.ProjectName,
            ArticleName = row.ArticleName,
            Style = row.Style,
            Color = row.Color,
            StepName = row.StepName,
            IsBundling = row.IsBundling,
            IsLastStep = row.IsLastStep,
            NextDivisionId = row.NextDivisionId,
            NextDivisionName = row.NextDivisionName,
            Sizes = string.IsNullOrEmpty(row.SizesJson)
                ? new()
                : JsonSerializer.Deserialize<List<StationActiveWorkSizeDto>>(row.SizesJson) ?? new(),
            BundleCount = row.BundleCount,
            TotalBundleQty = row.TotalBundleQty,
            TotalOrderQty = row.TotalOrderQty
        }).ToList();
    }

    // Prompt 12e: tab "Dikerjakan" -- lihat SIS_Station_InProgress. Prompt 22b: lineResourceId,
    // lihat komentar GetPendingReceivesAsync.
    public async Task<List<StationInProgressDto>> GetInProgressAsync(int divisionId, int? lineResourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)lineResourceId ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<StationInProgressDto>(
                "EXEC SIS_Station_InProgress @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
            .ToListAsync();
    }

    // Prompt 12e: strip 3 angka besar (Masuk/Dikerjakan/Dikirim) -- lihat SIS_Station_Counts.
    // Prompt 22b: lineResourceId, lihat komentar GetPendingReceivesAsync.
    public async Task<StationCountsDto> GetCountsAsync(int divisionId, int? lineResourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)lineResourceId ?? DBNull.Value);

        var rows = await _db.Database
            .SqlQueryRaw<StationCountsDto>(
                "EXEC SIS_Station_Counts @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
            .ToListAsync();

        return rows.FirstOrDefault() ?? new StationCountsDto();
    }

    // Prompt 12e: "Batal Serah" -- lihat SIS_WorkflowLog_Manage action CANCEL_HANDOVER.
    public async Task<(bool Success, string Error)> CancelHandoverAsync(int id, int? actingDivisionId, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CANCEL_HANDOVER");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);
        var actingDivisionIdParam = new SqlParameter("@ActingDivisionId", (object?)actingDivisionId ?? DBNull.Value);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @Id = @Id, @UserId = @UserId, @ActingDivisionId = @ActingDivisionId",
                actionParam, idParam, userIdParam, actingDivisionIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Prompt 12e: "Revisi" di tab Dikirim -- lihat SIS_WorkflowLog_Manage action REVISE_HANDOVER.
    public async Task<(bool Success, string Error)> ReviseHandoverAsync(int id, StationReviseHandoverRequest request, int? actingDivisionId, int userId)
    {
        var actionParam = new SqlParameter("@Action", "REVISE_HANDOVER");
        var idParam = new SqlParameter("@Id", id);
        var qtyOkParam = new SqlParameter("@QtyOk", request.QtyOk);
        var qtyRejectPrintParam = new SqlParameter("@QtyRejectPrint", request.QtyRejectPrint);
        var qtyRejectFabricParam = new SqlParameter("@QtyRejectFabric", request.QtyRejectFabric);
        var qtyRejectSewingParam = new SqlParameter("@QtyRejectSewing", request.QtyRejectSewing);
        var remarkParam = new SqlParameter("@Remark", (object?)request.Remark ?? DBNull.Value);
        var newTargetDivisionIdParam = new SqlParameter("@NewTargetDivisionId", request.NewTargetDivisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)request.NewResourceId ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);
        var actingDivisionIdParam = new SqlParameter("@ActingDivisionId", (object?)actingDivisionId ?? DBNull.Value);
        var updatedByResourceIdParam = new SqlParameter("@UpdatedByResourceId", request.ResourceId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLog_Manage @Action = @Action, @Id = @Id, @QtyOk = @QtyOk, @QtyRejectPrint = @QtyRejectPrint, @QtyRejectFabric = @QtyRejectFabric, @QtyRejectSewing = @QtyRejectSewing, @Remark = @Remark, @NewTargetDivisionId = @NewTargetDivisionId, @ResourceId = @ResourceId, @UserId = @UserId, @ActingDivisionId = @ActingDivisionId, @UpdatedByResourceId = @UpdatedByResourceId",
                actionParam, idParam, qtyOkParam, qtyRejectPrintParam, qtyRejectFabricParam, qtyRejectSewingParam,
                remarkParam, newTargetDivisionIdParam, resourceIdParam, userIdParam, actingDivisionIdParam, updatedByResourceIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    private const string CreateLogSql =
        "EXEC SIS_WorkflowLog_Manage @Action = @Action, @ArticleWorkflowId = @ArticleWorkflowId, @BundleId = @BundleId, @ArticleSizeId = @ArticleSizeId, @ResourceId = @ResourceId, @QtyOk = @QtyOk, @QtyRejectPrint = @QtyRejectPrint, @QtyRejectFabric = @QtyRejectFabric, @QtyRejectSewing = @QtyRejectSewing, @Remark = @Remark, @UserId = @UserId, @ActingDivisionId = @ActingDivisionId, @ConfirmExceed = @ConfirmExceed, @ConfirmShort = @ConfirmShort";

    private static SqlParameter[] BuildCreateLogParams(WorkflowLogCreateInput input, int userId) => new[]
    {
        new SqlParameter("@Action", "CREATE"),
        new SqlParameter("@ArticleWorkflowId", input.ArticleWorkflowId),
        new SqlParameter("@BundleId", (object?)input.BundleId ?? DBNull.Value),
        new SqlParameter("@ArticleSizeId", (object?)input.ArticleSizeId ?? DBNull.Value),
        new SqlParameter("@ResourceId", (object?)input.ResourceId ?? DBNull.Value),
        new SqlParameter("@QtyOk", input.QtyOk),
        new SqlParameter("@QtyRejectPrint", input.QtyRejectPrint),
        new SqlParameter("@QtyRejectFabric", input.QtyRejectFabric),
        new SqlParameter("@QtyRejectSewing", input.QtyRejectSewing),
        new SqlParameter("@Remark", (object?)input.Remark ?? DBNull.Value),
        new SqlParameter("@UserId", userId),
        new SqlParameter("@ActingDivisionId", (object?)input.ActingDivisionId ?? DBNull.Value),
        new SqlParameter("@ConfirmExceed", input.ConfirmExceed),
        new SqlParameter("@ConfirmShort", input.ConfirmShort)
    };

    public async Task<(bool Success, string Error)> CreateAsync(WorkflowLogCreateInput input, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(CreateLogSql, BuildCreateLogParams(input, userId));
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Prompt 19: grid input cutting -- satu baris article_workflow_logs per ukuran, semua
    // atau tidak sama sekali (satu transaksi C#, sama seperti EXEC tunggal di CreateAsync
    // hanya diulang). SP tidak diubah -- tetap satu EXEC per baris.
    public async Task<(bool Success, string Error, int? FailedArticleSizeId)> CreateBatchAsync(List<WorkflowLogCreateInput> inputs, int userId)
    {
        await using var transaction = await _db.Database.BeginTransactionAsync();
        int? currentArticleSizeId = null;

        try
        {
            foreach (var input in inputs)
            {
                currentArticleSizeId = input.ArticleSizeId;
                await _db.Database.ExecuteSqlRawAsync(CreateLogSql, BuildCreateLogParams(input, userId));
            }

            await transaction.CommitAsync();
            return (true, string.Empty, null);
        }
        catch (SqlException ex)
        {
            await transaction.RollbackAsync();
            return (false, ex.Message, currentArticleSizeId);
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

    // Prompt 22b: lineResourceId dicocokkan ke received_by_resource_id (siapa yang menerima).
    public async Task<List<StationRecentReceivedDto>> GetRecentReceivedAsync(int divisionId, int? lineResourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)lineResourceId ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<StationRecentReceivedDto>(
                "EXEC SIS_Station_RecentReceived @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
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

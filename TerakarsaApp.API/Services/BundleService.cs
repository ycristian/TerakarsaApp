using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Bundles;

namespace TerakarsaApp.API.Services;

// PublicBaseUrl dipakai untuk merakit qr_content (link QR di label bundle), lihat
// sql/sp_Bundle_Manage.sql -- serial baru hanya diketahui di dalam SP (sp_getapplock),
// jadi base URL dikirim sebagai parameter dan qr_content lengkap dirakit di sana.
public class AppOptions
{
    public string PublicBaseUrl { get; set; } = string.Empty;
}

public class BundleService
{
    private readonly AppDbContext _db;
    private readonly string _publicBaseUrl;

    public BundleService(AppDbContext db, IOptions<AppOptions> appOptions)
    {
        _db = db;
        _publicBaseUrl = appOptions.Value.PublicBaseUrl;
    }

    private class BundleCreateResultRow
    {
        public int NewId { get; set; }
        // Fix: nullable -- NULL kalau @PrintCopies = 0.
        public int? NewPrintJobId { get; set; }
        public int NewBundleNo { get; set; }
        public string? NewBundleLetter { get; set; }
        public string NewSerial { get; set; } = string.Empty;
    }

    // Prompt 24: dipisah dari GetByArticleAsync supaya bisa dipakai sendiri oleh station
    // (ringkasan modal Buat Bundle + validasi divisi Bundling), tanpa perlu Bundles/PublicBaseUrl.
    public async Task<List<BundleSizeSummaryDto>> GetSummaryAsync(int articleId)
    {
        var articleIdParam = new SqlParameter("@ArticleId", articleId);

        return await _db.Database
            .SqlQueryRaw<BundleSizeSummaryDto>("EXEC SIS_Article_BundleSummary @ArticleId = @ArticleId", articleIdParam)
            .ToListAsync();
    }

    public async Task<ArticleBundlesDto> GetByArticleAsync(int articleId)
    {
        var articleIdParam2 = new SqlParameter("@ArticleId", articleId);

        var summary = await GetSummaryAsync(articleId);

        var bundles = await _db.Database
            .SqlQueryRaw<BundleDto>("EXEC SIS_Bundle_ListByArticle @ArticleId = @ArticleId", articleIdParam2)
            .ToListAsync();

        return new ArticleBundlesDto
        {
            ArticleId = articleId,
            Summary = summary,
            Bundles = bundles,
            PublicBaseUrl = _publicBaseUrl
        };
    }

    public async Task<(bool Success, string Error, BundleCreateResult Result)> CreateAsync(BundleCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var articleIdParam = new SqlParameter("@ArticleId", request.ArticleId);
        var articleSizeIdParam = new SqlParameter("@ArticleSizeId", request.ArticleSizeId);
        var qtyParam = new SqlParameter("@Qty", request.Qty);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)request.ResourceId ?? DBNull.Value);
        var employeeIdParam = new SqlParameter("@EmployeeId", (object?)request.EmployeeId ?? DBNull.Value);
        var remarksParam = new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value);
        var publicBaseUrlParam = new SqlParameter("@PublicBaseUrl", (object?)_publicBaseUrl ?? DBNull.Value);
        var bundlingResourceIdParam = new SqlParameter("@BundlingResourceId", (object?)request.BundlingResourceId ?? DBNull.Value);
        var printCopiesParam = new SqlParameter("@PrintCopies", request.PrintCopies);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<BundleCreateResultRow>(
                    "EXEC SIS_Bundle_Manage @Action = @Action, @ArticleId = @ArticleId, @ArticleSizeId = @ArticleSizeId, @Qty = @Qty, @ResourceId = @ResourceId, @EmployeeId = @EmployeeId, @Remarks = @Remarks, @PublicBaseUrl = @PublicBaseUrl, @BundlingResourceId = @BundlingResourceId, @PrintCopies = @PrintCopies, @UserId = @UserId",
                    actionParam, articleIdParam, articleSizeIdParam, qtyParam, resourceIdParam, employeeIdParam, remarksParam, publicBaseUrlParam, bundlingResourceIdParam, printCopiesParam, userIdParam)
                .ToListAsync();

            var row = result.First();
            return (true, string.Empty, new BundleCreateResult { Id = row.NewId, PrintJobId = row.NewPrintJobId, BundleNo = row.NewBundleNo, BundleLetter = row.NewBundleLetter, Serial = row.NewSerial });
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, new BundleCreateResult());
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(BundleUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var qtyParam = new SqlParameter("@Qty", request.Qty);
        var articleSizeIdParam = new SqlParameter("@ArticleSizeId", (object?)request.ArticleSizeId ?? DBNull.Value);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)request.ResourceId ?? DBNull.Value);
        var employeeIdParam = new SqlParameter("@EmployeeId", (object?)request.EmployeeId ?? DBNull.Value);
        var remarksParam = new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value);
        var bundlingResourceIdParam = new SqlParameter("@BundlingResourceId", (object?)request.BundlingResourceId ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Bundle_Manage @Action = @Action, @Id = @Id, @Qty = @Qty, @ArticleSizeId = @ArticleSizeId, @ResourceId = @ResourceId, @EmployeeId = @EmployeeId, @Remarks = @Remarks, @BundlingResourceId = @BundlingResourceId, @UserId = @UserId",
                actionParam, idParam, qtyParam, articleSizeIdParam, resourceIdParam, employeeIdParam, remarksParam, bundlingResourceIdParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Bundle_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
                actionParam, idParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // SIS_Bundle_ScanInfo mengembalikan 3 result set sekaligus (info, timeline, aksi) —
    // EF Core SqlQueryRaw hanya mendukung satu result set, jadi di sini pakai SqlCommand
    // mentah + reader.NextResultAsync() langsung di atas koneksi yang sama dengan AppDbContext.
    public async Task<BundleScanInfoDto?> GetScanInfoAsync(string serial, int? divisionId, int? resourceId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Bundle_ScanInfo";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@Serial", serial));
            cmd.Parameters.Add(new SqlParameter("@DivisionId", (object?)divisionId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value));

            using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return null;

            var bundle = new BundleScanBundleDto
            {
                BundleId = reader.GetInt32(reader.GetOrdinal("BundleId")),
                BundleNo = reader.GetInt32(reader.GetOrdinal("BundleNo")),
                BundleLetter = reader.IsDBNull(reader.GetOrdinal("BundleLetter")) ? null : reader.GetString(reader.GetOrdinal("BundleLetter")),
                Serial = reader.GetString(reader.GetOrdinal("Serial")),
                Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                Style = reader.IsDBNull(reader.GetOrdinal("Style")) ? null : reader.GetString(reader.GetOrdinal("Style")),
                Color = reader.IsDBNull(reader.GetOrdinal("Color")) ? null : reader.GetString(reader.GetOrdinal("Color")),
                ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                Line = reader.IsDBNull(reader.GetOrdinal("Line")) ? null : reader.GetString(reader.GetOrdinal("Line")),
                LastStepName = reader.IsDBNull(reader.GetOrdinal("LastStepName")) ? null : reader.GetString(reader.GetOrdinal("LastStepName")),
                LastStatus = reader.IsDBNull(reader.GetOrdinal("LastStatus")) ? null : reader.GetString(reader.GetOrdinal("LastStatus")),
                LastDivisionName = reader.IsDBNull(reader.GetOrdinal("LastDivisionName")) ? null : reader.GetString(reader.GetOrdinal("LastDivisionName")),
                EmployeeName = reader.IsDBNull(reader.GetOrdinal("EmployeeName")) ? null : reader.GetString(reader.GetOrdinal("EmployeeName")),
            };

            await reader.NextResultAsync();
            var timeline = new List<BundleScanTimelineDto>();
            while (await reader.ReadAsync())
            {
                timeline.Add(new BundleScanTimelineDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    SizeName = reader.IsDBNull(reader.GetOrdinal("SizeName")) ? null : reader.GetString(reader.GetOrdinal("SizeName")),
                    DivisionName = reader.IsDBNull(reader.GetOrdinal("DivisionName")) ? null : reader.GetString(reader.GetOrdinal("DivisionName")),
                    ResourceName = reader.IsDBNull(reader.GetOrdinal("ResourceName")) ? null : reader.GetString(reader.GetOrdinal("ResourceName")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyRejectPrint = reader.GetInt32(reader.GetOrdinal("QtyRejectPrint")),
                    QtyRejectFabric = reader.GetInt32(reader.GetOrdinal("QtyRejectFabric")),
                    QtyRejectSewing = reader.GetInt32(reader.GetOrdinal("QtyRejectSewing")),
                    QtyRejectRework = reader.GetInt32(reader.GetOrdinal("QtyRejectRework")),
                    QtyLost = reader.GetInt32(reader.GetOrdinal("QtyLost")),
                    LogType = reader.GetString(reader.GetOrdinal("LogType")),
                    TargetDivisionName = reader.IsDBNull(reader.GetOrdinal("TargetDivisionName")) ? null : reader.GetString(reader.GetOrdinal("TargetDivisionName")),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    ReceivedAt = reader.IsDBNull(reader.GetOrdinal("ReceivedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("ReceivedAt")),
                    ReceivedByResourceName = reader.IsDBNull(reader.GetOrdinal("ReceivedByResourceName")) ? null : reader.GetString(reader.GetOrdinal("ReceivedByResourceName")),
                    ReceivedRemark = reader.IsDBNull(reader.GetOrdinal("ReceivedRemark")) ? null : reader.GetString(reader.GetOrdinal("ReceivedRemark")),
                });
            }

            await reader.NextResultAsync();
            var action = new BundleScanActionDto();
            if (await reader.ReadAsync())
            {
                action.AllowedAction = reader.GetString(reader.GetOrdinal("AllowedAction"));
                var actionStepOrdinal = reader.GetOrdinal("ActionArticleWorkflowId");
                action.ActionArticleWorkflowId = reader.IsDBNull(actionStepOrdinal) ? null : reader.GetInt32(actionStepOrdinal);
                var actionLogOrdinal = reader.GetOrdinal("ActionWorkflowLogId");
                action.ActionWorkflowLogId = reader.IsDBNull(actionLogOrdinal) ? null : reader.GetInt32(actionLogOrdinal);
                var messageOrdinal = reader.GetOrdinal("Message");
                action.Message = reader.IsDBNull(messageOrdinal) ? null : reader.GetString(messageOrdinal);
                action.IsLastStep = reader.GetBoolean(reader.GetOrdinal("IsLastStep"));
                var nextDivisionIdOrdinal = reader.GetOrdinal("NextDivisionId");
                action.NextDivisionId = reader.IsDBNull(nextDivisionIdOrdinal) ? null : reader.GetInt32(nextDivisionIdOrdinal);
                var nextDivisionNameOrdinal = reader.GetOrdinal("NextDivisionName");
                action.NextDivisionName = reader.IsDBNull(nextDivisionNameOrdinal) ? null : reader.GetString(nextDivisionNameOrdinal);

                var actionQtyOkOrdinal = reader.GetOrdinal("ActionQtyOk");
                action.ActionQtyOk = reader.IsDBNull(actionQtyOkOrdinal) ? null : reader.GetInt32(actionQtyOkOrdinal);
                var actionQtyRejectPrintOrdinal = reader.GetOrdinal("ActionQtyRejectPrint");
                action.ActionQtyRejectPrint = reader.IsDBNull(actionQtyRejectPrintOrdinal) ? null : reader.GetInt32(actionQtyRejectPrintOrdinal);
                var actionQtyRejectFabricOrdinal = reader.GetOrdinal("ActionQtyRejectFabric");
                action.ActionQtyRejectFabric = reader.IsDBNull(actionQtyRejectFabricOrdinal) ? null : reader.GetInt32(actionQtyRejectFabricOrdinal);
                var actionQtyRejectSewingOrdinal = reader.GetOrdinal("ActionQtyRejectSewing");
                action.ActionQtyRejectSewing = reader.IsDBNull(actionQtyRejectSewingOrdinal) ? null : reader.GetInt32(actionQtyRejectSewingOrdinal);
                var actionQtyRejectReworkOrdinal = reader.GetOrdinal("ActionQtyRejectRework");
                action.ActionQtyRejectRework = reader.IsDBNull(actionQtyRejectReworkOrdinal) ? null : reader.GetInt32(actionQtyRejectReworkOrdinal);
                var actionQtyLostOrdinal = reader.GetOrdinal("ActionQtyLost");
                action.ActionQtyLost = reader.IsDBNull(actionQtyLostOrdinal) ? null : reader.GetInt32(actionQtyLostOrdinal);
                var actionRemarkOrdinal = reader.GetOrdinal("ActionRemark");
                action.ActionRemark = reader.IsDBNull(actionRemarkOrdinal) ? null : reader.GetString(actionRemarkOrdinal);
                action.AllowedAdjust = reader.GetBoolean(reader.GetOrdinal("AllowedAdjust"));
            }

            await reader.NextResultAsync();
            var adjustSteps = new List<BundleAdjustStepSaldoDto>();
            while (await reader.ReadAsync())
            {
                adjustSteps.Add(new BundleAdjustStepSaldoDto
                {
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    SaldoRejectPrint = reader.GetInt32(reader.GetOrdinal("SaldoRejectPrint")),
                    SaldoRejectFabric = reader.GetInt32(reader.GetOrdinal("SaldoRejectFabric")),
                    SaldoRejectSewing = reader.GetInt32(reader.GetOrdinal("SaldoRejectSewing")),
                    SaldoRejectRework = reader.GetInt32(reader.GetOrdinal("SaldoRejectRework")),
                    SaldoLost = reader.GetInt32(reader.GetOrdinal("SaldoLost")),
                    NextDivisionId = reader.IsDBNull(reader.GetOrdinal("NextDivisionId")) ? null : reader.GetInt32(reader.GetOrdinal("NextDivisionId")),
                    NextDivisionName = reader.IsDBNull(reader.GetOrdinal("NextDivisionName")) ? null : reader.GetString(reader.GetOrdinal("NextDivisionName")),
                });
            }

            return new BundleScanInfoDto { Bundle = bundle, Timeline = timeline, Action = action, AdjustSteps = adjustSteps };
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    private class ArticleWipStepRow
    {
        public int ArticleWorkflowId { get; set; }
        public string StepName { get; set; } = string.Empty;
        public int SortOrder { get; set; }
        public bool RequiresBundle { get; set; }
        public int ReceivedPcs { get; set; }
        public int ReceivedBundleCount { get; set; }
        public int CompletedPcs { get; set; }
        public int CompletedBundleCount { get; set; }
        public int TotalBundlePcs { get; set; }
        public int TotalBundleCount { get; set; }
        public int QtyOrder { get; set; }
        public int QtyOk { get; set; }
        public int QtyReject { get; set; }
    }

    public async Task<List<ArticleWipStepDto>> GetArticleWipAsync(int articleId)
    {
        var articleIdParam = new SqlParameter("@ArticleId", articleId);

        var rows = await _db.Database
            .SqlQueryRaw<ArticleWipStepRow>("EXEC SIS_Article_Wip @ArticleId = @ArticleId", articleIdParam)
            .ToListAsync();

        return rows.Select(row => new ArticleWipStepDto
        {
            ArticleWorkflowId = row.ArticleWorkflowId,
            StepName = row.StepName,
            SortOrder = row.SortOrder,
            RequiresBundle = row.RequiresBundle,
            ReceivedPcs = row.ReceivedPcs,
            ReceivedBundleCount = row.ReceivedBundleCount,
            CompletedPcs = row.CompletedPcs,
            CompletedBundleCount = row.CompletedBundleCount,
            TotalBundlePcs = row.TotalBundlePcs,
            TotalBundleCount = row.TotalBundleCount,
            QtyOrder = row.QtyOrder,
            QtyOk = row.QtyOk,
            QtyReject = row.QtyReject
        }).ToList();
    }

    public async Task<(bool Success, string Error, int PrintJobId)> ReprintAsync(int bundleId, int copies, int userId)
    {
        var bundleIdParam = new SqlParameter("@BundleId", bundleId);
        var publicBaseUrlParam = new SqlParameter("@PublicBaseUrl", (object?)_publicBaseUrl ?? DBNull.Value);
        var copiesParam = new SqlParameter("@Copies", copies);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_Bundle_ReprintLabel @BundleId = @BundleId, @PublicBaseUrl = @PublicBaseUrl, @Copies = @Copies, @UserId = @UserId",
                    bundleIdParam, publicBaseUrlParam, copiesParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    // Prompt: "Print Label Cacat" -- reprint label bundle (template sama, lihat
    // SIS_Bundle_ReprintLabel) sebanyak Copies lembar, remark di-override dengan catatan +
    // ringkasan qty cacat yang sudah dirakit di klien (BundleScanCard).
    public async Task<(bool Success, string Error, int PrintJobId)> PrintDefectLabelAsync(int bundleId, int copies, string? remark, int userId)
    {
        var bundleIdParam = new SqlParameter("@BundleId", bundleId);
        var publicBaseUrlParam = new SqlParameter("@PublicBaseUrl", (object?)_publicBaseUrl ?? DBNull.Value);
        var copiesParam = new SqlParameter("@Copies", copies);
        var remarkOverrideParam = new SqlParameter("@RemarkOverride", (object?)remark ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_Bundle_ReprintLabel @BundleId = @BundleId, @PublicBaseUrl = @PublicBaseUrl, @Copies = @Copies, @RemarkOverride = @RemarkOverride, @UserId = @UserId",
                    bundleIdParam, publicBaseUrlParam, copiesParam, remarkOverrideParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }
}

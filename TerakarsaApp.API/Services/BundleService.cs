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
        public int NewPrintJobId { get; set; }
        public int NewBundleNo { get; set; }
    }

    public async Task<ArticleBundlesDto> GetByArticleAsync(int articleId)
    {
        var articleIdParam1 = new SqlParameter("@ArticleId", articleId);
        var articleIdParam2 = new SqlParameter("@ArticleId", articleId);

        var summary = await _db.Database
            .SqlQueryRaw<BundleSizeSummaryDto>("EXEC SIS_Article_BundleSummary @ArticleId = @ArticleId", articleIdParam1)
            .ToListAsync();

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
        var resourcePersonNameParam = new SqlParameter("@ResourcePersonName", (object?)request.ResourcePersonName ?? DBNull.Value);
        var publicBaseUrlParam = new SqlParameter("@PublicBaseUrl", (object?)_publicBaseUrl ?? DBNull.Value);
        var bundlingResourceIdParam = new SqlParameter("@BundlingResourceId", (object?)request.BundlingResourceId ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<BundleCreateResultRow>(
                    "EXEC SIS_Bundle_Manage @Action = @Action, @ArticleId = @ArticleId, @ArticleSizeId = @ArticleSizeId, @Qty = @Qty, @ResourceId = @ResourceId, @ResourcePersonName = @ResourcePersonName, @PublicBaseUrl = @PublicBaseUrl, @BundlingResourceId = @BundlingResourceId, @UserId = @UserId",
                    actionParam, articleIdParam, articleSizeIdParam, qtyParam, resourceIdParam, resourcePersonNameParam, publicBaseUrlParam, bundlingResourceIdParam, userIdParam)
                .ToListAsync();

            var row = result.First();
            return (true, string.Empty, new BundleCreateResult { Id = row.NewId, PrintJobId = row.NewPrintJobId, BundleNo = row.NewBundleNo });
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
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)request.ResourceId ?? DBNull.Value);
        var resourcePersonNameParam = new SqlParameter("@ResourcePersonName", (object?)request.ResourcePersonName ?? DBNull.Value);
        var bundlingResourceIdParam = new SqlParameter("@BundlingResourceId", (object?)request.BundlingResourceId ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Bundle_Manage @Action = @Action, @Id = @Id, @Qty = @Qty, @ResourceId = @ResourceId, @ResourcePersonName = @ResourcePersonName, @BundlingResourceId = @BundlingResourceId, @UserId = @UserId",
                actionParam, idParam, qtyParam, resourceIdParam, resourcePersonNameParam, bundlingResourceIdParam, userIdParam);
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
            };

            await reader.NextResultAsync();
            var timeline = new List<BundleScanTimelineDto>();
            while (await reader.ReadAsync())
            {
                timeline.Add(new BundleScanTimelineDto
                {
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    SizeName = reader.IsDBNull(reader.GetOrdinal("SizeName")) ? null : reader.GetString(reader.GetOrdinal("SizeName")),
                    DivisionName = reader.IsDBNull(reader.GetOrdinal("DivisionName")) ? null : reader.GetString(reader.GetOrdinal("DivisionName")),
                    ResourceName = reader.IsDBNull(reader.GetOrdinal("ResourceName")) ? null : reader.GetString(reader.GetOrdinal("ResourceName")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyRejectPrint = reader.GetInt32(reader.GetOrdinal("QtyRejectPrint")),
                    QtyRejectFabric = reader.GetInt32(reader.GetOrdinal("QtyRejectFabric")),
                    QtyRejectSewing = reader.GetInt32(reader.GetOrdinal("QtyRejectSewing")),
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
                var actionRemarkOrdinal = reader.GetOrdinal("ActionRemark");
                action.ActionRemark = reader.IsDBNull(actionRemarkOrdinal) ? null : reader.GetString(actionRemarkOrdinal);
            }

            return new BundleScanInfoDto { Bundle = bundle, Timeline = timeline, Action = action };
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

    public async Task<(bool Success, string Error, int PrintJobId)> ReprintAsync(int bundleId, int userId)
    {
        var bundleIdParam = new SqlParameter("@BundleId", bundleId);
        var publicBaseUrlParam = new SqlParameter("@PublicBaseUrl", (object?)_publicBaseUrl ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_Bundle_ReprintLabel @BundleId = @BundleId, @PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId",
                    bundleIdParam, publicBaseUrlParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }
}

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
            Bundles = bundles
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
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<BundleCreateResultRow>(
                    "EXEC SIS_Bundle_Manage @Action = @Action, @ArticleId = @ArticleId, @ArticleSizeId = @ArticleSizeId, @Qty = @Qty, @ResourceId = @ResourceId, @ResourcePersonName = @ResourcePersonName, @PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId",
                    actionParam, articleIdParam, articleSizeIdParam, qtyParam, resourceIdParam, resourcePersonNameParam, publicBaseUrlParam, userIdParam)
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
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Bundle_Manage @Action = @Action, @Id = @Id, @Qty = @Qty, @ResourceId = @ResourceId, @ResourcePersonName = @ResourcePersonName, @UserId = @UserId",
                actionParam, idParam, qtyParam, resourceIdParam, resourcePersonNameParam, userIdParam);
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

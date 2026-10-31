using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Bundles;

namespace TerakarsaApp.API.Services;

// Prompt 82 -- bundle anak, pemecahan, dan selisih.
// Semua mutasi lewat SIS_BundleSplit_Manage (@Action = 'SPLIT' | 'FOUND'); pembacaan
// lewat SIS_BundleSplit_Info / _MissingByArticle / _MissingSizes / _MissingBundles.
// Lihat sql/sp_BundleSplit_Manage.sql dan sql/sp_BundleSplit_Select.sql.
public class BundleSplitService
{
    private readonly AppDbContext _db;
    private readonly string _publicBaseUrl;

    public BundleSplitService(AppDbContext db, IOptions<AppOptions> appOptions)
    {
        _db = db;
        _publicBaseUrl = appOptions.Value.PublicBaseUrl;
    }

    // SIS_BundleSplit_Info mengembalikan DUA result set (header + anak yang sudah lahir) --
    // pola pembacaannya sama dengan BundleService.GetScanInfoAsync (SqlCommand mentah di
    // atas koneksi AppDbContext, EF SqlQueryRaw hanya mendukung satu result set).
    public async Task<BundleSplitInfoResult> GetInfoAsync(int bundleId, int articleWorkflowId)
    {
        var result = new BundleSplitInfoResult();

        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_BundleSplit_Info";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@BundleId", bundleId));
            cmd.Parameters.Add(new SqlParameter("@ArticleWorkflowId", articleWorkflowId));

            using var reader = await cmd.ExecuteReaderAsync();

            if (await reader.ReadAsync())
            {
                result.Header = new BundleSplitInfoDto
                {
                    BundleId = reader.GetInt32(reader.GetOrdinal("BundleId")),
                    Serial = reader.GetString(reader.GetOrdinal("Serial")),
                    SequenceNo = reader.GetInt32(reader.GetOrdinal("SequenceNo")),
                    BundleStatus = reader.GetString(reader.GetOrdinal("BundleStatus")),
                    BundleNo = reader.GetInt32(reader.GetOrdinal("BundleNo")),
                    BundleLetter = reader.IsDBNull(reader.GetOrdinal("BundleLetter")) ? null : reader.GetString(reader.GetOrdinal("BundleLetter")),
                    RootBundleNo = reader.GetInt32(reader.GetOrdinal("RootBundleNo")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                    NoPo = reader.IsDBNull(reader.GetOrdinal("NoPo")) ? null : reader.GetString(reader.GetOrdinal("NoPo")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    QtyMasuk = reader.GetInt32(reader.GetOrdinal("QtyMasuk")),
                    QtyNow = reader.GetInt32(reader.GetOrdinal("QtyNow")),
                    ExistingChildQty = reader.GetInt32(reader.GetOrdinal("ExistingChildQty")),
                    ExistingMissing = reader.GetInt32(reader.GetOrdinal("ExistingMissing")),
                    MissingQty = reader.GetInt32(reader.GetOrdinal("MissingQty")),
                    NextSequenceNo = reader.GetInt32(reader.GetOrdinal("NextSequenceNo")),
                    IsEdit = reader.GetBoolean(reader.GetOrdinal("IsEdit")),
                    IsLocked = reader.GetBoolean(reader.GetOrdinal("IsLocked")),
                    NextStationDone = reader.GetBoolean(reader.GetOrdinal("NextStationDone")),
                    BlockedByStepName = reader.IsDBNull(reader.GetOrdinal("BlockedByStepName")) ? null : reader.GetString(reader.GetOrdinal("BlockedByStepName")),
                    IsBundlingStep = reader.GetBoolean(reader.GetOrdinal("IsBundlingStep")),
                    CanSubmit = reader.GetBoolean(reader.GetOrdinal("CanSubmit")),
                    NextDivisionId = reader.IsDBNull(reader.GetOrdinal("NextDivisionId")) ? null : reader.GetInt32(reader.GetOrdinal("NextDivisionId")),
                    NextDivisionName = reader.IsDBNull(reader.GetOrdinal("NextDivisionName")) ? null : reader.GetString(reader.GetOrdinal("NextDivisionName")),
                    IsLastStep = reader.GetBoolean(reader.GetOrdinal("IsLastStep")),
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Children.Add(new BundleSplitChildDto
                {
                    BundleId = reader.GetInt32(reader.GetOrdinal("BundleId")),
                    Serial = reader.GetString(reader.GetOrdinal("Serial")),
                    SequenceNo = reader.GetInt32(reader.GetOrdinal("SequenceNo")),
                    DisplayCode = reader.GetString(reader.GetOrdinal("DisplayCode")),
                    Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                    Status = reader.GetString(reader.GetOrdinal("Status")),
                    RejectCategory = reader.IsDBNull(reader.GetOrdinal("RejectCategory")) ? null : reader.GetString(reader.GetOrdinal("RejectCategory")),
                    RejectReason = reader.IsDBNull(reader.GetOrdinal("RejectReason")) ? null : reader.GetString(reader.GetOrdinal("RejectReason")),
                });
            }
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }

        return result;
    }

    public async Task<(bool Success, string Error, List<BundleSplitResultDto> Children)> SplitAsync(
        BundleSplitRequest request, int resourceId, int? actingDivisionId, bool allowResourceChange, int userId)
    {
        var rowsJson = JsonSerializer.Serialize(request.Rows.Select(r => new
        {
            r.Category,
            Reason = r.Reason,
            r.Qty
        }));

        var parameters = new[]
        {
            new SqlParameter("@Action", "SPLIT"),
            new SqlParameter("@BundleId", request.BundleId),
            new SqlParameter("@ArticleWorkflowId", request.ArticleWorkflowId),
            new SqlParameter("@QtyOk", request.QtyOk),
            new SqlParameter("@ResultsJson", rowsJson),
            new SqlParameter("@AutoReceiveResourceId", (object?)request.AutoReceiveResourceId ?? DBNull.Value),
            new SqlParameter("@ResourceId", resourceId),
            new SqlParameter("@ActingDivisionId", (object?)actingDivisionId ?? DBNull.Value),
            new SqlParameter("@ActingAllowResourceChange", allowResourceChange),
            new SqlParameter("@PublicBaseUrl", _publicBaseUrl),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            var children = await _db.Database
                .SqlQueryRaw<BundleSplitResultDto>(
                    "EXEC SIS_BundleSplit_Manage @Action = @Action, @BundleId = @BundleId, @ArticleWorkflowId = @ArticleWorkflowId, "
                    + "@QtyOk = @QtyOk, @ResultsJson = @ResultsJson, @AutoReceiveResourceId = @AutoReceiveResourceId, "
                    + "@ResourceId = @ResourceId, @ActingDivisionId = @ActingDivisionId, "
                    + "@ActingAllowResourceChange = @ActingAllowResourceChange, @PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId",
                    parameters)
                .ToListAsync();

            return (true, string.Empty, children);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, new List<BundleSplitResultDto>());
        }
    }

    public async Task<(bool Success, string Error, List<BundleSplitResultDto> Children)> FoundAsync(
        BundleFoundRequest request, int resourceId, int? actingDivisionId, int userId)
    {
        var allocJson = request.Allocations.Count == 0
            ? null
            : JsonSerializer.Serialize(request.Allocations.Select(a => new { a.BundleId, a.Qty }));

        var parameters = new[]
        {
            new SqlParameter("@Action", "FOUND"),
            new SqlParameter("@ArticleSizeId", request.ArticleSizeId),
            new SqlParameter("@QtyFound", request.QtyFound),
            new SqlParameter("@Condition", request.Condition),
            new SqlParameter("@Reason", (object?)request.Reason ?? DBNull.Value),
            new SqlParameter("@AllocationJson", (object?)allocJson ?? DBNull.Value),
            new SqlParameter("@ResourceId", resourceId),
            new SqlParameter("@ActingDivisionId", (object?)actingDivisionId ?? DBNull.Value),
            new SqlParameter("@PublicBaseUrl", _publicBaseUrl),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            var children = await _db.Database
                .SqlQueryRaw<BundleSplitResultDto>(
                    "EXEC SIS_BundleSplit_Manage @Action = @Action, @ArticleSizeId = @ArticleSizeId, @QtyFound = @QtyFound, "
                    + "@Condition = @Condition, @Reason = @Reason, @AllocationJson = @AllocationJson, "
                    + "@ResourceId = @ResourceId, @ActingDivisionId = @ActingDivisionId, "
                    + "@PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId",
                    parameters)
                .ToListAsync();

            return (true, string.Empty, children);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, new List<BundleSplitResultDto>());
        }
    }

    // resourceId: line pemanggil -- angka Hilang/Lebih/Tidak lengkap hanya menghitung
    // selisih yang dinyatakan hilang oleh line itu sendiri (lihat komentar atribusi di
    // sql/sp_BundleSplit_Select.sql). NULL = semua line.
    public async Task<List<BundleMissingSummaryDto>> GetMissingByArticleAsync(int? articleId, int? resourceId)
    {
        var p = new SqlParameter("@ArticleId", (object?)articleId ?? DBNull.Value);
        var resourceParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        return await _db.Database
            .SqlQueryRaw<BundleMissingSummaryDto>(
                "EXEC SIS_BundleSplit_MissingByArticle @ArticleId = @ArticleId, @ResourceId = @ResourceId",
                p, resourceParam)
            .ToListAsync();
    }

    public async Task<List<BundleMissingSizeDto>> GetMissingSizesAsync(int articleId, int? resourceId)
    {
        var p = new SqlParameter("@ArticleId", articleId);
        var resourceParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        return await _db.Database
            .SqlQueryRaw<BundleMissingSizeDto>(
                "EXEC SIS_BundleSplit_MissingSizes @ArticleId = @ArticleId, @ResourceId = @ResourceId",
                p, resourceParam)
            .ToListAsync();
    }

    // Dua cara pakai (lihat komentar SP): articleSizeId = kandidat alokasi satu size,
    // articleId = daftar seluruh bundle ber-selisih terbuka artikel itu lintas size
    // (daftar "Bundle yang masih hilang" di bawah form Barang ketemu, qty NULL).
    public async Task<List<BundleMissingBundleDto>> GetMissingBundlesAsync(
        int? articleSizeId, int? qty, int? resourceId, int? articleId = null)
    {
        var sizeParam = new SqlParameter("@ArticleSizeId", (object?)articleSizeId ?? DBNull.Value);
        var qtyParam = new SqlParameter("@Qty", (object?)qty ?? DBNull.Value);
        var resourceParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var articleParam = new SqlParameter("@ArticleId", (object?)articleId ?? DBNull.Value);
        return await _db.Database
            .SqlQueryRaw<BundleMissingBundleDto>(
                "EXEC SIS_BundleSplit_MissingBundles @ArticleSizeId = @ArticleSizeId, @Qty = @Qty, @ResourceId = @ResourceId, @ArticleId = @ArticleId",
                sizeParam, qtyParam, resourceParam, articleParam)
            .ToListAsync();
    }
}

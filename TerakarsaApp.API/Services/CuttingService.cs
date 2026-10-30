using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Cutting;

namespace TerakarsaApp.API.Services;

// Prompt 78-80 -- module Cutting (stok bundle dari hamparan).
//
// Semua akses data lewat SP (sql/cutting/sp_78_Cutting.sql & sp_80_CuttingTake.sql).
// PublicBaseUrl dipakai untuk merakit qr_content stiker bundle cutting -- isinya
// SENGAJA format QR bundle yang sudah ada ({PublicBaseUrl}/b/<serial>) supaya scanner
// station mengenalinya tanpa perubahan; serial-nya pun digenerate di SP seperti bundle
// manual. Kode lapangan (H06-M-03) tersimpan terpisah di bundles.cutting_code.
public class CuttingService
{
    private readonly AppDbContext _db;
    private readonly string _publicBaseUrl;

    public CuttingService(AppDbContext db, IOptions<AppOptions> appOptions)
    {
        _db = db;
        _publicBaseUrl = appOptions.Value.PublicBaseUrl;
    }

    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    // ==================== dropdown & hitungan ====================

    public async Task<List<CuttingArticleDto>> GetArticlesAsync()
        => await _db.Database.SqlQueryRaw<CuttingArticleDto>("EXEC SIS_Cutting_Articles").ToListAsync();

    public async Task<List<CuttingSizeDto>> GetArticleSizesAsync(int articleId)
    {
        var p = new SqlParameter("@ArticleId", articleId);
        return await _db.Database
            .SqlQueryRaw<CuttingSizeDto>("EXEC SIS_Cutting_ArticleSizes @ArticleId = @ArticleId", p)
            .ToListAsync();
    }

    private class NextFromRow { public int NextFrom { get; set; } }
    private class NextCodeRow { public string NextCode { get; set; } = string.Empty; }

    public async Task<int> GetNextNumberAsync(int articleId, int articleSizeId)
    {
        var articleParam = new SqlParameter("@ArticleId", articleId);
        var sizeParam = new SqlParameter("@ArticleSizeId", articleSizeId);

        var rows = await _db.Database
            .SqlQueryRaw<NextFromRow>(
                "EXEC SIS_Cutting_NextNumber @ArticleId = @ArticleId, @ArticleSizeId = @ArticleSizeId",
                articleParam, sizeParam)
            .ToListAsync();

        return rows.FirstOrDefault()?.NextFrom ?? 1;
    }

    public async Task<string> GetNextSpreadCodeAsync(int articleId)
    {
        var p = new SqlParameter("@ArticleId", articleId);
        var rows = await _db.Database
            .SqlQueryRaw<NextCodeRow>("EXEC SIS_Cutting_NextSpreadCode @ArticleId = @ArticleId", p)
            .ToListAsync();

        return rows.FirstOrDefault()?.NextCode ?? "H01";
    }

    public async Task<List<CuttingSuggestItemDto>> SuggestBundlesAsync(int sheets, int target)
    {
        var sheetsParam = new SqlParameter("@Sheets", sheets);
        var targetParam = new SqlParameter("@Target", target);

        return await _db.Database
            .SqlQueryRaw<CuttingSuggestItemDto>(
                "EXEC SIS_Cutting_SuggestBundles @Sheets = @Sheets, @Target = @Target",
                sheetsParam, targetParam)
            .ToListAsync();
    }

    // ==================== simpan hamparan ====================

    private class SpreadCreateRow
    {
        public int NewId { get; set; }
        public int BundleCount { get; set; }
    }

    private class JobCountRow { public int JobCount { get; set; } }

    // CREATE + (opsional) enqueue stiker & MARK_PRINTED. Transaksi pembuatan bundle ada
    // di dalam SP; enqueue stiker dijalankan setelahnya (job cetak gagal tidak boleh
    // membatalkan hamparan yang sudah tersimpan).
    public async Task<(bool Success, string Error, SpreadCreateResultDto? Hasil)> CreateSpreadAsync(
        SpreadCreateRequest request, int userId)
    {
        var sizesJson = JsonSerializer.Serialize(request.Sizes, Json);
        var bundlesJson = JsonSerializer.Serialize(request.Bundles, Json);

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<SpreadCreateRow>(
                    "EXEC SIS_Spread_Manage @Action = 'CREATE', @ArticleId = @ArticleId, " +
                    "@SpreadCode = @SpreadCode, @SpreadDate = @SpreadDate, @SetCount = @SetCount, " +
                    "@SheetsPerSet = @SheetsPerSet, @Note = @Note, @SizesJson = @SizesJson, " +
                    "@BundlesJson = @BundlesJson, @UserId = @UserId",
                    new SqlParameter("@ArticleId", request.ArticleId),
                    new SqlParameter("@SpreadCode", request.SpreadCode ?? string.Empty),
                    new SqlParameter("@SpreadDate", (object?)request.SpreadDate ?? DBNull.Value),
                    new SqlParameter("@SetCount", request.SetCount),
                    new SqlParameter("@SheetsPerSet", request.SheetsPerSet),
                    new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value),
                    new SqlParameter("@SizesJson", sizesJson),
                    new SqlParameter("@BundlesJson", bundlesJson),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            var created = rows.FirstOrDefault();
            if (created is null) return (false, "Hamparan gagal disimpan.", null);

            var hasil = new SpreadCreateResultDto
            {
                SpreadId = created.NewId,
                BundleCount = created.BundleCount
            };

            if (request.Print)
            {
                var (printOk, printError, jobs) = await PrintAsync(created.NewId, null, userId);
                if (!printOk) return (false, printError, hasil);
                hasil.JobCount = jobs;
            }

            return (true, string.Empty, hasil);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error)> UpdateSpreadHeaderAsync(
        int id, SpreadHeaderUpdateRequest request, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Spread_Manage @Action = 'UPDATE_HEADER', @Id = @Id, @SpreadCode = @SpreadCode, " +
                "@SpreadDate = @SpreadDate, @Note = @Note, @UserId = @UserId",
                new SqlParameter("@Id", id),
                new SqlParameter("@SpreadCode", request.SpreadCode ?? string.Empty),
                new SqlParameter("@SpreadDate", (object?)request.SpreadDate ?? DBNull.Value),
                new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value),
                new SqlParameter("@UserId", userId));
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteSpreadAsync(int id, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Spread_Manage @Action = 'DELETE', @Id = @Id, @UserId = @UserId",
                new SqlParameter("@Id", id),
                new SqlParameter("@UserId", userId));
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Enqueue stiker + MARK_PRINTED. bundleIds null/kosong = semua bundle hamparan.
    public async Task<(bool Success, string Error, int JobCount)> PrintAsync(
        int spreadId, List<int>? bundleIds, int userId)
    {
        var idsJson = JsonSerializer.Serialize(bundleIds ?? new List<int>());

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<JobCountRow>(
                    "EXEC SIS_CuttingBundle_Print @SpreadId = @SpreadId, @BundleIdsJson = @BundleIdsJson, " +
                    "@PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId",
                    new SqlParameter("@SpreadId", spreadId),
                    new SqlParameter("@BundleIdsJson", idsJson),
                    new SqlParameter("@PublicBaseUrl", _publicBaseUrl),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            var jobs = rows.FirstOrDefault()?.JobCount ?? 0;

            // Cetak seluruh hamparan = hamparan dianggap sudah dicetak (DRAFT -> PRINTED).
            if (bundleIds is null || bundleIds.Count == 0)
            {
                await _db.Database.ExecuteSqlRawAsync(
                    "EXEC SIS_Spread_Manage @Action = 'MARK_PRINTED', @Id = @Id, @UserId = @UserId",
                    new SqlParameter("@Id", spreadId),
                    new SqlParameter("@UserId", userId));
            }

            return (true, string.Empty, jobs);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    // ==================== edit bundle dalam set ====================

    public Task<(bool Success, string Error)> UpdateBundleQtyAsync(
        List<SpreadBundleQtyInput> bundles, int userId)
        => ManageBundleAsync("UPDATE_QTY", null, null, null, null, bundles, userId);

    public Task<(bool Success, string Error)> AddBundleAsync(
        SpreadBundleAddRequest request, int userId)
        => ManageBundleAsync("ADD", request.SpreadSizeId, request.SetNo, null, request.Qty, request.Bundles, userId);

    public Task<(bool Success, string Error)> RemoveBundleAsync(
        int bundleId, List<SpreadBundleQtyInput> bundles, int userId)
        => ManageBundleAsync("REMOVE", null, null, bundleId, null, bundles, userId);

    private async Task<(bool Success, string Error)> ManageBundleAsync(
        string action, int? spreadSizeId, int? setNo, int? bundleId, int? qty,
        List<SpreadBundleQtyInput>? bundles, int userId)
    {
        var bundlesJson = JsonSerializer.Serialize(bundles ?? new List<SpreadBundleQtyInput>(), Json);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_SpreadBundle_Manage @Action = @Action, @SpreadSizeId = @SpreadSizeId, " +
                "@SetNo = @SetNo, @BundleId = @BundleId, @Qty = @Qty, @BundlesJson = @BundlesJson, " +
                "@UserId = @UserId",
                new SqlParameter("@Action", action),
                new SqlParameter("@SpreadSizeId", (object?)spreadSizeId ?? DBNull.Value),
                new SqlParameter("@SetNo", (object?)setNo ?? DBNull.Value),
                new SqlParameter("@BundleId", (object?)bundleId ?? DBNull.Value),
                new SqlParameter("@Qty", (object?)qty ?? DBNull.Value),
                new SqlParameter("@BundlesJson", bundlesJson),
                new SqlParameter("@UserId", userId));
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // ==================== daftar & detail ====================

    public async Task<List<SpreadListItemDto>> GetSpreadsAsync(
        int? articleId, string? status, DateTime? dateFrom, DateTime? dateTo)
    {
        return await _db.Database
            .SqlQueryRaw<SpreadListItemDto>(
                "EXEC SIS_Spread_List @ArticleId = @ArticleId, @Status = @Status, " +
                "@DateFrom = @DateFrom, @DateTo = @DateTo",
                new SqlParameter("@ArticleId", (object?)articleId ?? DBNull.Value),
                new SqlParameter("@Status", (object?)status ?? DBNull.Value),
                new SqlParameter("@DateFrom", (object?)dateFrom ?? DBNull.Value),
                new SqlParameter("@DateTo", (object?)dateTo ?? DBNull.Value))
            .ToListAsync();
    }

    // SIS_Spread_Detail mengembalikan 3 result set (header, sizes, bundles) -- EF Core
    // SqlQueryRaw hanya mendukung satu, jadi pakai SqlCommand mentah + NextResultAsync
    // (pola BundleService.GetScanInfoAsync).
    public async Task<SpreadDetailDto?> GetSpreadDetailAsync(int id)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Spread_Detail";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@Id", id));

            using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return null;

            var hasil = new SpreadDetailDto
            {
                Header = new SpreadDetailHeaderDto
                {
                    SpreadId = reader.GetInt32(reader.GetOrdinal("SpreadId")),
                    SpreadCode = reader.GetString(reader.GetOrdinal("SpreadCode")),
                    SpreadDate = reader.GetDateTime(reader.GetOrdinal("SpreadDate")),
                    SetCount = reader.GetInt32(reader.GetOrdinal("SetCount")),
                    SheetsPerSet = reader.GetInt32(reader.GetOrdinal("SheetsPerSet")),
                    Status = reader.GetString(reader.GetOrdinal("Status")),
                    PrintedAt = GetNullableDate(reader, "PrintedAt"),
                    Note = GetNullableString(reader, "Note"),
                    ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    BundleTargetQty = reader.GetInt32(reader.GetOrdinal("BundleTargetQty")),
                    NoPo = GetNullableString(reader, "NoPo"),
                    ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                    CreatedByName = GetNullableString(reader, "CreatedByName"),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    TotalBundles = reader.GetInt32(reader.GetOrdinal("TotalBundles")),
                    TotalPcs = reader.GetInt32(reader.GetOrdinal("TotalPcs")),
                    StockBundles = reader.GetInt32(reader.GetOrdinal("StockBundles")),
                    StockPcs = reader.GetInt32(reader.GetOrdinal("StockPcs")),
                    TakenBundles = reader.GetInt32(reader.GetOrdinal("TakenBundles")),
                }
            };

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                hasil.Sizes.Add(new SpreadDetailSizeDto
                {
                    SpreadSizeId = reader.GetInt32(reader.GetOrdinal("SpreadSizeId")),
                    ArticleSizeId = reader.GetInt32(reader.GetOrdinal("ArticleSizeId")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    SizeSortOrder = reader.GetInt32(reader.GetOrdinal("SizeSortOrder")),
                    SetCount = reader.GetInt32(reader.GetOrdinal("SetCount")),
                    NumberFrom = reader.GetInt32(reader.GetOrdinal("NumberFrom")),
                    NumberTo = reader.GetInt32(reader.GetOrdinal("NumberTo")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                hasil.Bundles.Add(new SpreadDetailBundleDto
                {
                    BundleId = reader.GetInt32(reader.GetOrdinal("BundleId")),
                    CuttingCode = reader.GetString(reader.GetOrdinal("CuttingCode")),
                    Serial = reader.GetString(reader.GetOrdinal("Serial")),
                    SpreadSizeId = reader.GetInt32(reader.GetOrdinal("SpreadSizeId")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    SizeSortOrder = reader.GetInt32(reader.GetOrdinal("SizeSortOrder")),
                    SetNo = reader.GetInt32(reader.GetOrdinal("SetNo")),
                    BundleSeq = reader.GetInt32(reader.GetOrdinal("BundleSeq")),
                    Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                    NumberFrom = reader.GetInt32(reader.GetOrdinal("NumberFrom")),
                    NumberTo = reader.GetInt32(reader.GetOrdinal("NumberTo")),
                    StockStatus = reader.GetString(reader.GetOrdinal("StockStatus")),
                    NeedsReprint = reader.GetBoolean(reader.GetOrdinal("NeedsReprint")),
                    TakenAt = GetNullableDate(reader, "TakenAt"),
                    TakenByResourceName = GetNullableString(reader, "TakenByResourceName"),
                });
            }

            return hasil;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // ==================== stok bundle (landing) ====================

    public async Task<CuttingStockSummaryDto> GetStockSummaryAsync()
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Cutting_StockSummary";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;

            using var reader = await cmd.ExecuteReaderAsync();

            var hasil = new CuttingStockSummaryDto();

            if (await reader.ReadAsync())
            {
                hasil.Totals = new CuttingStockTotalsDto
                {
                    StockBundles = reader.GetInt32(reader.GetOrdinal("StockBundles")),
                    StockPcs = reader.GetInt32(reader.GetOrdinal("StockPcs")),
                    TakenToday = reader.GetInt32(reader.GetOrdinal("TakenToday")),
                    DraftSpreads = reader.GetInt32(reader.GetOrdinal("DraftSpreads")),
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                hasil.Sizes.Add(new CuttingStockSizeDto
                {
                    ProjectId = reader.GetInt32(reader.GetOrdinal("ProjectId")),
                    NoPo = GetNullableString(reader, "NoPo"),
                    ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                    ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    BundleTargetQty = reader.GetInt32(reader.GetOrdinal("BundleTargetQty")),
                    SpreadCount = reader.GetInt32(reader.GetOrdinal("SpreadCount")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    ArticleSizeId = reader.GetInt32(reader.GetOrdinal("ArticleSizeId")),
                    SizeSortOrder = reader.GetInt32(reader.GetOrdinal("SizeSortOrder")),
                    PoQty = reader.GetInt32(reader.GetOrdinal("PoQty")),
                    CutPcs = reader.GetInt32(reader.GetOrdinal("CutPcs")),
                    CutBundlePcs = reader.GetInt32(reader.GetOrdinal("CutBundlePcs")),
                    CutLogPcs = reader.GetInt32(reader.GetOrdinal("CutLogPcs")),
                    TotalBundles = reader.GetInt32(reader.GetOrdinal("TotalBundles")),
                    StockBundles = reader.GetInt32(reader.GetOrdinal("StockBundles")),
                    TakenBundles = reader.GetInt32(reader.GetOrdinal("TakenBundles")),
                    StockPcs = reader.GetInt32(reader.GetOrdinal("StockPcs")),
                });
            }

            return hasil;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<List<CuttingTakenTodayDto>> GetTakenTodayAsync()
        => await _db.Database.SqlQueryRaw<CuttingTakenTodayDto>("EXEC SIS_Cutting_TakenToday").ToListAsync();

    // ==================== Prompt 80: Scan Stok Bundle ====================

    // @Code boleh cutting_code (H06-M-03), serial (B26-000153), atau URL QR penuh --
    // normalisasi ada di SP supaya satu sumber. Lookup TIDAK mengubah apa pun.
    public async Task<(bool Success, string Error, CuttingBundleScanDto? Bundle)> LookupBundleAsync(
        string code, int? articleId)
    {
        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<CuttingBundleScanDto>(
                    "EXEC SIS_CuttingBundle_Lookup @Code = @Code, @ArticleId = @ArticleId",
                    new SqlParameter("@Code", code ?? string.Empty),
                    new SqlParameter("@ArticleId", (object?)articleId ?? DBNull.Value))
                .ToListAsync();

            var bundle = rows.FirstOrDefault();
            return bundle is null
                ? (false, "Bundle tidak ditemukan.", null)
                : (true, string.Empty, bundle);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error, CuttingBundleTakeResultDto? Hasil)> TakeBundlesAsync(
        CuttingBundleTakeRequest request, int userId)
    {
        var idsJson = JsonSerializer.Serialize(request.BundleIds ?? new List<int>());

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<CuttingBundleTakeResultDto>(
                    "EXEC SIS_CuttingBundle_Take @BundleIdsJson = @BundleIdsJson, " +
                    "@ResourceId = @ResourceId, @UserId = @UserId, " +
                    "@TargetResourceId = @TargetResourceId, @EmployeeId = @EmployeeId",
                    new SqlParameter("@BundleIdsJson", idsJson),
                    new SqlParameter("@ResourceId", request.ResourceId),
                    new SqlParameter("@UserId", userId),
                    // Prompt 81: 0 = tanpa claim -- SP menormalkan <= 0 jadi NULL dan
                    // memakai cabang Prompt 80 (log pending).
                    new SqlParameter("@TargetResourceId", request.TargetResourceId),
                    new SqlParameter("@EmployeeId", request.EmployeeId))
                .ToListAsync();

            return (true, string.Empty, rows.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    // ==================== helper ====================

    private static string? GetNullableString(SqlDataReader reader, string column)
    {
        var i = reader.GetOrdinal(column);
        return reader.IsDBNull(i) ? null : reader.GetString(i);
    }

    private static DateTime? GetNullableDate(SqlDataReader reader, string column)
    {
        var i = reader.GetOrdinal(column);
        return reader.IsDBNull(i) ? null : reader.GetDateTime(i);
    }
}

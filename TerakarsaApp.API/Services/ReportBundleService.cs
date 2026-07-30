using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.API.Services;

// Prompt 13: Modul Laporan Arus Bundle -- murni read-only (SIS_Report_* di
// sql/sp_Report_Bundle.sql), tidak menulis apa pun ke database.
public class ReportBundleService
{
    private readonly AppDbContext _db;

    public ReportBundleService(AppDbContext db)
    {
        _db = db;
    }

    // Fix: order-by-klik-header + pagination -- pola sama dengan ProjectService.GetPagedAsync
    // (dua panggilan SP: LIST untuk halaman data, COUNT untuk total + breakdown per status
    // dipakai badge ringkasan). Lihat SIS_Report_BundleWip di sql/sp_Report_Bundle.sql.
    private class BundleWipCountRow
    {
        public int TotalCount { get; set; }
        public int BelumMulaiCount { get; set; }
        public int TransitCount { get; set; }
        public int DikerjakanCount { get; set; }
        public int SelesaiCount { get; set; }
    }

    public async Task<BundleWipPagedResult> GetWipAsync(BundleWipPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var projectIdParam = new SqlParameter("@ProjectId", (object?)request.ProjectId ?? DBNull.Value);
        var articleIdParam = new SqlParameter("@ArticleId", (object?)request.ArticleId ?? DBNull.Value);
        var divisionIdParam = new SqlParameter("@DivisionId", (object?)request.DivisionId ?? DBNull.Value);
        var statusParam = new SqlParameter("@Status", (object?)request.Status ?? DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", (object?)request.SortColumn ?? DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<BundleWipDto>(
                "EXEC SIS_Report_BundleWip @Action = @Action, @ProjectId = @ProjectId, @ArticleId = @ArticleId, @DivisionId = @DivisionId, @Status = @Status, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, projectIdParam, articleIdParam, divisionIdParam, statusParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countProjectIdParam = new SqlParameter("@ProjectId", (object?)request.ProjectId ?? DBNull.Value);
        var countArticleIdParam = new SqlParameter("@ArticleId", (object?)request.ArticleId ?? DBNull.Value);
        var countDivisionIdParam = new SqlParameter("@DivisionId", (object?)request.DivisionId ?? DBNull.Value);
        var countStatusParam = new SqlParameter("@Status", (object?)request.Status ?? DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<BundleWipCountRow>(
                "EXEC SIS_Report_BundleWip @Action = @Action, @ProjectId = @ProjectId, @ArticleId = @ArticleId, @DivisionId = @DivisionId, @Status = @Status",
                countActionParam, countProjectIdParam, countArticleIdParam, countDivisionIdParam, countStatusParam)
            .ToListAsync();

        var counts = countResult.FirstOrDefault() ?? new BundleWipCountRow();

        return new BundleWipPagedResult
        {
            Items = items,
            TotalCount = counts.TotalCount,
            PageNumber = request.PageNumber,
            PageSize = request.PageSize,
            BelumMulaiCount = counts.BelumMulaiCount,
            TransitCount = counts.TransitCount,
            DikerjakanCount = counts.DikerjakanCount,
            SelesaiCount = counts.SelesaiCount
        };
    }

    // SIS_Report_ArticleProgress mengembalikan 2 result set (step ber-bundle, step
    // non-bundle) -- EF Core SqlQueryRaw hanya mendukung satu result set, jadi di sini
    // pakai SqlCommand mentah + reader.NextResultAsync() (pola sama dengan
    // BundleService.GetScanInfoAsync).
    public async Task<ArticleProgressResultDto> GetArticleProgressAsync(int projectId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Report_ArticleProgress";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@ProjectId", projectId));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new ArticleProgressResultDto();

            while (await reader.ReadAsync())
            {
                result.BundleSteps.Add(new ArticleProgressBundleStepDto
                {
                    ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    TotalBundle = reader.GetInt32(reader.GetOrdinal("TotalBundle")),
                    BundleSelesai = reader.GetInt32(reader.GetOrdinal("BundleSelesai")),
                    BundleDiterima = reader.GetInt32(reader.GetOrdinal("BundleDiterima")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyReject = reader.GetInt32(reader.GetOrdinal("QtyReject")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.NonBundleSteps.Add(new ArticleProgressNonBundleStepDto
                {
                    ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    QtyTarget = reader.GetInt32(reader.GetOrdinal("QtyTarget")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyReject = reader.GetInt32(reader.GetOrdinal("QtyReject")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.SizeSurplus.Add(new ArticleProgressSizeSurplusDto
                {
                    ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    QtyTarget = reader.GetInt32(reader.GetOrdinal("QtyTarget")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    Surplus = reader.GetInt32(reader.GetOrdinal("Surplus")),
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // SIS_Report_ArticleSizeProgress mengembalikan 3 result set (ukuran, step, sel matriks)
    // -- pola raw SqlCommand yang sama dengan GetArticleProgressAsync di atas.
    public async Task<ArticleSizeProgressResultDto> GetArticleSizeProgressAsync(int articleId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Report_ArticleSizeProgress";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@ArticleId", articleId));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new ArticleSizeProgressResultDto();

            while (await reader.ReadAsync())
            {
                result.Sizes.Add(new ArticleSizeProgressSizeDto
                {
                    SizeId = reader.GetInt32(reader.GetOrdinal("SizeId")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                    PoQty = reader.GetInt32(reader.GetOrdinal("PoQty")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Steps.Add(new ArticleSizeProgressStepDto
                {
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Cells.Add(new ArticleSizeProgressCellDto
                {
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    SizeId = reader.GetInt32(reader.GetOrdinal("SizeId")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<List<BundleVarianceDto>> GetVarianceAsync(int? projectId, int? articleId)
    {
        var projectIdParam = new SqlParameter("@ProjectId", (object?)projectId ?? DBNull.Value);
        var articleIdParam = new SqlParameter("@ArticleId", (object?)articleId ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<BundleVarianceDto>(
                "EXEC SIS_Report_BundleVariance @ProjectId = @ProjectId, @ArticleId = @ArticleId",
                projectIdParam, articleIdParam)
            .ToListAsync();
    }

    // SIS_Report_BundleHistory mengembalikan 2 result set (header, timeline). RAISERROR di
    // SP (bundle tidak ditemukan / parameter kurang) muncul sebagai SqlException di sini --
    // ditangkap dan dikembalikan sebagai error, bukan exception mentah ke controller.
    public async Task<(bool Success, string Error, BundleHistoryResultDto Result)> GetBundleHistoryAsync(string? serial, int? projectId, int? bundleNo)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Report_BundleHistory";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@Serial", (object?)serial ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@ProjectId", (object?)projectId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@BundleNo", (object?)bundleNo ?? DBNull.Value));

            using var reader = await cmd.ExecuteReaderAsync();

            var history = new BundleHistoryResultDto();

            if (await reader.ReadAsync())
            {
                history.Header = new BundleHistoryHeaderDto
                {
                    BundleId = reader.GetInt32(reader.GetOrdinal("BundleId")),
                    Serial = reader.GetString(reader.GetOrdinal("Serial")),
                    BundleNo = reader.GetInt32(reader.GetOrdinal("BundleNo")),
                    BundleLetter = reader.IsDBNull(reader.GetOrdinal("BundleLetter")) ? null : reader.GetString(reader.GetOrdinal("BundleLetter")),
                    ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                    TailorName = reader.IsDBNull(reader.GetOrdinal("TailorName")) ? null : reader.GetString(reader.GetOrdinal("TailorName")),
                    Status = reader.GetString(reader.GetOrdinal("Status")),
                    PosisiDivisionName = reader.IsDBNull(reader.GetOrdinal("PosisiDivisionName")) ? null : reader.GetString(reader.GetOrdinal("PosisiDivisionName")),
                    StepName = reader.IsDBNull(reader.GetOrdinal("StepName")) ? null : reader.GetString(reader.GetOrdinal("StepName")),
                    EmployeeName = reader.IsDBNull(reader.GetOrdinal("EmployeeName")) ? null : reader.GetString(reader.GetOrdinal("EmployeeName")),
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                history.Timeline.Add(new BundleHistoryTimelineDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    DivisionName = reader.IsDBNull(reader.GetOrdinal("DivisionName")) ? null : reader.GetString(reader.GetOrdinal("DivisionName")),
                    TargetDivisionName = reader.IsDBNull(reader.GetOrdinal("TargetDivisionName")) ? null : reader.GetString(reader.GetOrdinal("TargetDivisionName")),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyReject = reader.GetInt32(reader.GetOrdinal("QtyReject")),
                    Remark = reader.IsDBNull(reader.GetOrdinal("Remark")) ? null : reader.GetString(reader.GetOrdinal("Remark")),
                    PelaksanaName = reader.IsDBNull(reader.GetOrdinal("PelaksanaName")) ? null : reader.GetString(reader.GetOrdinal("PelaksanaName")),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    CreatedByName = reader.IsDBNull(reader.GetOrdinal("CreatedByName")) ? null : reader.GetString(reader.GetOrdinal("CreatedByName")),
                    ReceivedAt = reader.IsDBNull(reader.GetOrdinal("ReceivedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("ReceivedAt")),
                    ReceivedByResourceName = reader.IsDBNull(reader.GetOrdinal("ReceivedByResourceName")) ? null : reader.GetString(reader.GetOrdinal("ReceivedByResourceName")),
                    ReceivedRemark = reader.IsDBNull(reader.GetOrdinal("ReceivedRemark")) ? null : reader.GetString(reader.GetOrdinal("ReceivedRemark")),
                });
            }

            if (history.Header is null) return (false, "Bundle tidak ditemukan.", history);
            return (true, string.Empty, history);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, new BundleHistoryResultDto());
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }
}

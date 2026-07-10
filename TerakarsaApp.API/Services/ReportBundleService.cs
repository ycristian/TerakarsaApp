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

    public async Task<List<BundleWipDto>> GetWipAsync(int? projectId, int? articleId, int? divisionId, string? status)
    {
        var projectIdParam = new SqlParameter("@ProjectId", (object?)projectId ?? DBNull.Value);
        var articleIdParam = new SqlParameter("@ArticleId", (object?)articleId ?? DBNull.Value);
        var divisionIdParam = new SqlParameter("@DivisionId", (object?)divisionId ?? DBNull.Value);
        var statusParam = new SqlParameter("@Status", (object?)status ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<BundleWipDto>(
                "EXEC SIS_Report_BundleWip @ProjectId = @ProjectId, @ArticleId = @ArticleId, @DivisionId = @DivisionId, @Status = @Status",
                projectIdParam, articleIdParam, divisionIdParam, statusParam)
            .ToListAsync();
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
                    ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                    TailorName = reader.IsDBNull(reader.GetOrdinal("TailorName")) ? null : reader.GetString(reader.GetOrdinal("TailorName")),
                    Status = reader.GetString(reader.GetOrdinal("Status")),
                    PosisiDivisionName = reader.IsDBNull(reader.GetOrdinal("PosisiDivisionName")) ? null : reader.GetString(reader.GetOrdinal("PosisiDivisionName")),
                    StepName = reader.IsDBNull(reader.GetOrdinal("StepName")) ? null : reader.GetString(reader.GetOrdinal("StepName")),
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                history.Timeline.Add(new BundleHistoryTimelineDto
                {
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

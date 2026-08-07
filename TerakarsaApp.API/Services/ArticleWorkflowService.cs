using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Services;

public class ArticleWorkflowService
{
    private readonly AppDbContext _db;

    public ArticleWorkflowService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ArticleWorkflowDto> GetByArticleAsync(int articleId)
    {
        var articleIdParam = new SqlParameter("@ArticleId", articleId);

        var rows = await _db.Database
            .SqlQueryRaw<ArticleWorkflowStepDto>("EXEC SIS_ArticleWorkflow_ListByArticle @ArticleId = @ArticleId", articleIdParam)
            .ToListAsync();

        var origin = rows.FirstOrDefault(r => r.WorkflowTemplateId.HasValue);

        return new ArticleWorkflowDto
        {
            ArticleId = articleId,
            WorkflowTemplateId = origin?.WorkflowTemplateId,
            WorkflowTemplateName = origin?.WorkflowTemplateName,
            Steps = rows
        };
    }

    public async Task<(bool Success, string Error)> ApplyAsync(ArticleWorkflowApplyRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "APPLY");
        var articleIdParam = new SqlParameter("@ArticleId", request.ArticleId);
        var templateIdParam = new SqlParameter("@WorkflowTemplateId", request.WorkflowTemplateId);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_ArticleWorkflow_Manage @Action = @Action, @ArticleId = @ArticleId, @WorkflowTemplateId = @WorkflowTemplateId, @UserId = @UserId",
                actionParam, articleIdParam, templateIdParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> SaveAsync(ArticleWorkflowSaveRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "SAVE");
        var articleIdParam = new SqlParameter("@ArticleId", request.ArticleId);
        var stepsParam = new SqlParameter("@Steps", JsonSerializer.Serialize(request.Steps));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_ArticleWorkflow_Manage @Action = @Action, @ArticleId = @ArticleId, @Steps = @Steps, @UserId = @UserId",
                actionParam, articleIdParam, stepsParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Prompt 50: SIS_ArticleWorkflow_Restructure -- PREVIEW_INSERT/PREVIEW_DEACTIVATE
    // mengembalikan 2 result set (ringkasan + daftar unit terdampak), jadi EF Core
    // SqlQueryRaw (satu result set) tidak cukup -- pola sama dengan
    // ReportBundleService.GetArticleProgressAsync (SqlCommand mentah + reader.NextResultAsync).
    public async Task<(RestructurePreviewResultDto? Result, string? Error)> PreviewInsertAsync(RestructureInsertPreviewRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "PREVIEW_INSERT"),
            new SqlParameter("@ArticleId", request.ArticleId),
            new SqlParameter("@StepName", request.StepName),
            new SqlParameter("@DivisionId", request.DivisionId),
            new SqlParameter("@RequiresBundle", request.RequiresBundle),
            new SqlParameter("@AutoReceive", request.AutoReceive),
            new SqlParameter("@AfterWorkflowId", (object?)request.AfterWorkflowId ?? DBNull.Value),
            new SqlParameter("@Backfill", request.Backfill),
            new SqlParameter("@UserId", userId)
        };

        return await ExecutePreviewAsync(parameters);
    }

    public async Task<(RestructurePreviewResultDto? Result, string? Error)> PreviewDeactivateAsync(RestructureDeactivatePreviewRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "PREVIEW_DEACTIVATE"),
            new SqlParameter("@ArticleId", request.ArticleId),
            new SqlParameter("@ArticleWorkflowId", request.ArticleWorkflowId),
            new SqlParameter("@UserId", userId)
        };

        return await ExecutePreviewAsync(parameters);
    }

    private async Task<(RestructurePreviewResultDto? Result, string? Error)> ExecutePreviewAsync(SqlParameter[] parameters)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_ArticleWorkflow_Restructure";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.AddRange(parameters);

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new RestructurePreviewResultDto();

            if (await reader.ReadAsync())
            {
                result.Summary = new RestructurePreviewSummaryDto
                {
                    PendingLogsToRedirect = reader.GetInt32(reader.GetOrdinal("PendingLogsToRedirect")),
                    ReceivedLogsToRedirect = reader.GetInt32(reader.GetOrdinal("ReceivedLogsToRedirect")),
                    BackfillLogsToCreate = reader.GetInt32(reader.GetOrdinal("BackfillLogsToCreate")),
                    ForcedBackfillCount = reader.GetInt32(reader.GetOrdinal("ForcedBackfillCount")),
                    StepsResequenced = reader.GetInt32(reader.GetOrdinal("StepsResequenced")),
                    WarningMessage = reader.IsDBNull(reader.GetOrdinal("WarningMessage")) ? null : reader.GetString(reader.GetOrdinal("WarningMessage"))
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.AffectedUnits.Add(new RestructureAffectedUnitDto
                {
                    BundleId = reader.IsDBNull(reader.GetOrdinal("BundleId")) ? null : reader.GetInt32(reader.GetOrdinal("BundleId")),
                    Serial = reader.IsDBNull(reader.GetOrdinal("Serial")) ? null : reader.GetString(reader.GetOrdinal("Serial")),
                    BundleNo = reader.IsDBNull(reader.GetOrdinal("BundleNo")) ? null : reader.GetInt32(reader.GetOrdinal("BundleNo")),
                    ArticleSizeId = reader.IsDBNull(reader.GetOrdinal("ArticleSizeId")) ? null : reader.GetInt32(reader.GetOrdinal("ArticleSizeId")),
                    SizeName = reader.IsDBNull(reader.GetOrdinal("SizeName")) ? null : reader.GetString(reader.GetOrdinal("SizeName")),
                    Category = reader.GetString(reader.GetOrdinal("Category")),
                    LastStepName = reader.GetString(reader.GetOrdinal("LastStepName"))
                });
            }

            return (result, null);
        }
        catch (SqlException ex)
        {
            return (null, ex.Message);
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<(RestructureInsertStepResultDto? Result, string? Error)> InsertStepAsync(RestructureInsertPreviewRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "INSERT_STEP");
        var articleIdParam = new SqlParameter("@ArticleId", request.ArticleId);
        var stepNameParam = new SqlParameter("@StepName", request.StepName);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var requiresBundleParam = new SqlParameter("@RequiresBundle", request.RequiresBundle);
        var autoReceiveParam = new SqlParameter("@AutoReceive", request.AutoReceive);
        var afterWorkflowIdParam = new SqlParameter("@AfterWorkflowId", (object?)request.AfterWorkflowId ?? DBNull.Value);
        var backfillParam = new SqlParameter("@Backfill", request.Backfill);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<RestructureInsertStepResultDto>(
                    "EXEC SIS_ArticleWorkflow_Restructure @Action = @Action, @ArticleId = @ArticleId, @StepName = @StepName, @DivisionId = @DivisionId, @RequiresBundle = @RequiresBundle, @AutoReceive = @AutoReceive, @AfterWorkflowId = @AfterWorkflowId, @Backfill = @Backfill, @UserId = @UserId",
                    actionParam, articleIdParam, stepNameParam, divisionIdParam, requiresBundleParam, autoReceiveParam, afterWorkflowIdParam, backfillParam, userIdParam)
                .ToListAsync();

            return (rows.FirstOrDefault(), null);
        }
        catch (SqlException ex)
        {
            return (null, ex.Message);
        }
    }

    public async Task<(RestructureDeactivateStepResultDto? Result, string? Error)> DeactivateStepAsync(RestructureDeactivatePreviewRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DEACTIVATE_STEP");
        var articleIdParam = new SqlParameter("@ArticleId", request.ArticleId);
        var articleWorkflowIdParam = new SqlParameter("@ArticleWorkflowId", request.ArticleWorkflowId);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<RestructureDeactivateStepResultDto>(
                    "EXEC SIS_ArticleWorkflow_Restructure @Action = @Action, @ArticleId = @ArticleId, @ArticleWorkflowId = @ArticleWorkflowId, @UserId = @UserId",
                    actionParam, articleIdParam, articleWorkflowIdParam, userIdParam)
                .ToListAsync();

            return (rows.FirstOrDefault(), null);
        }
        catch (SqlException ex)
        {
            return (null, ex.Message);
        }
    }
}

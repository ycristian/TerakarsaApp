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

    // Prompt 12c: step requires_bundle = 0 milik artikel + divisi tujuan (divisi step hidup
    // berikutnya dalam urutan sort_order, bundle atau non-bundle -- aturan 12b menjamin semua
    // step non-bundle berada sebelum step ber-bundle, jadi "berikutnya" selalu valid untuk
    // prefill tampilan). Dipakai halaman /workflow-input (WorkflowInputController), tidak
    // menyentuh SIS_ArticleWorkflow_ListByArticle -- reuse GetByArticleAsync di atas.
    public async Task<List<ArticleNonBundleStepDto>> GetNonBundleStepsAsync(int articleId)
    {
        var full = await GetByArticleAsync(articleId);
        var steps = full.Steps.OrderBy(s => s.SortOrder).ToList();
        var result = new List<ArticleNonBundleStepDto>();

        for (var i = 0; i < steps.Count; i++)
        {
            var step = steps[i];
            if (step.RequiresBundle) continue;

            var next = i + 1 < steps.Count ? steps[i + 1] : null;
            result.Add(new ArticleNonBundleStepDto
            {
                ArticleWorkflowId = step.Id,
                StepName = step.StepName,
                SortOrder = step.SortOrder,
                DivisionId = step.DivisionId,
                DivisionName = step.DivisionName,
                IsLastStep = next is null,
                NextDivisionId = next?.DivisionId,
                NextDivisionName = next?.DivisionName
            });
        }

        return result;
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
}

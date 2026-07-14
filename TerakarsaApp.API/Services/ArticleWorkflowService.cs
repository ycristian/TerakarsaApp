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
}

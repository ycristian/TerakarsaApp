using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/article-workflows")]
[Authorize]
[RequireModule("ORDER_PROJECT")]
public class ArticleWorkflowController : ControllerBase
{
    private readonly ArticleWorkflowService _articleWorkflowService;

    public ArticleWorkflowController(ArticleWorkflowService articleWorkflowService)
    {
        _articleWorkflowService = articleWorkflowService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("by-article/{articleId}")]
    public async Task<IActionResult> GetByArticle(int articleId)
    {
        var result = await _articleWorkflowService.GetByArticleAsync(articleId);
        return Ok(result);
    }

    [HttpPost("apply")]
    public async Task<IActionResult> Apply([FromBody] ArticleWorkflowApplyRequest request)
    {
        if (request.WorkflowTemplateId <= 0)
            return BadRequest("Template workflow wajib dipilih.");

        var (success, error) = await _articleWorkflowService.ApplyAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("save")]
    public async Task<IActionResult> Save([FromBody] ArticleWorkflowSaveRequest request)
    {
        if (request.Steps.Any(s => string.IsNullOrWhiteSpace(s.StepName) || s.DivisionId <= 0))
            return BadRequest("Nama step dan divisi wajib diisi untuk setiap baris.");

        var (success, error) = await _articleWorkflowService.SaveAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

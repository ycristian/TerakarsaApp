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

    // Prompt 50: restrukturisasi workflow setelah sudah ada log -- lihat
    // sql/sp_ArticleWorkflow_Restructure.sql.
    [HttpPost("{articleId}/restructure/preview-insert")]
    public async Task<IActionResult> PreviewInsertStep(int articleId, [FromBody] RestructureInsertPreviewRequest request)
    {
        request.ArticleId = articleId;
        if (string.IsNullOrWhiteSpace(request.StepName) || request.DivisionId <= 0)
            return BadRequest("Nama step dan divisi wajib diisi.");

        var (result, error) = await _articleWorkflowService.PreviewInsertAsync(request, CurrentUserId);
        if (error != null) return BadRequest(error);
        return Ok(result);
    }

    [HttpPost("{articleId}/restructure/insert-step")]
    public async Task<IActionResult> InsertStep(int articleId, [FromBody] RestructureInsertPreviewRequest request)
    {
        request.ArticleId = articleId;
        if (string.IsNullOrWhiteSpace(request.StepName) || request.DivisionId <= 0)
            return BadRequest("Nama step dan divisi wajib diisi.");

        var (result, error) = await _articleWorkflowService.InsertStepAsync(request, CurrentUserId);
        if (error != null) return BadRequest(error);
        return Ok(result);
    }

    [HttpPost("{articleId}/restructure/preview-deactivate")]
    public async Task<IActionResult> PreviewDeactivateStep(int articleId, [FromBody] RestructureDeactivatePreviewRequest request)
    {
        request.ArticleId = articleId;
        var (result, error) = await _articleWorkflowService.PreviewDeactivateAsync(request, CurrentUserId);
        if (error != null) return BadRequest(error);
        return Ok(result);
    }

    [HttpPost("{articleId}/restructure/deactivate-step")]
    public async Task<IActionResult> DeactivateStep(int articleId, [FromBody] RestructureDeactivatePreviewRequest request)
    {
        request.ArticleId = articleId;
        var (result, error) = await _articleWorkflowService.DeactivateStepAsync(request, CurrentUserId);
        if (error != null) return BadRequest(error);
        return Ok(result);
    }
}

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/articles")]
[Authorize]
[RequireModule("ORDER_PROJECT")]
public class ArticleController : ControllerBase
{
    private readonly ArticleService _articleService;
    private readonly ReportBundleService _reportBundleService;

    public ArticleController(ArticleService articleService, ReportBundleService reportBundleService)
    {
        _articleService = articleService;
        _reportBundleService = reportBundleService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("by-project/{projectId}")]
    public async Task<IActionResult> GetByProject(int projectId)
    {
        var result = await _articleService.GetByProjectAsync(projectId);
        return Ok(result);
    }

    // Kartu "Laporan Progress" (matriks ukuran x step) di halaman Edit Project -- reuse
    // ReportBundleService (SIS_Report_ArticleSizeProgress) di sini supaya tetap bisa diakses
    // dengan module ORDER_PROJECT saja, tanpa perlu REPORT_BUNDLE (pola sama dengan
    // report-bundle-picker/* di ReportBundleController yang reuse ArticleService).
    [HttpGet("{id}/size-progress")]
    public async Task<IActionResult> GetSizeProgress(int id)
    {
        var result = await _reportBundleService.GetArticleSizeProgressAsync(id);
        return Ok(result);
    }

    [HttpGet("by-project/{projectId}/sizes")]
    public async Task<IActionResult> GetSizesByProject(int projectId)
    {
        var result = await _articleService.GetSizesByProjectAsync(projectId);
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var article = await _articleService.GetByIdAsync(id);
        if (article is null) return NotFound();
        return Ok(article);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] ArticleCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ArticleName))
            return BadRequest("Nama artikel wajib diisi.");

        if (request.SizePackId <= 0)
            return BadRequest("Size pack wajib dipilih.");

        var (success, error, id) = await _articleService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new ArticleCreateResult { Id = id });
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] ArticleUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ArticleName))
            return BadRequest("Nama artikel wajib diisi.");

        if (request.SizePackId <= 0)
            return BadRequest("Size pack wajib dipilih.");

        var (success, error) = await _articleService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _articleService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

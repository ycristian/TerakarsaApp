using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Controllers;

// Prompt 13: Modul Laporan Arus Bundle -- murni read-only (module REPORT_BUNDLE, halaman
// /report-bundle). Endpoint report-bundle-picker/* memakai ulang ProjectService/
// ArticleService/DivisionService langsung (tanpa mengubah controller aslinya), pola sama
// dengan bundle-picker/* di BundleController dan workflow-input/* di WorkflowInputController.
[ApiController]
[Route("api")]
[Authorize]
[RequireModule("REPORT_BUNDLE")]
public class ReportBundleController : ControllerBase
{
    private readonly ReportBundleService _reportBundleService;
    private readonly ProjectService _projectService;
    private readonly ArticleService _articleService;
    private readonly DivisionService _divisionService;

    public ReportBundleController(
        ReportBundleService reportBundleService,
        ProjectService projectService,
        ArticleService articleService,
        DivisionService divisionService)
    {
        _reportBundleService = reportBundleService;
        _projectService = projectService;
        _articleService = articleService;
        _divisionService = divisionService;
    }

    [HttpGet("report-bundle/wip")]
    public async Task<IActionResult> GetWip([FromQuery] int? projectId, [FromQuery] int? articleId, [FromQuery] int? divisionId, [FromQuery] string? status)
    {
        var result = await _reportBundleService.GetWipAsync(projectId, articleId, divisionId, status);
        return Ok(result);
    }

    [HttpGet("report-bundle/progress")]
    public async Task<IActionResult> GetProgress([FromQuery] int projectId)
    {
        if (projectId <= 0) return BadRequest("Project wajib dipilih.");

        var result = await _reportBundleService.GetArticleProgressAsync(projectId);
        return Ok(result);
    }

    [HttpGet("report-bundle/variance")]
    public async Task<IActionResult> GetVariance([FromQuery] int? projectId, [FromQuery] int? articleId)
    {
        var result = await _reportBundleService.GetVarianceAsync(projectId, articleId);
        return Ok(result);
    }

    [HttpGet("report-bundle/history")]
    public async Task<IActionResult> GetHistory([FromQuery] string? serial, [FromQuery] int? projectId, [FromQuery] int? bundleNo)
    {
        if (string.IsNullOrWhiteSpace(serial) && (projectId is null || bundleNo is null))
            return BadRequest("Serial atau (Project + Bundle No) wajib diisi.");

        var (success, error, result) = await _reportBundleService.GetBundleHistoryAsync(
            string.IsNullOrWhiteSpace(serial) ? null : serial.Trim(), projectId, bundleNo);

        if (!success) return BadRequest(error);
        return Ok(result);
    }

    // --- Pemilih filter: Project, Artikel, Divisi ---

    [HttpGet("report-bundle-picker/projects")]
    public async Task<IActionResult> GetProjects()
    {
        var result = await _projectService.GetPagedAsync(new ProjectPagedRequest
        {
            PageNumber = 1,
            PageSize = 500,
            SortColumn = "CreatedAt",
            SortDirection = "desc"
        });
        return Ok(result.Items);
    }

    [HttpGet("report-bundle-picker/projects/{projectId:int}/articles")]
    public async Task<IActionResult> GetArticlesByProject(int projectId)
    {
        var result = await _articleService.GetByProjectAsync(projectId);
        return Ok(result);
    }

    [HttpGet("report-bundle-picker/divisions")]
    public async Task<IActionResult> GetDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }
}

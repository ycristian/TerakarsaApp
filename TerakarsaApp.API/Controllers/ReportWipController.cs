using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Prompt 22: Dashboard WIP per Divisi & Resource -- murni read-only (module REPORT_WIP,
// halaman /wip-dashboard).
[ApiController]
[Route("api")]
[Authorize]
[RequireModule("REPORT_WIP")]
public class ReportWipController : ControllerBase
{
    private readonly ReportWipService _reportWipService;

    public ReportWipController(ReportWipService reportWipService)
    {
        _reportWipService = reportWipService;
    }

    [HttpGet("report-wip/summary")]
    public async Task<IActionResult> GetSummary([FromQuery] int? projectId)
    {
        var result = await _reportWipService.GetSummaryAsync(projectId);
        return Ok(result);
    }

    [HttpGet("report-wip/bundles")]
    public async Task<IActionResult> GetBundles([FromQuery] int divisionId, [FromQuery] string mode, [FromQuery] int? resourceId, [FromQuery] bool filterResource = false, [FromQuery] int? projectId = null)
    {
        if (divisionId <= 0) return BadRequest("Divisi wajib diisi.");
        if (string.IsNullOrWhiteSpace(mode)) return BadRequest("Mode wajib diisi.");

        var (success, error, result) = await _reportWipService.GetBundlesAsync(divisionId, mode.Trim(), resourceId, filterResource, projectId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    [HttpGet("report-wip/projects")]
    public async Task<IActionResult> GetRunningProjects()
    {
        var result = await _reportWipService.GetRunningProjectsAsync();
        return Ok(result);
    }
}

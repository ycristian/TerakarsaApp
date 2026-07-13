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
    public async Task<IActionResult> GetSummary()
    {
        var result = await _reportWipService.GetSummaryAsync();
        return Ok(result);
    }

    [HttpGet("report-wip/bundles")]
    public async Task<IActionResult> GetBundles([FromQuery] int divisionId, [FromQuery] string mode, [FromQuery] int? resourceId, [FromQuery] bool filterResource = false)
    {
        if (divisionId <= 0) return BadRequest("Divisi wajib diisi.");
        if (string.IsNullOrWhiteSpace(mode)) return BadRequest("Mode wajib diisi.");

        var (success, error, result) = await _reportWipService.GetBundlesAsync(divisionId, mode.Trim(), resourceId, filterResource);
        if (!success) return BadRequest(error);
        return Ok(result);
    }
}

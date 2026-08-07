using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.API.Controllers;

// Endpoint untuk TerakarsaApp.PrintService (Windows Worker Service di PC printer).
// TIDAK memakai [Authorize] JWT -- autentikasi murni lewat header X-Print-Api-Key,
// divalidasi oleh RequirePrintApiKeyAttribute terhadap PrintService:ApiKey.
[ApiController]
[Route("api/print")]
[RequirePrintApiKey]
public class PrintController : ControllerBase
{
    private readonly PrintJobService _printJobService;

    public PrintController(PrintJobService printJobService)
    {
        _printJobService = printJobService;
    }

    [HttpPost("claim")]
    public async Task<IActionResult> Claim([FromBody] PrintJobClaimRequest request)
    {
        var batchSize = request.BatchSize <= 0 ? 5 : request.BatchSize;
        var result = await _printJobService.ClaimAsync(batchSize, request.JobTypes, request.DryRun);
        return Ok(result);
    }

    [HttpPost("report")]
    public async Task<IActionResult> Report([FromBody] PrintJobReportRequest request)
    {
        await _printJobService.ReportAsync(request);
        return Ok();
    }

    // Prompt 48: render isi cetakan (job_type render_mode = TOKEN) -- dipanggil worker
    // SETELAH klaim, sebelum diterjemahkan ke byte ESC/POS lewat EscPosRenderer. dryRun (ad
    // hoc lanjutan Prompt 48) harus sama dengan flag yang dipakai saat klaim job ini --
    // menentukan apakah SIS_Print_Dispatch baca dari print_jobs_dryrun atau print_jobs.
    [HttpGet("render/{printJobId:int}")]
    public async Task<IActionResult> Render(int printJobId, [FromQuery] bool dryRun = false)
    {
        var (success, error, tokenText) = await _printJobService.RenderAsync(printJobId, dryRun);
        if (!success) return BadRequest(error);
        return Ok(new { tokenText });
    }
}

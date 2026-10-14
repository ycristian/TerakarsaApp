using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.API.Controllers;

// Endpoint untuk pencetak: TerakarsaApp.PrintService (Windows Worker Service di PC
// printer) DAN app Android (printer Bluetooth, Prompt 77).
// TIDAK memakai [Authorize] JWT -- autentikasi lewat header X-Print-Api-Key (service PC)
// atau X-Print-Device-Token (satu HP), divalidasi RequirePrintAuthAttribute.
// Pengelolaan device & routing ada di PrintAdminController (pakai JWT).
[ApiController]
[Route("api/print")]
[RequirePrintAuth]
public class PrintController : ControllerBase
{
    private readonly PrintJobService _printJobService;

    public PrintController(PrintJobService printJobService)
    {
        _printJobService = printJobService;
    }

    // Ad hoc (2026-09-01): daftar job_type "kupon" (thermal) yang boleh diklaim, dibaca dari
    // tabel print_kupon_job_types -- dipanggil worker SETIAP siklus poll (bukan cache startup)
    // supaya job_type struk baru langsung kepakai tanpa restart PrintService.
    [HttpGet("kupon-job-types")]
    public async Task<IActionResult> GetKuponJobTypes()
    {
        var result = await _printJobService.GetKuponJobTypesAsync();
        return Ok(result);
    }

    [HttpPost("claim")]
    public async Task<IActionResult> Claim([FromBody] PrintJobClaimRequest request)
    {
        var batchSize = request.BatchSize <= 0 ? 5 : request.BatchSize;
        var result = await _printJobService.ClaimAsync(batchSize, request.JobTypes, request.DryRun, this.PrintDeviceId());
        return Ok(result);
    }

    [HttpPost("report")]
    public async Task<IActionResult> Report([FromBody] PrintJobReportRequest request)
    {
        var (success, error) = await _printJobService.ReportAsync(request, this.PrintDeviceId());
        if (!success) return BadRequest(error);
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

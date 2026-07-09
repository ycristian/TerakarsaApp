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
        var result = await _printJobService.ClaimAsync(batchSize);
        return Ok(result);
    }

    [HttpPost("report")]
    public async Task<IActionResult> Report([FromBody] PrintJobReportRequest request)
    {
        await _printJobService.ReportAsync(request);
        return Ok();
    }
}

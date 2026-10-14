using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.API.Controllers;

// Prompt 74: stock opname benang. Dipisah dari ThreadStockController supaya controller
// master/movement tidak jadi tempat semuanya.
//
// TIDAK ADA endpoint penyesuaian stok manual: ADJUST hanya lahir dari CLOSE sesi
// opname (ditegakkan juga di inv.SIS_ThreadMovement_Manage).
[ApiController]
[Route("api/gudang/benang/opname")]
[Authorize]
[RequireModule("INV_THREAD")]
public class ThreadOpnameController : ControllerBase
{
    private readonly ThreadOpnameService _opnameService;

    public ThreadOpnameController(ThreadOpnameService opnameService)
    {
        _opnameService = opnameService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    // Sesi OPEN (kalau ada) + progres per rak.
    [HttpGet("current")]
    public async Task<IActionResult> Current() => Ok(await _opnameService.GetCurrentAsync());

    [HttpGet("{sessionId:int}/lines")]
    public async Task<IActionResult> Lines(int sessionId, [FromQuery] int? locationId = null)
        => Ok(await _opnameService.GetLinesAsync(sessionId, locationId));

    [HttpGet("{sessionId:int}/preview-close")]
    public async Task<IActionResult> PreviewClose(int sessionId)
        => Ok(await _opnameService.PreviewCloseAsync(sessionId));

    [HttpGet("{sessionId:int}")]
    public async Task<IActionResult> GetById(int sessionId)
    {
        var detail = await _opnameService.GetByIdAsync(sessionId);
        if (detail is null) return NotFound();
        return Ok(detail);
    }

    [HttpGet("riwayat")]
    public async Task<IActionResult> Riwayat([FromQuery] int top = 50)
        => Ok(await _opnameService.GetListAsync(top));

    [HttpGet("reason-codes")]
    public async Task<IActionResult> ReasonCodes() => Ok(await _opnameService.GetReasonCodesAsync());

    [HttpPost("open")]
    public Task<IActionResult> Open([FromBody] ThreadOpnameOpenRequest request)
        => Hasil(_opnameService.OpenAsync(request, CurrentUserId));

    [HttpPost("add-line")]
    public Task<IActionResult> AddLine([FromBody] ThreadOpnameAddLineRequest request)
        => Hasil(_opnameService.AddLineAsync(request, CurrentUserId));

    [HttpPost("count")]
    public Task<IActionResult> Count([FromBody] ThreadOpnameCountRequest request)
        => Hasil(_opnameService.CountAsync(request, CurrentUserId));

    [HttpPost("{sessionId:int}/location/{locationId:int}/done")]
    public Task<IActionResult> LocationDone(int sessionId, int locationId)
        => Hasil(_opnameService.LocationDoneAsync(sessionId, locationId, CurrentUserId));

    [HttpPost("close")]
    public Task<IActionResult> Close([FromBody] ThreadOpnameCloseRequest request)
        => Hasil(_opnameService.CloseAsync(request, CurrentUserId));

    [HttpPost("{sessionId:int}/cancel")]
    public Task<IActionResult> Cancel(int sessionId)
        => Hasil(_opnameService.CancelAsync(sessionId, CurrentUserId));

    private static async Task<IActionResult> Hasil(Task<(bool Success, string Error, int Id)> task)
    {
        var (success, error, id) = await task;
        if (!success) return new BadRequestObjectResult(error);
        return new OkObjectResult(id);
    }
}

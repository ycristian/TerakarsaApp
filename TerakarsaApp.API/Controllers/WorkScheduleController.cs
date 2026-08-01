using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.WorkSchedules;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/work-schedule")]
[Authorize]
[RequireModule("SETTING_JAM_KERJA")]
public class WorkScheduleController : ControllerBase
{
    private readonly WorkScheduleService _workScheduleService;

    public WorkScheduleController(WorkScheduleService workScheduleService)
    {
        _workScheduleService = workScheduleService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("defaults")]
    public async Task<IActionResult> GetDefaults()
    {
        var result = await _workScheduleService.GetDefaultsAsync();
        return Ok(result);
    }

    [HttpPut("defaults/{divisionId}")]
    public async Task<IActionResult> SaveDivisionSchedule(int divisionId, [FromBody] SaveDivisionScheduleRequest request)
    {
        if (request.Days.Count != 7)
            return BadRequest("Jam kerja harus lengkap untuk 7 hari (Senin s.d. Minggu).");

        request.DivisionId = divisionId;
        var (success, error) = await _workScheduleService.SaveDivisionScheduleAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpGet("breaks")]
    public async Task<IActionResult> GetBreaks()
    {
        var result = await _workScheduleService.GetBreaksAsync();
        return Ok(result);
    }

    [HttpPost("breaks")]
    public async Task<IActionResult> CreateBreak([FromBody] WorkBreakCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.BreakName))
            return BadRequest("Nama istirahat wajib diisi.");

        var (success, error) = await _workScheduleService.CreateBreakAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut("breaks")]
    public async Task<IActionResult> UpdateBreak([FromBody] WorkBreakUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.BreakName))
            return BadRequest("Nama istirahat wajib diisi.");

        var (success, error) = await _workScheduleService.UpdateBreakAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("breaks/{id}")]
    public async Task<IActionResult> DeleteBreak(int id)
    {
        await _workScheduleService.DeleteBreakAsync(id, CurrentUserId);
        return Ok();
    }
}

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.DailyPlans;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/daily-plan")]
[Authorize]
[RequireModule("PPIC_PLANNING")]
public class DailyPlanController : ControllerBase
{
    private readonly DailyPlanService _dailyPlanService;

    public DailyPlanController(DailyPlanService dailyPlanService)
    {
        _dailyPlanService = dailyPlanService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<IActionResult> GetByDate([FromQuery] DateTime date)
    {
        var result = await _dailyPlanService.GetByDateAsync(date);
        return Ok(result);
    }

    [HttpPut("{divisionId}")]
    public async Task<IActionResult> Save(int divisionId, [FromQuery] DateTime date, [FromBody] SaveDailyPlanRequest request)
    {
        request.PlanDate = date;
        var (success, error, planId) = await _dailyPlanService.SaveAsync(divisionId, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { id = planId });
    }

    [HttpDelete("{divisionId}")]
    public async Task<IActionResult> Delete(int divisionId, [FromQuery] DateTime date)
    {
        await _dailyPlanService.DeleteAsync(date, divisionId, CurrentUserId);
        return Ok();
    }

    [HttpPost("copy")]
    public async Task<IActionResult> Copy([FromBody] CopyDailyPlanRequest request)
    {
        var (success, error, copiedCount) = await _dailyPlanService.CopyAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new CopyDailyPlanResult { CopiedCount = copiedCount });
    }

    [HttpGet("dates")]
    public async Task<IActionResult> GetDates([FromQuery] DateTime from, [FromQuery] DateTime to)
    {
        var result = await _dailyPlanService.GetDatesAsync(from, to);
        return Ok(result);
    }
}

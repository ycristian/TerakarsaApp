using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Dashboards;

namespace TerakarsaApp.API.Controllers;

// Endpoint untuk kiosk TV (layar publik di lantai produksi, tanpa login).
// TIDAK memakai [Authorize] JWT -- autentikasi murni lewat header X-Dashboard-Token,
// divalidasi oleh RequireDashboardTokenAttribute terhadap SIS_DashboardToken_GetByToken.
// Read-only: tidak ada endpoint mutasi di sini sama sekali.
[ApiController]
[Route("api/dashboard")]
[RequireDashboardToken]
public class DashboardController : ControllerBase
{
    private readonly DashboardService _dashboardService;

    public DashboardController(DashboardService dashboardService)
    {
        _dashboardService = dashboardService;
    }

    [HttpGet("target-harian")]
    public async Task<IActionResult> GetTargetHarian([FromQuery] DateTime? date)
    {
        var planDate = date ?? DateTime.Today;
        var result = await _dashboardService.GetTargetHarianAsync(planDate);
        return Ok(result);
    }

    [HttpGet("me")]
    public IActionResult GetMe()
    {
        var auth = HttpContext.Items[RequireDashboardTokenAttribute.HttpContextItemKey] as DashboardTokenAuthDto;
        if (auth is null) return Unauthorized();

        return Ok(new DashboardMeDto
        {
            TokenName = auth.TokenName,
            RefreshIntervalMinutes = auth.RefreshIntervalMinutes
        });
    }
}

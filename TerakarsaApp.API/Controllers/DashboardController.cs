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

    // Prompt 45/46: modal drill-down per line, privilege sama persis dengan target-harian di
    // atas ([RequireDashboardToken] di level class) -- tidak ada modul JWT terpisah untuk halaman ini.
    // Prompt 51: resourceId opsional -- kosong berarti mode divisi (agregat seluruh resource).
    [HttpGet("line-detail/employees")]
    public async Task<IActionResult> GetLineDetailEmployees([FromQuery] int divisionId, [FromQuery] int? resourceId, [FromQuery] DateTime tanggal)
    {
        var result = await _dashboardService.GetLineEmployeeProgressAsync(divisionId, resourceId, tanggal.Date);
        return Ok(result);
    }

    [HttpGet("line-detail/bundles")]
    public async Task<IActionResult> GetLineDetailBundles([FromQuery] int divisionId, [FromQuery] int? resourceId)
    {
        var result = await _dashboardService.GetLineActiveBundlesAsync(divisionId, resourceId);
        return Ok(result);
    }

    // Prompt 52: tab "Transit".
    [HttpGet("line-detail/transit")]
    public async Task<IActionResult> GetLineDetailTransit([FromQuery] int divisionId, [FromQuery] int? resourceId)
    {
        var result = await _dashboardService.GetLineTransitBundlesAsync(divisionId, resourceId);
        return Ok(result);
    }

    // Prompt 46: tab "Selesai" & "Reject" -- @periode = "hari" (default) / "7hari" / "gajian",
    // dikonversi ke rentang tanggal di DashboardService (satu sumber definisi periode gajian).
    [HttpGet("line-detail/completed")]
    public async Task<IActionResult> GetLineDetailCompleted([FromQuery] int divisionId, [FromQuery] int? resourceId, [FromQuery] string? periode, [FromQuery] DateTime tanggal)
    {
        var result = await _dashboardService.GetLineCompletedBundlesAsync(divisionId, resourceId, periode, tanggal.Date);
        return Ok(result);
    }

    [HttpGet("line-detail/rejects")]
    public async Task<IActionResult> GetLineDetailRejects([FromQuery] int divisionId, [FromQuery] int? resourceId, [FromQuery] string? periode, [FromQuery] DateTime tanggal)
    {
        var result = await _dashboardService.GetLineRejectBundlesAsync(divisionId, resourceId, periode, tanggal.Date);
        return Ok(result);
    }

    // Prompt 51: tab "Tren" -- @rentang = "14hari" (default) / "30hari" utk grafik harian; tabel
    // rekap mingguan (10 periode gajian terakhir) tidak punya parameter rentang sendiri.
    [HttpGet("line-detail/trend-daily")]
    public async Task<IActionResult> GetLineDetailTrendDaily([FromQuery] int divisionId, [FromQuery] int? resourceId, [FromQuery] string? rentang, [FromQuery] DateTime tanggal)
    {
        var result = await _dashboardService.GetLineTrendDailyAsync(divisionId, resourceId, rentang, tanggal.Date);
        return Ok(result);
    }

    [HttpGet("line-detail/trend-weekly")]
    public async Task<IActionResult> GetLineDetailTrendWeekly([FromQuery] int divisionId, [FromQuery] int? resourceId, [FromQuery] DateTime tanggal)
    {
        var result = await _dashboardService.GetLineTrendWeeklyAsync(divisionId, resourceId, tanggal.Date);
        return Ok(result);
    }

    // Prompt 51: tab "Per Jam" -- grafik output per jam pada tanggal aktif dashboard.
    [HttpGet("line-detail/hourly")]
    public async Task<IActionResult> GetLineDetailHourly([FromQuery] int divisionId, [FromQuery] int? resourceId, [FromQuery] DateTime tanggal)
    {
        var result = await _dashboardService.GetLineHourlyAsync(divisionId, resourceId, tanggal.Date);
        return Ok(result);
    }
}

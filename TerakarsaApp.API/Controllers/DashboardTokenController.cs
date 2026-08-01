using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Dashboards;

namespace TerakarsaApp.API.Controllers;

// Admin-only CRUD token dashboard TV, pakai JWT biasa. Endpoint kiosk (autentikasi via
// X-Dashboard-Token) ada di DashboardController.
[ApiController]
[Route("api/dashboard-tokens")]
[Authorize]
[RequireModule("DASHBOARD_TARGET")]
public class DashboardTokenController : ControllerBase
{
    private readonly DashboardTokenService _dashboardTokenService;

    public DashboardTokenController(DashboardTokenService dashboardTokenService)
    {
        _dashboardTokenService = dashboardTokenService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] DashboardTokenPagedRequest request)
    {
        var result = await _dashboardTokenService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] DashboardTokenCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.TokenName))
            return BadRequest("Nama TV wajib diisi.");

        var (success, error, result) = await _dashboardTokenService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] DashboardTokenUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.TokenName))
            return BadRequest("Nama TV wajib diisi.");

        var (success, error) = await _dashboardTokenService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _dashboardTokenService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }

    // Token lama langsung mati -- TV yang masih memakainya berhenti pada refresh berikutnya.
    [HttpPost("{id:int}/regenerate")]
    public async Task<IActionResult> Regenerate(int id)
    {
        var (success, error, result) = await _dashboardTokenService.RegenerateAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    // Supaya admin bisa menyalin link tanpa perlu regenerate (yang akan mematikan TV yang
    // sudah aktif memakai token itu).
    [HttpGet("{id:int}/link")]
    public async Task<IActionResult> GetLink(int id)
    {
        var link = await _dashboardTokenService.GetLinkAsync(id);
        if (link is null) return NotFound();
        return Ok(new DashboardTokenLinkDto { Link = link });
    }
}

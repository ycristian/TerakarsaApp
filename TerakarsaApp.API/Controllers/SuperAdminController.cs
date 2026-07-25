using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.SuperAdmin;

namespace TerakarsaApp.API.Controllers;

// Prompt 29: module Super Admin -- koreksi data langsung bundle & workflow log yang
// melewati guard normal. Module SUPER_ADMIN tidak di-auto-assign (lihat
// sql/seed_super_admin_module.sql), jadi RequireModule di sini adalah satu-satunya pintu.
[ApiController]
[Route("api/super-admin")]
[Authorize]
[RequireModule("SUPER_ADMIN")]
public class SuperAdminController : ControllerBase
{
    private readonly SuperAdminService _superAdminService;
    // Reprint label memakai ulang SIS_Bundle_ReprintLabel lewat BundleService.ReprintAsync yang
    // sudah ada (bukan duplikasi SP) -- diekspos di sini supaya user SUPER_ADMIN-only (tanpa
    // module BUNDLE_MANAGE) tetap bisa cetak ulang label setelah koreksi bundle, tanpa mengubah
    // otorisasi BundleController.
    private readonly BundleService _bundleService;

    public SuperAdminController(SuperAdminService superAdminService, BundleService bundleService)
    {
        _superAdminService = superAdminService;
        _bundleService = bundleService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("bundles")]
    public async Task<IActionResult> SearchBundles([FromQuery] string? search)
    {
        var result = await _superAdminService.SearchBundlesAsync(search);
        return Ok(result);
    }

    [HttpGet("bundles/{id:int}")]
    public async Task<IActionResult> GetBundleDetail(int id)
    {
        var result = await _superAdminService.GetBundleDetailAsync(id);
        if (result is null) return NotFound();
        return Ok(result);
    }

    [HttpPut("bundles/{id:int}")]
    public async Task<IActionResult> UpdateBundle(int id, [FromBody] SuperAdminBundleUpdateRequest request)
    {
        var (success, error) = await _superAdminService.UpdateBundleAsync(id, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("bundles/{id:int}")]
    public async Task<IActionResult> DeleteBundle(int id, [FromBody] SuperAdminDeleteRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DeleteReason))
            return BadRequest("Alasan hapus wajib diisi.");

        var (success, error) = await _superAdminService.DeleteBundleAsync(id, request.DeleteReason, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("bundles/{id:int}/reprint")]
    public async Task<IActionResult> ReprintBundle(int id)
    {
        var (success, error, printJobId) = await _bundleService.ReprintAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    [HttpPut("workflow-logs/{id:int}")]
    public async Task<IActionResult> UpdateLog(int id, [FromBody] SuperAdminLogUpdateRequest request)
    {
        var (success, error) = await _superAdminService.UpdateLogAsync(id, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("workflow-logs/{id:int}")]
    public async Task<IActionResult> DeleteLog(int id, [FromBody] SuperAdminDeleteRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DeleteReason))
            return BadRequest("Alasan hapus wajib diisi.");

        var (success, error) = await _superAdminService.DeleteLogAsync(id, request.DeleteReason, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

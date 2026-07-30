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
    public async Task<IActionResult> ReprintBundle(int id, [FromQuery] int copies = 1)
    {
        if (copies < 1) return BadRequest("Jumlah label harus minimal 1.");

        var (success, error, printJobId) = await _bundleService.ReprintAsync(id, copies, CurrentUserId);
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

    // Prompt 36: modal "Edit Log"/"Edit Bundle" langsung dari /b/{serial} & /report-bundle
    // (tab Riwayat) -- validasi arah bawah/atas, BEDA dari LOG_UPDATE/BUNDLE_UPDATE di atas
    // (koreksi bebas panel /super-admin). Lihat SIS_SuperAdmin_Manage @Action = 'EDIT_LOG'/
    // 'EDIT_BUNDLE'.
    [HttpGet("logs/{id:int}/edit-info")]
    public async Task<IActionResult> GetLogEditInfo(int id)
    {
        var result = await _superAdminService.GetLogEditInfoAsync(id);
        if (result is null) return NotFound();
        return Ok(result);
    }

    [HttpPut("logs/{id:int}/edit")]
    public async Task<IActionResult> EditLog(int id, [FromBody] SuperAdminEditLogRequest request)
    {
        var (success, error) = await _superAdminService.EditLogAsync(id, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut("bundles/{id:int}/edit")]
    public async Task<IActionResult> EditBundle(int id, [FromBody] SuperAdminEditBundleRequest request)
    {
        var (success, error) = await _superAdminService.EditBundleAsync(id, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Dropdown Line/Pelaksana (GetActiveByDivisionAsync) & Penjahit cascading
    // (GetActiveByResourceAsync) -- proxy tipis ke ResourceService/EmployeeService yang
    // sudah dipakai ResourceController/EmployeeController, diekspos di sini (bukan lewat
    // controller aslinya) supaya user SUPER_ADMIN-only (tanpa module MASTER_RESOURCE/
    // MASTER_EMPLOYEE) tetap bisa isi dropdown modal Edit Bundle/Edit Log.
    [HttpGet("resources/by-division/{divisionId:int}")]
    public async Task<IActionResult> GetResourcesByDivision(int divisionId)
    {
        var result = await _superAdminService.GetResourcesByDivisionAsync(divisionId);
        return Ok(result);
    }

    [HttpGet("employees/by-resource/{resourceId:int}")]
    public async Task<IActionResult> GetEmployeesByResource(int resourceId)
    {
        var result = await _superAdminService.GetEmployeesByResourceAsync(resourceId);
        return Ok(result);
    }
}

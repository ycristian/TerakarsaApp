using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Payroll;

namespace TerakarsaApp.API.Controllers;

// Prompt 83: Rekap Gajian admin (module PAYROLL_REKAP, halaman /payroll-rekap).
//
// Di sini-lah satu-satunya tempat harga borongan bisa diubah (SIS_LockItem_UpdatePrice) dan
// periode gajian bisa difinalisasi. Module-nya dipisah dari MANUAL_OUTPUT dengan sengaja:
// melihat daftar output manual tidak otomatis berarti boleh mengubah nominal upah.
//
// Semua aturan ditegakkan di SP (periode final -> harga read-only; finalisasi ditolak kalau
// masih ada harga kosong). Pesan error SP diteruskan APA ADANYA supaya prefix
// 'HARGA_KOSONG|' sampai ke client.
[ApiController]
[Route("api/payroll-rekap")]
[Authorize]
[RequireModule("PAYROLL_REKAP")]
public class PayrollRekapController : ControllerBase
{
    private readonly PayrollRekapService _payrollRekapService;
    private readonly DivisionService _divisionService;

    public PayrollRekapController(PayrollRekapService payrollRekapService, DivisionService divisionService)
    {
        _payrollRekapService = payrollRekapService;
        _divisionService = divisionService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("periods")]
    public async Task<IActionResult> GetPeriods()
    {
        var result = await _payrollRekapService.GetPeriodsAsync();
        return Ok(result);
    }

    [HttpGet("divisions")]
    public async Task<IActionResult> GetDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{payrollPeriodId:int}")]
    public async Task<IActionResult> Get(
        int payrollPeriodId,
        [FromQuery] int? divisionId = null,
        [FromQuery] int? resourceId = null,
        [FromQuery] bool onlyMissingPrice = false)
    {
        var result = await _payrollRekapService.GetAsync(
            payrollPeriodId, divisionId, resourceId, onlyMissingPrice);
        return Ok(result);
    }

    // Nilai MINUS diperbolehkan (dipakai baris potongan); UnitPrice null = kosongkan lagi.
    // Sengaja TIDAK ada validasi >= 0 di sini maupun di SP.
    [HttpPut("items/{lockItemId:int}/price")]
    public async Task<IActionResult> UpdatePrice(int lockItemId, [FromBody] LockItemPriceRequest request)
    {
        var (success, error) = await _payrollRekapService.UpdateLockItemPriceAsync(
            lockItemId, request?.UnitPrice, CurrentUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Ditolak selama masih ada lock item dengan harga kosong -- daftar baris bermasalahnya
    // ikut dikembalikan supaya admin tahu harus memperbaiki apa.
    [HttpPost("{payrollPeriodId:int}/finalize")]
    public async Task<IActionResult> Finalize(int payrollPeriodId)
    {
        var (success, error, missingRows) = await _payrollRekapService.FinalizeAsync(
            payrollPeriodId, CurrentUserId);

        if (!success)
            return BadRequest(new { error, missingRows });

        return Ok();
    }

    [HttpPost("{payrollPeriodId:int}/unfinalize")]
    public async Task<IActionResult> Unfinalize(int payrollPeriodId)
    {
        var (success, error) = await _payrollRekapService.UnfinalizeAsync(payrollPeriodId, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

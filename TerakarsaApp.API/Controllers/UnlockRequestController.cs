using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.UnlockRequests;

namespace TerakarsaApp.API.Controllers;

// Prompt 57: meja admin "Request Unlock" (module UNLOCK_REQUEST, halaman /unlock-requests).
// Read lewat SIS_UnlockRequest_List / SIS_UnlockRequest_Detail; keputusan lewat
// SIS_UnlockRequest_Manage APPROVE/REJECT (SP Prompt 55, TIDAK diubah). @UserId keputusan =
// user login dari JWT -- berbeda dari sisi stasiun (StationDeviceController) yang memakai user
// sistem station_system. Pesan error SP diteruskan APA ADANYA.
// Dropdown divisi memakai ulang DivisionService.GetActiveAsync (pola sama dengan
// ReportActivityLogController), tanpa endpoint/SP baru.
[ApiController]
[Route("api/unlock-requests")]
[Authorize]
[RequireModule("UNLOCK_REQUEST")]
public class UnlockRequestController : ControllerBase
{
    private readonly WorkflowLockService _workflowLockService;
    private readonly DivisionService _divisionService;

    public UnlockRequestController(WorkflowLockService workflowLockService, DivisionService divisionService)
    {
        _workflowLockService = workflowLockService;
        _divisionService = divisionService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<IActionResult> GetList(
        [FromQuery] string? state, [FromQuery] int? divisionId,
        [FromQuery] DateTime? dateFrom, [FromQuery] DateTime? dateTo)
    {
        if (dateFrom.HasValue && dateTo.HasValue && dateTo.Value.Date < dateFrom.Value.Date)
            return BadRequest("Rentang tanggal tidak valid.");

        var result = await _workflowLockService.ListAsync(state, divisionId, dateFrom, dateTo);
        return Ok(result);
    }

    [HttpGet("divisions")]
    public async Task<IActionResult> GetDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetDetail(int id)
    {
        var (result, error) = await _workflowLockService.GetDetailAsync(id);
        if (error is not null) return BadRequest(error);
        if (result is null) return NotFound("Pengajuan tidak ditemukan.");
        return Ok(result);
    }

    [HttpPost("{id:int}/approve")]
    public async Task<IActionResult> Approve(int id, [FromBody] UnlockRequestDecisionRequest? request)
    {
        var (success, error) = await _workflowLockService.DecideAsync(id, true, request?.AdminNote, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("{id:int}/reject")]
    public async Task<IActionResult> Reject(int id, [FromBody] UnlockRequestDecisionRequest request)
    {
        // Catatan wajib saat menolak -- dicek juga di SP (single source of truth), di sini hanya
        // supaya pesannya tidak perlu bolak-balik ke DB.
        if (string.IsNullOrWhiteSpace(request?.AdminNote))
            return BadRequest("Catatan admin wajib diisi saat menolak.");

        var (success, error) = await _workflowLockService.DecideAsync(id, false, request.AdminNote, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

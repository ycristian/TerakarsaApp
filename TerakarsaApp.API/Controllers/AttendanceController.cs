using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.API.Controllers;

// Prompt 70: halaman admin /attendance -- CRUD kartu pegawai, rekap absensi, koreksi anomali.
// Berbeda dengan GateController (tanpa login, X-Gate-Api-Key), di sini JWT + module biasa.
[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("HR_ATTENDANCE")]
public class AttendanceController : ControllerBase
{
    private readonly AttendanceService _attendanceService;

    public AttendanceController(AttendanceService attendanceService)
    {
        _attendanceService = attendanceService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    // ---------- Tab 1: Kartu Karyawan ----------

    [HttpPost("cards/list")]
    public async Task<IActionResult> GetCards([FromBody] EmployeeCardListRequest request)
    {
        var result = await _attendanceService.GetCardsAsync(request);
        return Ok(result);
    }

    [HttpGet("cards/{id:int}")]
    public async Task<IActionResult> GetCardById(int id)
    {
        var card = await _attendanceService.GetCardByIdAsync(id);
        if (card is null) return NotFound();
        return Ok(card);
    }

    [HttpPost("cards")]
    public async Task<IActionResult> CreateCard([FromBody] EmployeeCardCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.CardUid))
            return BadRequest("UID kartu wajib diisi.");

        var (success, error) = await _attendanceService.CreateCardAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut("cards")]
    public async Task<IActionResult> UpdateCard([FromBody] EmployeeCardUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.CardUid))
            return BadRequest("UID kartu wajib diisi.");

        var (success, error) = await _attendanceService.UpdateCardAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Terpisah dari Hapus: ini jalur normal kartu hilang/diganti, riwayat tetap utuh.
    [HttpPost("cards/deactivate")]
    public async Task<IActionResult> DeactivateCard([FromBody] EmployeeCardDeactivateRequest request)
    {
        var (success, error) = await _attendanceService.DeactivateCardAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("cards/{id:int}")]
    public async Task<IActionResult> DeleteCard(int id)
    {
        var (success, error) = await _attendanceService.DeleteCardAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // ---------- Tab 2: Rekap Absensi ----------

    [HttpPost("report")]
    public async Task<IActionResult> GetReport([FromBody] AttendanceReportRequest request)
    {
        var result = await _attendanceService.GetReportAsync(request);
        return Ok(result);
    }

    // ---------- Tab 3: Koreksi Absensi ----------

    [HttpPost("anomali")]
    public async Task<IActionResult> GetAnomali([FromBody] AttendanceAnomaliRequest request)
    {
        var result = await _attendanceService.GetAnomaliAsync(request);
        return Ok(result);
    }

    [HttpPost("correct")]
    public async Task<IActionResult> Correct([FromBody] AttendanceCorrectRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Remarks))
            return BadRequest("Catatan koreksi wajib diisi.");

        var (success, error) = await _attendanceService.CorrectAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("manual")]
    public async Task<IActionResult> CreateManual([FromBody] AttendanceManualRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Remarks))
            return BadRequest("Catatan wajib diisi untuk absensi manual.");

        var (success, error) = await _attendanceService.CreateManualAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // "Tandai sudah benar": jam pulang memang tidak diketahui, sesi keluar dari antrian koreksi.
    [HttpPost("ack")]
    public async Task<IActionResult> Ack([FromBody] AttendanceAckRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Remarks))
            return BadRequest("Catatan wajib diisi.");

        var (success, error) = await _attendanceService.AckAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("delete")]
    public async Task<IActionResult> DeleteSession([FromBody] AttendanceDeleteRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Remarks))
            return BadRequest("Catatan wajib diisi saat menghapus sesi absensi.");

        var (success, error) = await _attendanceService.DeleteSessionAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.API.Controllers;

// Prompt 70: endpoint untuk TerakarsaApp.GateApp (tablet di meja satpam).
// SENGAJA TANPA [Authorize]: aplikasi gate tidak punya login. Autentikasinya header
// X-Gate-Api-Key (RequireGateApiKeyAttribute), dan akses menu satpam di dalam aplikasi gate
// ditentukan jabatan kartu (positions.is_gate_operator), bukan oleh user/role.
//
// created_by semua mutasi dari sini = user sistem gate_system (Gate:SystemUserId di
// appsettings); pelaku sebenarnya (satpam) tercatat di kolom *_by_employee_id.
[ApiController]
[Route("api/gate")]
[RequireGateApiKey]
public class GateController : ControllerBase
{
    private readonly GateService _gateService;
    private readonly GateOptions _gateOptions;

    public GateController(GateService gateService, IOptions<GateOptions> gateOptions)
    {
        _gateService = gateService;
        _gateOptions = gateOptions.Value;
    }

    // Master kartu + master karyawan + serverTime, satu panggilan (SIS_Gate_CardSync).
    [HttpGet("cards")]
    public async Task<IActionResult> GetCards()
    {
        var result = await _gateService.GetCardSyncAsync();
        return Ok(result);
    }

    // Antrian tap. Server mengurutkan menurut tappedAt lalu memanggil SIS_Gate_Tap satu per
    // satu; urutan response sama dengan urutan input, dan satu tap gagal tidak membatalkan
    // tap lain.
    [HttpPost("taps")]
    public async Task<IActionResult> PostTaps([FromBody] GateTapBatchRequest request)
    {
        if (request.Taps is null || request.Taps.Count == 0)
            return Ok(new List<GateTapResultDto>());

        var gateCode = NormalizeGateCode(request.GateCode);
        if (gateCode is null) return BadRequest("gateCode wajib dikirim.");

        var results = await _gateService.ProcessTapsAsync(request.Taps, gateCode, _gateOptions.SystemUserId);
        return Ok(results);
    }

    [HttpGet("counts")]
    public async Task<IActionResult> GetCounts([FromQuery] string? gateCode, [FromQuery] DateTime? atDate)
    {
        var result = await _gateService.GetCountsAsync(gateCode, atDate);
        return Ok(result);
    }

    [HttpGet("pending")]
    public async Task<IActionResult> GetPending([FromQuery] string mode)
    {
        if (string.IsNullOrWhiteSpace(mode)) return BadRequest("mode wajib dikirim.");
        var result = await _gateService.GetPendingAsync(mode);
        return Ok(result);
    }

    // Butuh ONLINE -- TIDAK boleh diantrekan offline: UID kembar harus dicek ke server.
    [HttpPost("cards/register")]
    public async Task<IActionResult> RegisterCard([FromBody] GateRegisterCardRequest request)
    {
        var (success, error, result) = await _gateService.RegisterCardAsync(request, _gateOptions.SystemUserId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    // Butuh ONLINE -- TIDAK boleh diantrekan offline.
    [HttpPost("employees/update")]
    public async Task<IActionResult> UpdateEmployee([FromBody] GateUpdateEmployeeRequest request)
    {
        var (success, error) = await _gateService.UpdateEmployeeAsync(request, _gateOptions.SystemUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Butuh ONLINE -- TIDAK boleh diantrekan: pembatalan harus kena sesi yang saat ini OPEN.
    [HttpPost("sessions/cancel")]
    public async Task<IActionResult> CancelSession([FromBody] GateCancelSessionRequest request)
    {
        var (success, error) = await _gateService.CancelSessionAsync(request, _gateOptions.SystemUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // gateCode selalu dari body/query (satu API bisa melayani beberapa gate), bukan hardcode.
    private static string? NormalizeGateCode(string? gateCode) =>
        string.IsNullOrWhiteSpace(gateCode) ? null : gateCode.Trim();
}

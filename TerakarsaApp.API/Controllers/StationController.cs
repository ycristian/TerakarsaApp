using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Controllers;

// Admin-only CRUD untuk stasiun, pakai JWT biasa. Endpoint untuk perangkat
// stasiun sendiri (autentikasi via X-Station-Token) ada di StationDeviceController.
[ApiController]
[Route("api/station")]
[Authorize]
[RequireModule("STATION_MANAGE")]
public class StationController : ControllerBase
{
    private readonly StationService _stationService;

    public StationController(StationService stationService)
    {
        _stationService = stationService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] StationPagedRequest request)
    {
        var result = await _stationService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var station = await _stationService.GetByIdAsync(id);
        if (station is null) return NotFound();
        return Ok(station);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] StationCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.StationCode))
            return BadRequest("Kode stasiun wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.StationName))
            return BadRequest("Nama stasiun wajib diisi.");

        if (request.DivisionId <= 0)
            return BadRequest("Divisi wajib dipilih.");

        var (success, error, result) = await _stationService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] StationUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.StationCode))
            return BadRequest("Kode stasiun wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.StationName))
            return BadRequest("Nama stasiun wajib diisi.");

        if (request.DivisionId <= 0)
            return BadRequest("Divisi wajib dipilih.");

        var (success, error) = await _stationService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _stationService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }

    // Prompt 20: menggantikan "regenerate-token" lama -- admin membuat kode pairing baru
    // (5 karakter, 15 menit, sekali pakai) alih-alih melihat token mentah.
    [HttpPost("{id:int}/pairing-code")]
    public async Task<IActionResult> GeneratePairingCode(int id)
    {
        var (success, error, result) = await _stationService.GeneratePairingCodeAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    // Prompt 20: "Putuskan Perangkat" -- rotasi station_token, perangkat lama tertendang.
    // Token baru TIDAK dikembalikan ke admin (perangkat harus klaim ulang lewat kode pairing).
    [HttpPost("{id:int}/unpair")]
    public async Task<IActionResult> Unpair(int id)
    {
        var (success, error) = await _stationService.UnpairAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

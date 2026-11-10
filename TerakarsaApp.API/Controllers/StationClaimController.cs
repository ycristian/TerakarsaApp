using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Controllers;

// Prompt 20: pairing perangkat stasiun. "claim" murni ANONIM (perangkat belum punya
// token sama sekali) -- keamanannya mengandalkan kode pairing 5 karakter, kedaluwarsa
// 15 menit, dan sekali pakai (lihat SIS_Station_Manage CLAIM_PAIRING). "logout" tetap
// butuh token perangkat yang sedang aktif, karenanya dipasangi [RequireStationToken]
// per-aksi (bukan di kelas, supaya "claim" tetap anonim).
//
// Prompt 85: claim juga menerima kode login terkunci (10 karakter, permanen) dan identitas
// perangkat; dibatasi rate limit "station-claim" karena kode terkunci tidak hangus.
[ApiController]
[Route("api/station-device")]
public class StationClaimController : ControllerBase
{
    // 5 = kode sekali pakai, 10 = kode login terkunci. Validasi sengaja tetap alfanumerik:
    // aturan "huruf saja" hanya saat membuat kode, supaya kode berangka buatan sebelum
    // Prompt 85 tetap bisa diklaim sampai hangus.
    private static readonly Regex PairingCodePattern = new("^([A-Za-z0-9]{5}|[A-Za-z0-9]{10})$", RegexOptions.Compiled);

    private readonly StationService _stationService;
    private readonly int _systemUserId;

    public StationClaimController(StationService stationService, IOptions<StationOptions> stationOptions)
    {
        _stationService = stationService;
        _systemUserId = stationOptions.Value.SystemUserId;
    }

    [HttpPost("claim")]
    [EnableRateLimiting("station-claim")]
    public async Task<IActionResult> Claim([FromBody] StationClaimRequest request)
    {
        var code = (request.Code ?? string.Empty).Trim();
        if (!PairingCodePattern.IsMatch(code))
            return BadRequest("Kode pairing tidak valid.");

        // Prompt 85: error "DIPAKAI|nama|terakhir aktif" dari SP diteruskan apa adanya --
        // client memakainya untuk dialog konfirmasi ambil alih.
        var (success, error, result) = await _stationService.ClaimPairingAsync(
            code.ToUpperInvariant(),
            StationDeviceIdentity.CleanId(request.DeviceId),
            StationDeviceIdentity.CleanName(request.DeviceName),
            request.Force);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    [HttpPost("logout")]
    [RequireStationToken]
    public async Task<IActionResult> Logout()
    {
        var station = (StationMeDto)HttpContext.Items[RequireStationTokenAttribute.HttpContextItemKey]!;
        var (success, error) = await _stationService.UnpairAsync(station.StationId, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

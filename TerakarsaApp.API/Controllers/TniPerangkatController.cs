using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Perangkat modul PDH TNI AD (satu nama petugas per perangkat, alter_75).
//
// PERHATIKAN BEDA OTORISASI -- dipasang PER ACTION, bukan di controller:
//   claim, me                 -> TANPA LOGIN (perangkat; claim bahkan belum
//                                punya token saat dipanggil)
//   sisanya                   -> JWT + module TNI_PDH (pengelolaan admin)
[ApiController]
[Route("api/tni/perangkat")]
public class TniPerangkatController : ControllerBase
{
    private readonly TniPerangkatService _service;

    public TniPerangkatController(TniPerangkatService service)
    {
        _service = service;
    }

    private int CurrentUserId
    {
        get
        {
            var claim = User.FindFirstValue(ClaimTypes.NameIdentifier);
            return int.TryParse(claim, out var id) ? id : 0;
        }
    }

    // ---------------- perangkat: tanpa login ----------------

    // Menukar kode pairing dengan token perangkat. Tidak butuh apa pun --
    // kodenya sendiri yang jadi bukti, sekali pakai & kedaluwarsa 15 menit.
    [HttpPost("claim")]
    [AllowAnonymous]
    public async Task<IActionResult> Claim([FromBody] TniClaimRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.PairingCode))
            return BadRequest("Kode pairing belum diisi.");

        var (ok, error, hasil) = await _service.ClaimAsync(request.PairingCode);
        if (!ok) return BadRequest(error);

        return Ok(hasil);
    }

    // Identitas perangkat pemegang token -- dipakai header halaman /tni.
    [HttpGet("me")]
    [RequireTniDeviceToken]
    public IActionResult Me()
    {
        var perangkat = HttpContext.Items[RequireTniDeviceTokenAttribute.HttpContextItemKey]
            as TniPerangkatMeDto;

        return perangkat is null ? Unauthorized() : Ok(perangkat);
    }

    // ---------------- pengelolaan: butuh login ----------------

    [HttpGet]
    [Authorize]
    [RequireModule("TNI_PDH")]
    public async Task<IActionResult> GetList() => Ok(await _service.GetListAsync());

    [HttpPost]
    [Authorize]
    [RequireModule("TNI_PDH")]
    public async Task<IActionResult> Create([FromBody] TniPerangkatCreateRequest request)
    {
        var (ok, error, id) = await _service.CreateAsync(request, CurrentUserId);
        return ok ? Ok(new { PerangkatId = id }) : BadRequest(error);
    }

    [HttpPut("{id:int}")]
    [Authorize]
    [RequireModule("TNI_PDH")]
    public async Task<IActionResult> Update(int id, [FromBody] TniPerangkatCreateRequest request)
    {
        var (ok, error) = await _service.UpdateAsync(id, request, CurrentUserId);
        return ok ? Ok() : BadRequest(error);
    }

    [HttpDelete("{id:int}")]
    [Authorize]
    [RequireModule("TNI_PDH")]
    public async Task<IActionResult> Delete(int id)
    {
        var (ok, error) = await _service.DeleteAsync(id, CurrentUserId);
        return ok ? Ok() : BadRequest(error);
    }

    // Kode baru menghanguskan kode lama; token perangkat belum berubah sampai diklaim.
    [HttpPost("{id:int}/pairing")]
    [Authorize]
    [RequireModule("TNI_PDH")]
    public async Task<IActionResult> GeneratePairing(int id)
    {
        var (ok, error, hasil) = await _service.GeneratePairingAsync(id, CurrentUserId);
        return ok ? Ok(hasil) : BadRequest(error);
    }

    // Memutus perangkat: token diganti, perangkat lama langsung kehilangan akses.
    [HttpPost("{id:int}/unpair")]
    [Authorize]
    [RequireModule("TNI_PDH")]
    public async Task<IActionResult> Unpair(int id)
    {
        var (ok, error) = await _service.UnpairAsync(id, CurrentUserId);
        return ok ? Ok() : BadRequest(error);
    }
}

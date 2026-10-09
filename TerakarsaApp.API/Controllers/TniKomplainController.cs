using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Komplain ukuran dari halaman QR /t/{token} (2026-10-06).
//
// OTORISASI PER ACTION:
//   kirim (POST {token})       -> TANPA LOGIN & tanpa perangkat: orang luar yang
//                                 memegang QR kartunya boleh mengomplain.
//                                 created_by = user sistem tni_system.
//   daftar (GET personel/{id}) -> perangkat terdaftar saja (berisi no telp).
[ApiController]
[Route("api/tni/komplain")]
public class TniKomplainController : ControllerBase
{
    private readonly TniKomplainService _service;
    private readonly TniOptions _opts;

    public TniKomplainController(TniKomplainService service, IOptions<TniOptions> opts)
    {
        _service = service;
        _opts = opts.Value;
    }

    [HttpPost("{token}")]
    [AllowAnonymous]
    public async Task<IActionResult> Kirim(string token, [FromBody] TniKomplainRequest request)
    {
        var (ok, error) = await _service.CreateAsync(token, request, _opts.SystemUserId);
        return ok ? Ok() : BadRequest(error);
    }

    [HttpGet("personel/{personelId:int}")]
    [RequireTniDeviceToken]
    public async Task<IActionResult> ByPersonel(int personelId)
        => Ok(await _service.GetByPersonelAsync(personelId));
}

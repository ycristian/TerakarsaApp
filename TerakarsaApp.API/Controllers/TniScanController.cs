using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 66: scan "Set Jadi" PDH TNI AD.
// Scan TIDAK PERNAH ditolak karena stok kurang/minus (keputusan owner) --
// stok boleh minus karena setoran mungkin belum dicatat.
[ApiController]
[Route("api/tni/scan")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniScanController : ControllerBase
{
    private readonly TniScanService _scanService;
    private readonly TniBoxService _boxService;

    public TniScanController(TniScanService scanService, TniBoxService boxService)
    {
        _scanService = scanService;
        _boxService = boxService;
    }

    // created_by: user login bila ada, kalau tidak user sistem tni_system.
    private int CurrentUserId => this.TniActorUserId();

    // Pop up konfirmasi: data kartu (isi label cetak) TANPA mencatat set.
    // POST, bukan GET: qr_token tidak ikut tercatat di log URL.
    [HttpPost("lookup")]
    public async Task<IActionResult> Lookup([FromBody] TniScanRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Kode))
            return BadRequest("Kode belum diisi.");

        var detail = await _scanService.LookupAsync(request.Kode.Trim());
        return detail is null ? NotFound() : Ok(detail);
    }

    [HttpPost("set-jadi")]
    public async Task<IActionResult> SetJadi([FromBody] TniScanRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Kode))
            return BadRequest("Kode belum diisi.");

        return Ok(await _scanService.SetJadiAsync(request.Kode.Trim(), CurrentUserId, this.TniPerangkatId()));
    }

    // Prompt 67: scan "Masuk Box". Hasilnya memakai bentuk yang sama dengan
    // set-jadi (TniScanHasilDto) supaya UI scan bisa memakai satu banner.
    [HttpPost("masuk-box")]
    public async Task<IActionResult> MasukBox([FromBody] TniMasukBoxRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Kode))
            return BadRequest("Kode belum diisi.");

        if (request.BoxId <= 0)
            return BadRequest("Pilih box dulu.");

        return Ok(await _boxService.MasukBoxAsync(request.Kode.Trim(), request.BoxId, CurrentUserId, this.TniPerangkatId(), request.Paksa));
    }
}

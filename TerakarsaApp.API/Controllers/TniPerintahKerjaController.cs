using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 65: Perintah Kerja & cetak kartu personel PDH TNI AD.
// Angka "bisa dibuat" adalah SARAN (greedy di service) -- tidak pernah memblokir
// pencetakan, dan cetak tidak mengunci stok.
[ApiController]
[Route("api/tni/perintah-kerja")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniPerintahKerjaController : ControllerBase
{
    private readonly TniPerintahKerjaService _pkService;
    private readonly TniOrderService _orderService;

    public TniPerintahKerjaController(TniPerintahKerjaService pkService, TniOrderService orderService)
    {
        _pkService = pkService;
        _orderService = orderService;
    }

    // created_by: user login bila ada, kalau tidak user sistem tni_system.
    private int CurrentUserId => this.TniActorUserId();

    private async Task<int?> OrderIdAsync() => (await _orderService.GetAktifAsync())?.OrderId;

    [HttpGet("rawatan")]
    public async Task<IActionResult> GetRawatan()
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new { rawatan = new List<TniRawatanDto>(), stokBebasKemeja = 0, stokBebasCelana = 0 });

        var rawatan = await _pkService.GetRawatanAsync(orderId.Value);
        var (kemeja, celana) = await _pkService.GetTotalStokBebasAsync(orderId.Value);

        return Ok(new { rawatan, stokBebasKemeja = kemeja, stokBebasCelana = celana });
    }

    [HttpGet("rawatan/{areaId:int}/satuan")]
    public async Task<IActionResult> GetSatuan(int areaId)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new List<TniSatuanSaranDto>());

        return Ok(await _pkService.GetSatuanAsync(orderId.Value, areaId));
    }

    [HttpGet("satuan/{satuanId:int}")]
    public async Task<IActionResult> GetSatuanDetail(int satuanId)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new TniSatuanDetailDto());

        return Ok(await _pkService.GetSatuanDetailAsync(orderId.Value, satuanId));
    }

    [HttpGet("satuan/{satuanId:int}/dijatah")]
    public async Task<IActionResult> GetDijatah(int satuanId)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new List<TniDijatahDto>());

        return Ok(await _pkService.GetDijatahAsync(orderId.Value, satuanId));
    }

    [HttpPost("cetak")]
    public async Task<IActionResult> Cetak([FromBody] TniCetakRequest request)
    {
        if (request.PersonelIds is null || request.PersonelIds.Count == 0)
            return BadRequest("Belum ada personel yang dipilih.");

        var (success, error, hasil) = await _pkService.CetakAsync(request.PersonelIds, CurrentUserId, this.TniPerangkatId());
        if (!success) return BadRequest(error);
        return Ok(hasil);
    }

    [HttpPost("lepas")]
    public async Task<IActionResult> Lepas([FromBody] TniCetakRequest request)
    {
        if (request.PersonelIds is null || request.PersonelIds.Count == 0)
            return BadRequest("Belum ada kartu yang dipilih.");

        var (success, error, hasil) = await _pkService.LepasAsync(request.PersonelIds, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(hasil);
    }
}

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 68: pengajuan & persetujuan pembatalan scan PDH TNI AD.
//
// PERHATIKAN BEDA OTORISASI -- dipasang PER ACTION, bukan di controller:
//   ajukan + riwayat personel -> PERANGKAT, tanpa login (X-Tni-Token)
//   list / setujui / tolak     -> WAJIB JWT + module TNI_PDH_APPROVE
//
// Inilah satu-satunya bagian modul TNI yang masih butuh login: staff di
// lantai tidak boleh menyetujui pembatalan scan-nya sendiri.
[ApiController]
[Route("api/tni/pembatalan")]
public class TniPembatalanController : ControllerBase
{
    private readonly TniPembatalanService _service;
    private readonly TniOrderService _orderService;

    public TniPembatalanController(TniPembatalanService service, TniOrderService orderService)
    {
        _service = service;
        _orderService = orderService;
    }

    // Pengaju lewat perangkat: created_by user sistem, perangkat pengaju di PerangkatId
    // (nama petugas = perangkat.nama_petugas).
    // Pemutus SELALU user login (endpoint putusan tetap pakai JWT).
    private int CurrentUserId => this.TniActorUserId();

    private async Task<int?> OrderIdAsync() => (await _orderService.GetAktifAsync())?.OrderId;

    // ---------------- staff: mengajukan ----------------

    [HttpPost("ajukan")]
    [RequireTniDeviceToken]
    public async Task<IActionResult> Ajukan([FromBody] TniPembatalanAjukanRequest request)
    {
        if (request.PersonelId <= 0)
            return BadRequest("Personel belum dipilih.");

        if (string.IsNullOrWhiteSpace(request.Alasan))
            return BadRequest("Alasan pembatalan wajib diisi.");

        var jenis = (request.Jenis ?? string.Empty).Trim().ToUpperInvariant();
        if (jenis is not ("SET" or "BOX"))
            return BadRequest("Jenis pembatalan harus SET atau BOX.");

        return Ok(await _service.AjukanAsync(
            new TniPembatalanAjukanRequest
            {
                PersonelId = request.PersonelId,
                Jenis = jenis,
                Alasan = request.Alasan.Trim()
            },
            CurrentUserId, this.TniPerangkatId()));
    }

    // Riwayat pembatalan satu personel -- dipakai detail personel, /t/{token},
    // dan sheet aksi di layar scan.
    [HttpGet("personel/{personelId:int}")]
    [RequireTniDeviceToken]
    public async Task<IActionResult> GetByPersonel(int personelId)
        => Ok(await _service.GetByPersonelAsync(personelId));

    // ---------------- approver: memutus ----------------

    [HttpGet]
    [Authorize]
    [RequireModule("TNI_PDH_APPROVE")]
    public async Task<IActionResult> GetList(
        [FromQuery] string? status = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 30)
    {
        if (status is not (null or "MENUNGGU" or "DISETUJUI" or "DITOLAK"))
            return BadRequest("Status harus MENUNGGU, DISETUJUI, atau DITOLAK.");

        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new List<TniPembatalanDto>());

        return Ok(await _service.GetListAsync(orderId.Value, status, pageNumber, pageSize));
    }

    [HttpPost("{id:int}/setujui")]
    [Authorize]
    [RequireModule("TNI_PDH_APPROVE")]
    public async Task<IActionResult> Setujui(int id, [FromBody] TniPembatalanPutusanRequest request)
        => Ok(await _service.SetujuiAsync(id, request?.Catatan?.Trim(), CurrentUserId));

    [HttpPost("{id:int}/tolak")]
    [Authorize]
    [RequireModule("TNI_PDH_APPROVE")]
    public async Task<IActionResult> Tolak(int id, [FromBody] TniPembatalanPutusanRequest request)
    {
        // Catatan wajib -- SP juga menolak, ini hanya supaya pesannya cepat.
        if (string.IsNullOrWhiteSpace(request?.Catatan))
            return BadRequest("Catatan wajib diisi saat menolak pengajuan.");

        return Ok(await _service.TolakAsync(id, request.Catatan.Trim(), CurrentUserId));
    }
}

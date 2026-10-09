using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 67: box & PDF isi box PDH TNI AD.
//
// PDF HANYA DIUNDUH -- tidak pernah dikirim ke print job, dan tidak disimpan ke
// disk (dibuat saat diminta).
// Membuka kembali box yang sudah ditutup TIDAK ADA di sini -- hanya lewat
// persetujuan pembatalan (Prompt 68).
[ApiController]
[Route("api/tni/box")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniBoxController : ControllerBase
{
    private readonly TniBoxService _boxService;
    private readonly TniBoxPdfService _pdfService;
    private readonly TniOrderService _orderService;

    public TniBoxController(
        TniBoxService boxService,
        TniBoxPdfService pdfService,
        TniOrderService orderService)
    {
        _boxService = boxService;
        _pdfService = pdfService;
        _orderService = orderService;
    }

    // created_by: user login bila ada, kalau tidak user sistem tni_system.
    private int CurrentUserId => this.TniActorUserId();

    private async Task<int?> OrderIdAsync() => (await _orderService.GetAktifAsync())?.OrderId;

    [HttpGet]
    public async Task<IActionResult> GetList(
        [FromQuery] int? areaId = null,
        [FromQuery] int? satuanId = null,
        [FromQuery] string? status = null,
        [FromQuery] bool? gabungan = null,
        [FromQuery] string? cari = null)   // no box (angka) atau potongan kode box
    {
        if (status is not (null or "TERBUKA" or "TERTUTUP" or "TERKIRIM"))
            return BadRequest("Status harus TERBUKA, TERTUTUP, atau TERKIRIM.");

        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new List<TniBoxListItemDto>());

        return Ok(await _boxService.GetListAsync(orderId.Value, areaId, satuanId, status, gabungan, cari));
    }

    // Box TERBUKA untuk pilihan di layar scan.
    [HttpGet("terbuka")]
    public async Task<IActionResult> GetTerbuka([FromQuery] int? areaId = null, [FromQuery] int? satuanId = null)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new List<TniBoxListItemDto>());

        return Ok(await _boxService.GetTerbukaAsync(orderId.Value, areaId, satuanId));
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var detail = await _boxService.GetByIdAsync(id);
        if (detail.Header is null) return NotFound("Box tidak ditemukan.");
        return Ok(detail);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] TniBoxCreateRequest request)
    {
        if (request.SatuanId is null && request.AreaId is null)
            return BadRequest("Pilih satuan, atau pilih rawatan untuk box gabungan.");

        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        var (success, error, hasil) = await _boxService.CreateAsync(orderId.Value, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(hasil);
    }

    [HttpPost("{id:int}/tutup")]
    public async Task<IActionResult> Tutup(int id)
    {
        var (success, error) = await _boxService.TutupAsync(id, CurrentUserId, this.TniPerangkatId());
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("{id:int}/kirim")]
    public async Task<IActionResult> Kirim(int id)
    {
        var (success, error) = await _boxService.KirimAsync(id, CurrentUserId, this.TniPerangkatId());
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Batal kirim -- box kembali TERTUTUP; alasan dicatat di keterangan box.
    [HttpPost("{id:int}/batal-kirim")]
    public async Task<IActionResult> BatalKirim(int id, [FromQuery] string? alasan = null)
    {
        var (success, error) = await _boxService.BatalKirimAsync(id, alasan, CurrentUserId, this.TniPerangkatId());
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Batal tutup (2026-10-07) -- box kembali TERBUKA; alasan dicatat di keterangan box.
    [HttpPost("{id:int}/batal-tutup")]
    public async Task<IActionResult> BatalTutup(int id, [FromQuery] string? alasan = null)
    {
        var (success, error) = await _boxService.BatalTutupAsync(id, alasan, CurrentUserId, this.TniPerangkatId());
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, [FromQuery] string? alasan = null)
    {
        var (success, error) = await _boxService.HapusAsync(id, alasan, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // PDF A4 daftar isi box. Hanya untuk box TERTUTUP / TERKIRIM.
    [HttpGet("{id:int}/pdf")]
    public async Task<IActionResult> GetPdf(int id)
    {
        var detail = await _boxService.GetByIdAsync(id);
        if (detail.Header is null) return NotFound("Box tidak ditemukan.");

        if (detail.Header.Terbuka)
            return BadRequest("Tutup box dulu sebelum mengunduh PDF.");

        var bytes = _pdfService.Build(detail);
        return File(bytes, "application/pdf", $"{detail.Header.BoxCode}.pdf");
    }
}

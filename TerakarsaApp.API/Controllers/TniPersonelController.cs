using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 63: beranda module & halaman Personel PDH TNI AD.
// Semua endpoint bekerja pada order tni.orders.is_active = 1.
[ApiController]
[Route("api/tni/personel")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniPersonelController : ControllerBase
{
    private readonly TniPersonelService _personelService;
    private readonly TniOrderService _orderService;
    private readonly TniScanService _scanService;
    private readonly TniLaporanPersonelPdfService _laporanPdfService;

    public TniPersonelController(
        TniPersonelService personelService,
        TniOrderService orderService,
        TniScanService scanService,
        TniLaporanPersonelPdfService laporanPdfService)
    {
        _personelService = personelService;
        _orderService = orderService;
        _scanService = scanService;
        _laporanPdfService = laporanPdfService;
    }

    // created_by: user login bila ada, kalau tidak user sistem tni_system.
    private int CurrentUserId => this.TniActorUserId();

    private async Task<int?> OrderIdAsync() => (await _orderService.GetAktifAsync())?.OrderId;

    [HttpGet("summary")]
    public async Task<IActionResult> GetSummary()
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new TniBerandaSummaryDto());

        return Ok(await _personelService.GetSummaryAsync(orderId.Value) ?? new TniBerandaSummaryDto());
    }

    [HttpGet("beranda-stok")]
    public async Task<IActionResult> GetBerandaStok()
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new TniBerandaStokDto());

        return Ok(await _personelService.GetBerandaStokAsync(orderId.Value));
    }

    [HttpGet]
    public async Task<IActionResult> GetList(
        [FromQuery] string? search = null,
        [FromQuery] int? areaId = null,
        [FromQuery] int? satuanId = null,
        [FromQuery] string? status = null,
        [FromQuery] bool perluReview = false,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 30,
        [FromQuery] int? polaKemejaId = null,
        [FromQuery] int? polaCelanaId = null)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new TniPersonelListResult());

        if (pageNumber < 1) pageNumber = 1;
        if (pageSize is < 1 or > 200) pageSize = 30;

        var result = await _personelService.GetListAsync(
            orderId.Value, search, areaId, satuanId, status, perluReview, pageNumber, pageSize,
            polaKemejaId, polaCelanaId);

        return Ok(result);
    }

    // Prompt 89: batas baris laporan PDF -- konstanta, bukan setting.
    private const int LaporanMaxBaris = 2000;

    // Prompt 89: PDF A4 portrait "Laporan Personel & Box" dari daftar yang
    // sedang difilter. Query string SAMA dengan GetList (tanpa paging).
    // Hanya diunduh: tidak lewat print job, tidak disimpan ke disk.
    [HttpGet("laporan-pdf")]
    public async Task<IActionResult> GetLaporanPdf(
        [FromQuery] string? search = null,
        [FromQuery] int? areaId = null,
        [FromQuery] int? satuanId = null,
        [FromQuery] string? status = null,
        [FromQuery] bool perluReview = false,
        [FromQuery] int? polaKemejaId = null,
        [FromQuery] int? polaCelanaId = null)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Tidak ada order aktif.");

        var data = await _personelService.GetLaporanAsync(
            orderId.Value, search, areaId, satuanId, status, perluReview, polaKemejaId, polaCelanaId);

        if (data.Header is null) return BadRequest("Order tidak ditemukan.");

        var n = data.Header.TotalBaris;
        if (n == 0) return BadRequest("Tidak ada personel yang cocok dengan filter.");
        if (n > LaporanMaxBaris)
            return BadRequest($"Terlalu banyak baris ({n:N0}). Persempit filter (satuan/rawatan/status/pola).");

        data.DicetakPada = DateTime.Now;
        var bytes = _laporanPdfService.Build(data);

        var stamp = data.DicetakPada.ToString("yyyyMMdd-HHmm");
        var kode = satuanId.HasValue ? data.Header.SatuanCode
                 : areaId.HasValue ? data.Header.AreaCode
                 : null;
        var nama = string.IsNullOrWhiteSpace(kode)
            ? $"Laporan_Personel_{stamp}.pdf"
            : $"Laporan_{kode}_{stamp}.pdf";

        return File(bytes, "application/pdf", nama);
    }

    [HttpGet("wilayah")]
    public async Task<IActionResult> GetWilayah()
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new List<TniWilayahRowDto>());

        return Ok(await _personelService.GetWilayahAsync(orderId.Value));
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var personel = await _personelService.GetByIdAsync(id);
        if (personel is null) return NotFound();
        return Ok(personel);
    }

    // Prompt 66: halaman /t/{token} saat user SUDAH login -- data lengkap, bentuknya
    // sama dengan GetById. Versi publiknya (tanpa login, data minimal) ada di
    // PublicController: GET api/public/tni/{token}.
    [HttpGet("by-token/{token}")]
    public async Task<IActionResult> GetByToken(string token)
    {
        var personel = await _scanService.GetDetailByTokenAsync(token);
        if (personel is null) return NotFound();
        return Ok(personel);
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] TniPersonelUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Nrp)) return BadRequest("NRP wajib diisi.");
        if (string.IsNullOrWhiteSpace(request.Nama)) return BadRequest("Nama wajib diisi.");

        var (success, error) = await _personelService.UpdateAsync(id, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut("{id:int}/pola")]
    public async Task<IActionResult> SetPola(int id, [FromBody] TniPersonelSetPolaRequest request)
    {
        var (success, error) = await _personelService.SetPolaAsync(id, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("{id:int}/reviewed")]
    public async Task<IActionResult> MarkReviewed(int id, [FromBody] TniPersonelCatatanRequest request)
    {
        var (success, error) = await _personelService.MarkReviewedAsync(id, request.Catatan, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Alasan wajib -- dikirim lewat query supaya DELETE tetap tanpa body.
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id, [FromQuery] string? alasan = null)
    {
        if (string.IsNullOrWhiteSpace(alasan)) return BadRequest("Alasan hapus wajib diisi.");

        var (success, error) = await _personelService.DeleteAsync(id, alasan, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

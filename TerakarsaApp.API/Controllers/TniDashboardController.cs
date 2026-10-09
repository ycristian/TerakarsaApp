using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 69: dashboard progres & kebutuhan size PDH TNI AD.
//
// Read-only -- tidak ada endpoint mutasi di sini. Angka progres dari
// tni.v_personel, angka stok dari tni.v_stok_pola.
[ApiController]
[Route("api/tni/dashboard")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniDashboardController : ControllerBase
{
    private readonly TniDashboardService _dashboardService;
    private readonly TniOrderService _orderService;
    private readonly TniPersonelService _personelService;

    public TniDashboardController(
        TniDashboardService dashboardService,
        TniOrderService orderService,
        TniPersonelService personelService)
    {
        _dashboardService = dashboardService;
        _orderService = orderService;
        _personelService = personelService;
    }

    [HttpGet("progres")]
    public async Task<IActionResult> GetProgres()
    {
        var order = await _orderService.GetAktifAsync();
        if (order is null) return Ok(new TniDashboardProgresDto());

        return Ok(await _dashboardService.GetProgresAsync(order.OrderId));
    }

    [HttpGet("kebutuhan-size")]
    public async Task<IActionResult> GetKebutuhanSize(
        [FromQuery] int? areaId = null,
        [FromQuery] string jenis = "KEMEJA",
        [FromQuery] int? satuanId = null)          // 2026-10-07: filter satuan
    {
        var jenisItem = Normalkan(jenis);
        if (jenisItem is null) return BadRequest("Jenis harus KEMEJA atau CELANA.");

        var order = await _orderService.GetAktifAsync();
        if (order is null) return Ok(new List<TniKebutuhanSizeDto>());

        return Ok(await _dashboardService.GetKebutuhanSizeAsync(order.OrderId, areaId, jenisItem, satuanId));
    }

    // Satu file, dua sheet (Kemeja & Celana) -- untuk diteruskan ke lantai produksi.
    [HttpGet("kebutuhan-size/excel")]
    public async Task<IActionResult> ExportKebutuhanSize(
        [FromQuery] int? areaId = null,
        [FromQuery] int? satuanId = null)
    {
        var order = await _orderService.GetAktifAsync();
        if (order is null) return NotFound("Belum ada order aktif.");

        // Label rawatan (+ satuan) untuk judul file & sheet.
        var areaLabel = "Semua rawatan";
        var kodeFile = "SEMUA";          // kode rawatan [+ nama satuan] untuk nama file
        if (areaId.HasValue || satuanId.HasValue)
        {
            var wilayah = await _personelService.GetWilayahAsync(order.OrderId);

            if (areaId.HasValue)
            {
                var area = wilayah.FirstOrDefault(x => x.AreaId == areaId.Value);
                if (area is null) return BadRequest("Rawatan tidak ditemukan.");
                areaLabel = $"{area.AreaCode} — {area.AreaName}";
                kodeFile = area.AreaCode;
            }

            if (satuanId.HasValue)
            {
                var satuan = wilayah.FirstOrDefault(x => x.SatuanId == satuanId.Value);
                if (satuan is null) return BadRequest("Satuan tidak ditemukan.");
                areaLabel = (areaId.HasValue ? areaLabel : $"{satuan.AreaCode} — {satuan.AreaName}")
                          + $" · Satuan {satuan.SatuanCode} — {satuan.SatuanName}";
                kodeFile = $"{satuan.AreaCode}_{satuan.SatuanName}";
            }
        }

        var bytes = await _dashboardService.ExportKebutuhanSizeAsync(
            order.OrderId, areaId, areaLabel, order.OrderName, satuanId);

        // 2026-10-07 permintaan owner: nama file = kode rawatan [+ nama satuan]
        // + tanggal cetak singkat, mis. "BDG_Yonif 301_07-10-26.xlsx".
        // Karakter yang dilarang di nama file Windows diganti "-".
        var aman = string.Concat(kodeFile.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '-' : c)).Trim();
        var namaFile = $"{aman}_{DateTime.Now:dd-MM-yy}.xlsx";

        return File(bytes,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            namaFile);
    }

    private static string? Normalkan(string? jenis)
    {
        var j = (jenis ?? string.Empty).Trim().ToUpperInvariant();
        return j is "KEMEJA" or "CELANA" ? j : null;
    }
}

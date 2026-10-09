using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 64: stok kemeja & celana PDH TNI AD.
// TIDAK ADA endpoint untuk TERPAKAI / BONGKAR -- keduanya hanya dibuat otomatis
// oleh scan Set Jadi (Prompt 66) dan persetujuan pembatalan (Prompt 68).
// Mutasi manual boleh dihapus (2026-10-06); setoran (header per tanggal & supplier)
// boleh diedit master + isi dan dihapus sekaligus (2026-10-07, alter_76).
[ApiController]
[Route("api/tni/stok")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniStokController : ControllerBase
{
    private readonly TniStokService _stokService;
    private readonly TniOrderService _orderService;

    public TniStokController(TniStokService stokService, TniOrderService orderService)
    {
        _stokService = stokService;
        _orderService = orderService;
    }

    // created_by: user login bila ada, kalau tidak user sistem tni_system.
    private int CurrentUserId => this.TniActorUserId();

    private async Task<int?> OrderIdAsync() => (await _orderService.GetAktifAsync())?.OrderId;

    private static bool JenisValid(string? j) => j is "KEMEJA" or "CELANA";

    [HttpGet("saldo")]
    public async Task<IActionResult> GetSaldo(
        [FromQuery] string jenis = "KEMEJA",
        [FromQuery] string? search = null,
        [FromQuery] bool hanyaAda = false)
    {
        if (!JenisValid(jenis)) return BadRequest("Jenis harus KEMEJA atau CELANA.");

        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new List<TniStokSaldoDto>());

        return Ok(await _stokService.GetSaldoAsync(orderId.Value, jenis, search, hanyaAda));
    }

    [HttpGet("riwayat")]
    public async Task<IActionResult> GetRiwayat(
        [FromQuery] string? jenis = null,
        [FromQuery] int? polaId = null,
        [FromQuery] string? jenisMutasi = null,
        [FromQuery] DateTime? dari = null,
        [FromQuery] DateTime? sampai = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] bool hanyaManual = false)   // tab Riwayat: setoran & keluarkan saja
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new TniStokRiwayatResult());

        if (pageNumber < 1) pageNumber = 1;
        if (pageSize is < 1 or > 200) pageSize = 50;

        return Ok(await _stokService.GetRiwayatAsync(
            orderId.Value, jenis, polaId, jenisMutasi, dari, sampai, pageNumber, pageSize, hanyaManual));
    }

    // Tab Riwayat (2026-10-07): satu entri = satu setoran (per tanggal & supplier)
    // atau satu RUSAK/KOREKSI. jenisMutasi: null semua | MASUK | RUSAK | KOREKSI.
    [HttpGet("riwayat-manual")]
    public async Task<IActionResult> GetRiwayatManual(
        [FromQuery] string? jenisMutasi = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 20)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return Ok(new TniStokRiwayatManualResult());

        if (pageNumber < 1) pageNumber = 1;
        if (pageSize is < 1 or > 100) pageSize = 20;

        return Ok(await _stokService.GetRiwayatManualAsync(orderId.Value, jenisMutasi, pageNumber, pageSize));
    }

    // Edit satu setoran: master (tanggal, supplier) + isi lengkap.
    [HttpPut("setoran/{id:int}")]
    public async Task<IActionResult> EditSetoran(int id, [FromBody] TniStokSetoranRequest request)
    {
        if (request.Tanggal is null) return BadRequest("Tanggal wajib diisi.");

        if (request.Items is null || request.Items.Count == 0)
            return BadRequest("Isi setoran kosong — untuk menghapus seluruh setoran pakai tombol Hapus.");

        if (request.Items.Any(i => !JenisValid(i.JenisItem)))
            return BadRequest("Jenis item harus KEMEJA atau CELANA.");

        if (request.Items.Any(i => i.PolaId <= 0 || i.Qty <= 0))
            return BadRequest("Setiap baris harus punya pola dan jumlah lebih dari 0.");

        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        var (success, error) = await _stokService.EditSetoranAsync(
            orderId.Value, id, request, CurrentUserId, this.TniPerangkatId());
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Hapus satu setoran beserta seluruh isinya (soft delete).
    [HttpDelete("setoran/{id:int}")]
    public async Task<IActionResult> HapusSetoran(int id)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        var (success, error) = await _stokService.HapusSetoranAsync(orderId.Value, id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Hapus setoran / pengeluaran (soft delete). TERPAKAI & BONGKAR ditolak SP.
    [HttpDelete("mutasi/{id:int}")]
    public async Task<IActionResult> HapusMutasi(int id)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        var (success, error) = await _stokService.HapusAsync(orderId.Value, id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("setoran")]
    public async Task<IActionResult> Setoran([FromBody] TniStokSetoranRequest request)
    {
        if (request.Items is null || request.Items.Count == 0)
            return BadRequest("Setoran kosong — tambahkan minimal satu baris.");

        if (request.Items.Any(i => !JenisValid(i.JenisItem)))
            return BadRequest("Jenis item harus KEMEJA atau CELANA.");

        if (request.Items.Any(i => i.Qty <= 0))
            return BadRequest("Jumlah setoran harus lebih dari 0.");

        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        var (success, error, hasil) = await _stokService.SetoranAsync(orderId.Value, request, CurrentUserId, this.TniPerangkatId());
        if (!success) return BadRequest(error);
        return Ok(hasil);
    }

    // 2026-10-07 (alter_77): satu pengeluaran banyak pola, sama seperti setoran.
    [HttpPost("keluar")]
    public Task<IActionResult> Keluar([FromBody] TniStokKeluarRequest request) => SimpanKeluarAsync(request, null);

    // Edit satu pengeluaran: master (tanggal, jenis, arah, alasan) + isi lengkap.
    [HttpPut("keluar/{id:int}")]
    public Task<IActionResult> EditKeluar(int id, [FromBody] TniStokKeluarRequest request) => SimpanKeluarAsync(request, id);

    private async Task<IActionResult> SimpanKeluarAsync(TniStokKeluarRequest request, int? keluarId)
    {
        if (request.JenisMutasi is not ("RUSAK" or "KOREKSI"))
            return BadRequest("Jenis mutasi harus RUSAK atau KOREKSI.");

        if (request.JenisMutasi == "KOREKSI" && request.Arah is not (1 or -1))
            return BadRequest("Arah koreksi harus tambah atau kurangi.");

        if (string.IsNullOrWhiteSpace(request.Alasan))
            return BadRequest("Alasan wajib diisi.");

        if (request.Items is null || request.Items.Count == 0)
            return BadRequest(keluarId.HasValue
                ? "Isi pengeluaran kosong — untuk menghapus seluruh pengeluaran pakai tombol Hapus."
                : "Pengeluaran kosong — tambahkan minimal satu baris.");

        if (request.Items.Any(i => !JenisValid(i.JenisItem)))
            return BadRequest("Jenis item harus KEMEJA atau CELANA.");

        if (request.Items.Any(i => i.PolaId <= 0 || i.Qty <= 0))
            return BadRequest("Setiap baris harus punya pola dan jumlah lebih dari 0.");

        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        var (success, error) = await _stokService.KeluarAsync(
            orderId.Value, request, CurrentUserId, this.TniPerangkatId(), keluarId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Hapus satu pengeluaran beserta seluruh isinya (soft delete).
    [HttpDelete("keluar/{id:int}")]
    public async Task<IActionResult> HapusKeluar(int id)
    {
        var orderId = await OrderIdAsync();
        if (orderId is null) return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        var (success, error) = await _stokService.HapusKeluarAsync(orderId.Value, id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Prompt 62: import personel PDH TNI AD dari export Google Form (.xlsx).
// Alur dua langkah: POST upload (staging + cek) lalu POST {batchId}/commit (simpan).
// File Excel TIDAK disimpan ke disk.
[ApiController]
[Route("api/tni/import")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniImportController : ControllerBase
{
    private const long MaxBytes = 10 * 1024 * 1024;   // 10 MB

    private readonly TniImportService _importService;
    private readonly TniOrderService _orderService;

    public TniImportController(TniImportService importService, TniOrderService orderService)
    {
        _importService = importService;
        _orderService = orderService;
    }

    // created_by: user login bila ada, kalau tidak user sistem tni_system.
    private int CurrentUserId => this.TniActorUserId();

    [HttpPost("upload")]
    [RequestSizeLimit(MaxBytes)]
    public async Task<IActionResult> Upload([FromForm] IFormFile? file)
    {
        if (file is null || file.Length == 0)
            return BadRequest("File belum dipilih.");

        if (file.Length > MaxBytes)
            return BadRequest("Ukuran file melebihi 10 MB.");

        if (!Path.GetExtension(file.FileName).Equals(".xlsx", StringComparison.OrdinalIgnoreCase))
            return BadRequest("File harus berformat .xlsx.");

        var order = await _orderService.GetAktifAsync();
        if (order is null)
            return BadRequest("Belum ada order PDH TNI AD yang aktif.");

        List<TerakarsaApp.Shared.Tni.TniImportRow> rows;
        try
        {
            // Dibaca dari memori; file tidak pernah menyentuh disk server.
            using var ms = new MemoryStream();
            await file.CopyToAsync(ms);
            ms.Position = 0;
            rows = _importService.ParseExcel(ms);
        }
        catch (InvalidOperationException ex)
        {
            // header hilang / sheet kosong -- pesannya sudah untuk manusia
            return BadRequest(ex.Message);
        }
        catch (Exception ex)
        {
            return BadRequest($"Gagal membaca file Excel: {ex.Message}");
        }

        if (rows.Count == 0)
            return BadRequest("Tidak ada baris data di file ini.");

        var batchId = await _importService.StageAsync(order.OrderId, file.FileName, rows, CurrentUserId);
        var hasil = await _importService.GetBatchAsync(batchId);
        return Ok(hasil);
    }

    [HttpGet("{batchId:int}")]
    public async Task<IActionResult> GetBatch(int batchId)
    {
        var hasil = await _importService.GetBatchAsync(batchId);
        if (hasil.Batch is null) return NotFound();
        return Ok(hasil);
    }

    [HttpGet("batches")]
    public async Task<IActionResult> GetBatches()
    {
        var order = await _orderService.GetAktifAsync();
        if (order is null) return Ok(new List<TerakarsaApp.Shared.Tni.TniImportBatchDto>());

        var list = await _importService.GetBatchListAsync(order.OrderId);
        return Ok(list);
    }

    [HttpPost("{batchId:int}/commit")]
    public async Task<IActionResult> Commit(int batchId)
    {
        var (success, error, hasil) = await _importService.CommitAsync(batchId, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(hasil);
    }
}

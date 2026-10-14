using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Prompt 75: laporan module Stok Benang (riwayat, ringkasan, pemakaian, export).
// READ-ONLY -- module yang sama (INV_THREAD), jadi owner/Admin sudah bisa akses.
[ApiController]
[Route("api/gudang/benang")]
[Authorize]
[RequireModule("INV_THREAD")]
public class ThreadReportController : ControllerBase
{
    private const string XlsxContentType =
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    private readonly ThreadReportService _reportService;

    public ThreadReportController(ThreadReportService reportService)
    {
        _reportService = reportService;
    }

    // movementTypes: dipisah koma, mis. "ISSUE,ADJUST".
    [HttpGet("movements")]
    public async Task<IActionResult> Movements(
        [FromQuery] DateTime? dari = null,
        [FromQuery] DateTime? sampai = null,
        [FromQuery] string? movementTypes = null,
        [FromQuery] string? reasonCode = null,
        [FromQuery] int? itemId = null,
        [FromQuery] int? locationId = null,
        [FromQuery] int? resourceId = null,
        [FromQuery] int? projectId = null,
        [FromQuery] int? createdBy = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 50)
    {
        if (pageNumber < 1) pageNumber = 1;
        if (pageSize is < 1 or > 200) pageSize = 50;

        return Ok(await _reportService.GetMovementsAsync(dari, sampai, movementTypes, reasonCode,
            itemId, locationId, resourceId, projectId, createdBy, pageNumber, pageSize));
    }

    [HttpGet("movements/export")]
    public async Task<IActionResult> ExportMovements(
        [FromQuery] DateTime? dari = null,
        [FromQuery] DateTime? sampai = null,
        [FromQuery] string? movementTypes = null,
        [FromQuery] string? reasonCode = null,
        [FromQuery] int? itemId = null,
        [FromQuery] int? locationId = null,
        [FromQuery] int? resourceId = null,
        [FromQuery] int? projectId = null,
        [FromQuery] int? createdBy = null)
    {
        var bytes = await _reportService.ExportMovementsAsync(dari, sampai, movementTypes, reasonCode,
            itemId, locationId, resourceId, projectId, createdBy);

        var nama = $"riwayat-benang-{DateTime.Now:yyyyMMdd-HHmm}.xlsx";
        return File(bytes, XlsxContentType, nama);
    }

    [HttpGet("summary")]
    public async Task<IActionResult> Summary() => Ok(await _reportService.GetSummaryAsync());

    [HttpGet("stocks/by-location")]
    public async Task<IActionResult> ByLocation() => Ok(await _reportService.GetByLocationAsync());

    [HttpGet("usage/by-project")]
    public async Task<IActionResult> UsageByProject(
        [FromQuery] int? projectId = null,
        [FromQuery] DateTime? dari = null,
        [FromQuery] DateTime? sampai = null)
        => Ok(await _reportService.GetUsageByProjectAsync(projectId, dari, sampai));

    [HttpGet("usage/by-project/export")]
    public async Task<IActionResult> ExportUsage(
        [FromQuery] int? projectId = null,
        [FromQuery] DateTime? dari = null,
        [FromQuery] DateTime? sampai = null)
    {
        var bytes = await _reportService.ExportUsageAsync(projectId, dari, sampai);
        var nama = $"pemakaian-benang-{DateTime.Now:yyyyMMdd-HHmm}.xlsx";
        return File(bytes, XlsxContentType, nama);
    }
}

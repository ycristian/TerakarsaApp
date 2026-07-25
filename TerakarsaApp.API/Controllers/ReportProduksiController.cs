using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Prompt 30: Laporan Produksi Periode Gajian -- murni read-only (module REPORT_PRODUKSI,
// halaman /reports/produksi). Endpoint reports/produksi/divisions memakai ulang
// DivisionService langsung (tanpa mengubah controller aslinya), pola sama dengan
// report-bundle-picker/* di ReportBundleController.
[ApiController]
[Route("api")]
[Authorize]
[RequireModule("REPORT_PRODUKSI")]
public class ReportProduksiController : ControllerBase
{
    private readonly ReportProduksiService _reportProduksiService;
    private readonly DivisionService _divisionService;

    public ReportProduksiController(ReportProduksiService reportProduksiService, DivisionService divisionService)
    {
        _reportProduksiService = reportProduksiService;
        _divisionService = divisionService;
    }

    [HttpGet("reports/produksi")]
    public async Task<IActionResult> GetReport(
        [FromQuery] int divisionId, [FromQuery] int? resourceId,
        [FromQuery] DateTime periodStart, [FromQuery] DateTime periodEnd)
    {
        if (divisionId <= 0) return BadRequest("Divisi wajib dipilih.");
        if (periodEnd <= periodStart) return BadRequest("Periode tidak valid.");

        var result = await _reportProduksiService.GetReportAsync(divisionId, resourceId, periodStart, periodEnd);
        return Ok(result);
    }

    [HttpGet("reports/produksi/resources")]
    public async Task<IActionResult> GetResources([FromQuery] int divisionId)
    {
        if (divisionId <= 0) return BadRequest("Divisi wajib dipilih.");

        var result = await _reportProduksiService.GetResourcesAsync(divisionId);
        return Ok(result);
    }

    [HttpGet("reports/produksi/divisions")]
    public async Task<IActionResult> GetDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }
}

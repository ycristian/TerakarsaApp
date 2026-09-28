using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Reports;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Controllers;

// Prompt 47: Modul Log Aktivitas -- murni read-only (module REPORT_ACTIVITY, halaman
// /activity-log). Endpoint activity-log-picker/* memakai ulang DivisionService/
// ResourceService/EmployeeService langsung (tanpa mengubah controller aslinya), pola sama
// dengan report-bundle-picker/* di ReportBundleController. Fix: tombol "Cetak Kupon" per
// baris -- memakai ulang WorkflowLogService.PrintHasilAsync (SIS_WorkflowLog_PrintHasil),
// SP/service yang sama dengan tombol "Print Hasil" di BundleScanCard, tidak ada SP baru.
// Fix: kartu "Rekap Produksi" -- memakai ulang RekapProduksiService (SIS_Report_RekapStruk /
// SIS_Report_RekapStrukPrint), SP/service yang sama dengan tab Rekap Produksi di
// StationDeviceController, hanya beda actor (CurrentUserId user login, bukan system user
// stasiun) dan endpoint (JWT, bukan X-Station-Token).
[ApiController]
[Route("api")]
[Authorize]
[RequireModule("REPORT_ACTIVITY")]
public class ReportActivityLogController : ControllerBase
{
    private readonly ReportActivityLogService _reportActivityLogService;
    private readonly DivisionService _divisionService;
    private readonly ResourceService _resourceService;
    private readonly EmployeeService _employeeService;
    private readonly WorkflowLogService _workflowLogService;
    private readonly RekapProduksiService _rekapProduksiService;

    public ReportActivityLogController(
        ReportActivityLogService reportActivityLogService,
        DivisionService divisionService,
        ResourceService resourceService,
        EmployeeService employeeService,
        WorkflowLogService workflowLogService,
        RekapProduksiService rekapProduksiService)
    {
        _reportActivityLogService = reportActivityLogService;
        _divisionService = divisionService;
        _resourceService = resourceService;
        _employeeService = employeeService;
        _workflowLogService = workflowLogService;
        _rekapProduksiService = rekapProduksiService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("reports/activity-log")]
    public async Task<IActionResult> GetActivityLog([FromQuery] ActivityLogPagedRequest request)
    {
        if (request.DateTo < request.DateFrom) return BadRequest("Rentang tanggal tidak valid.");

        var result = await _reportActivityLogService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("reports/activity-log-picker/divisions")]
    public async Task<IActionResult> GetDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("reports/activity-log-picker/divisions/{divisionId:int}/resources")]
    public async Task<IActionResult> GetResources(int divisionId)
    {
        var result = await _resourceService.GetActiveByDivisionAsync(divisionId);
        return Ok(result);
    }

    [HttpGet("reports/activity-log-picker/divisions/{divisionId:int}/employees")]
    public async Task<IActionResult> GetEmployees(int divisionId)
    {
        var result = await _employeeService.GetActiveByDivisionAsync(divisionId);
        return Ok(result);
    }

    // Fix: "Cetak Kupon" -- tombol per baris (kolom paling kiri tabel), tombol client hanya
    // tampil kalau baris itu punya PrintKupon = 1 (SP menegakkan ulang lewat print_kupon step).
    [HttpPost("reports/activity-log/workflow-logs/{id:int}/print-kupon")]
    public async Task<IActionResult> PrintKupon(int id)
    {
        var (success, error, printJobId) = await _workflowLogService.PrintHasilAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    // Fix: dropdown "Penjahit" di kartu Rekap Produksi -- cascading dari RESOURCE (bukan
    // Divisi, beda dari dropdown Employee filter utama di atas), pola sama dengan tab Rekap
    // Produksi station (SIS_Employee_GetActiveByResource, sudah ada sejak Prompt 32).
    [HttpGet("reports/activity-log-picker/resources/{resourceId:int}/employees")]
    public async Task<IActionResult> GetEmployeesByResource(int resourceId)
    {
        var result = await _employeeService.GetActiveByResourceAsync(resourceId);
        return Ok(result);
    }

    // Fix: kartu "Rekap Produksi" -- header + detail harian + WIP snapshot, level = pilihan
    // terdalam yang diisi client (DIVISION | RESOURCE | EMPLOYEE), sama seperti tab Rekap
    // Produksi station.
    [HttpGet("reports/activity-log/rekap-struk")]
    public async Task<IActionResult> GetRekapStruk(
        [FromQuery] string level, [FromQuery] int divisionId, [FromQuery] int? resourceId,
        [FromQuery] int? employeeId, [FromQuery] DateTime? date)
    {
        // Kartu ini tetap SATU HARI (bukan rentang jam spt tab Rekap Produksi /station) --
        // date dikonversi ke rentang 00:00 s/d 00:00 hari berikutnya.
        DateTime? startDateTime = date?.Date;
        DateTime? endDateTime = date?.Date.AddDays(1);
        var result = await _rekapProduksiService.GetAsync(level, divisionId, resourceId, employeeId, startDateTime, endDateTime);
        if (result.Header is null) return NotFound("Divisi tidak ditemukan.");
        return Ok(result);
    }

    [HttpPost("reports/activity-log/rekap-struk/print")]
    public async Task<IActionResult> PrintRekapStruk([FromBody] RekapStrukPrintRequest request)
    {
        var (success, error, printJobId) = await _rekapProduksiService.PrintAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    // Fix: "Cetak Karyawan" -- tombol baru terpisah, muncul hanya kalau checkbox "Print
    // Karyawan" dicentang di client (SIS_Report_RekapKaryawanPrint, satu hari, breakdown Line >
    // Karyawan > PO > Bundle).
    [HttpPost("reports/activity-log/rekap-karyawan/print")]
    public async Task<IActionResult> PrintRekapKaryawan([FromBody] RekapKaryawanPrintRequest request)
    {
        var (success, error, printJobId) = await _rekapProduksiService.PrintKaryawanAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }
}

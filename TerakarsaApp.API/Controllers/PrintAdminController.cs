using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.API.Controllers;

// Prompt 77: pengelolaan device cetak & routing job_type.
//
// Dipisah dari PrintController karena autentikasinya BERBEDA: di sini JWT user biasa
// (admin gudang / Admin), sedangkan PrintController dipakai mesin pencetak lewat
// API key / device token.
[ApiController]
[Route("api/print")]
[Authorize]
public class PrintAdminController : ControllerBase
{
    private readonly PrintDeviceService _deviceService;

    public PrintAdminController(PrintDeviceService deviceService)
    {
        _deviceService = deviceService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    // Dipanggil app Android saat admin gudang mendaftarkan HP-nya sebagai pencetak.
    // device_token hanya dikembalikan di sini (sekali) -- app menyimpannya di SecureStorage.
    [HttpPost("devices/register-mobile")]
    [RequireModule("INV_THREAD")]
    public async Task<IActionResult> RegisterMobile([FromBody] PrintDeviceRegisterRequest request)
    {
        var (success, error, hasil) = await _deviceService.RegisterMobileAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(hasil);
    }

    [HttpGet("devices/mobile")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> MobileDevices() => Ok(await _deviceService.GetMobileDevicesAsync());

    [HttpGet("devices")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Devices() => Ok(await _deviceService.GetAllDevicesAsync());

    [HttpGet("routes")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Routes() => Ok(await _deviceService.GetRoutesAsync());

    // Prompt 88: request membawa daftar LENGKAP device tujuan (multi-pilih).
    [HttpPut("routes")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> SetRoute([FromBody] PrintJobRouteSetRequest request)
    {
        var (success, error) = await _deviceService.SetRouteAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // ==================== Prompt 88 ====================

    // PrinterPicker untuk user login biasa (Kelola Bundle, Admin Cutting, Super Admin).
    // Perangkat station memakai GET api/station/printers (header X-Station-Token).
    [HttpGet("devices/for-job")]
    public async Task<IActionResult> DevicesForJob([FromQuery] string jobType)
    {
        if (string.IsNullOrWhiteSpace(jobType)) return BadRequest("jobType wajib diisi.");
        return Ok(await _deviceService.GetForJobTypeAsync(jobType));
    }

    [HttpPost("devices")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> CreateDevice([FromBody] PrintDeviceSaveRequest request)
    {
        var (success, error, id) = await _deviceService.SaveDeviceAsync(null, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintDeviceId = id });
    }

    [HttpPut("devices/{id:int}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateDevice(int id, [FromBody] PrintDeviceSaveRequest request)
    {
        var (success, error, _) = await _deviceService.SaveDeviceAsync(id, request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Job TEST_PRINT langsung ke device PC ini (tanpa route).
    [HttpPost("devices/{id:int}/test-print")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> TestPrint(int id)
    {
        var (success, error, printJobId) = await _deviceService.TestPrintAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }
}

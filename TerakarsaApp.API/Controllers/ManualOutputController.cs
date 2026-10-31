using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.ManualOutputs;

namespace TerakarsaApp.API.Controllers;

// Prompt 83: halaman admin "Output Manual" (module MANUAL_OUTPUT, halaman /manual-outputs).
//
// Dua hal saja: melihat semua baris manual_outputs dengan filter, dan menempelkan artikel
// secara massal. TIDAK ADA endpoint harga di sini -- koreksi harga ada di
// PayrollRekapController (module PAYROLL_REKAP), supaya hak lihat daftar output tidak
// otomatis berarti hak mengubah nominal upah.
//
// Pencatatan/penghapusan baris TETAP milik stasiun (StationDeviceController) -- admin tidak
// membuat output manual atas nama divisi lain.
//
// @UserId = user login dari JWT, berbeda dari sisi stasiun yang memakai user sistem
// station_system. Dropdown divisi & pencarian artikel memakai ulang service yang sudah ada
// (pola sama dengan UnlockRequestController), tanpa SP baru.
[ApiController]
[Route("api/manual-outputs")]
[Authorize]
[RequireModule("MANUAL_OUTPUT")]
public class ManualOutputController : ControllerBase
{
    private readonly ManualOutputService _manualOutputService;
    private readonly DivisionService _divisionService;
    private readonly ArticleService _articleService;

    public ManualOutputController(
        ManualOutputService manualOutputService,
        DivisionService divisionService,
        ArticleService articleService)
    {
        _manualOutputService = manualOutputService;
        _divisionService = divisionService;
        _articleService = articleService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<IActionResult> GetList(
        [FromQuery] bool onlyUnlinked = false,
        [FromQuery] int? divisionId = null,
        [FromQuery] int? payrollPeriodId = null,
        [FromQuery] int? resourceId = null,
        [FromQuery] string? search = null)
    {
        var result = await _manualOutputService.GetAdminListAsync(
            onlyUnlinked, divisionId, payrollPeriodId, resourceId, search);
        return Ok(result);
    }

    [HttpGet("divisions")]
    public async Task<IActionResult> GetDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }

    // Pencarian artikel untuk SearchableSelect "Hubungkan ke Artikel" (TOP 20, lintas PO).
    [HttpGet("articles")]
    public async Task<IActionResult> SearchArticles([FromQuery] string? q)
    {
        if (string.IsNullOrWhiteSpace(q)) return Ok(new List<object>());
        var result = await _articleService.SearchAsync(q.Trim());
        return Ok(result);
    }

    // Aksi massal. Boleh untuk baris yang sudah lock -- menempelkan artikel tidak mengubah
    // fakta qty. Kalau baris itu sudah lock dan harganya masih kosong, SP ikut mengisinya
    // dari tarif artikel (tanpa menimpa harga yang sudah ada).
    [HttpPost("link-article")]
    public async Task<IActionResult> LinkArticle([FromBody] ManualOutputLinkArticleRequest request)
    {
        if (request is null || request.ManualOutputIds.Count == 0)
            return BadRequest("Pilih minimal satu baris output manual.");

        if (request.ArticleId <= 0)
            return BadRequest("Artikel wajib dipilih.");

        var (result, error) = await _manualOutputService.LinkArticleAsync(
            request.ManualOutputIds, request.ArticleId, CurrentUserId);

        if (result is null) return BadRequest(error);
        return Ok(result);
    }
}

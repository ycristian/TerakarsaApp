using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Cutting;

namespace TerakarsaApp.API.Controllers;

// Prompt 78-80: module Cutting. Dipakai Admin Cutting lewat TABLET dengan LOGIN
// (akun, bukan perangkat/station) -- created_by selalu user yang login.
// Pengambilan bundle oleh Bundling TIDAK di sini: itu dari perangkat station tanpa
// login (header X-Station-Token) -> StationDeviceController.
[ApiController]
[Route("api/cutting")]
[Authorize]
[RequireModule("CUTTING")]
public class CuttingController : ControllerBase
{
    private readonly CuttingService _cutting;

    public CuttingController(CuttingService cutting)
    {
        _cutting = cutting;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    private IActionResult Hasil((bool Success, string Error) r)
        => r.Success ? Ok() : BadRequest(new { message = r.Error });

    // ==================== dropdown & hitungan ====================

    [HttpGet("articles")]
    public async Task<IActionResult> GetArticles()
        => Ok(await _cutting.GetArticlesAsync());

    [HttpGet("articles/{articleId:int}/sizes")]
    public async Task<IActionResult> GetArticleSizes(int articleId)
        => Ok(await _cutting.GetArticleSizesAsync(articleId));

    [HttpGet("articles/{articleId:int}/next-code")]
    public async Task<IActionResult> GetNextSpreadCode(int articleId)
        => Ok(new { nextCode = await _cutting.GetNextSpreadCodeAsync(articleId) });

    [HttpGet("next-number")]
    public async Task<IActionResult> GetNextNumber([FromQuery] int articleId, [FromQuery] int articleSizeId)
        => Ok(new { nextFrom = await _cutting.GetNextNumberAsync(articleId, articleSizeId) });

    [HttpPost("suggest")]
    public async Task<IActionResult> Suggest([FromBody] CuttingSuggestRequest request)
        => Ok(await _cutting.SuggestBundlesAsync(request.Sheets, request.Target));

    // ==================== stok bundle ====================

    [HttpGet("stock")]
    public async Task<IActionResult> GetStock()
        => Ok(await _cutting.GetStockSummaryAsync());

    [HttpGet("taken-today")]
    public async Task<IActionResult> GetTakenToday()
        => Ok(await _cutting.GetTakenTodayAsync());

    // ==================== hamparan ====================

    [HttpGet("spreads")]
    public async Task<IActionResult> GetSpreads(
        [FromQuery] int? articleId, [FromQuery] string? status,
        [FromQuery] DateTime? dateFrom, [FromQuery] DateTime? dateTo)
        => Ok(await _cutting.GetSpreadsAsync(articleId, status, dateFrom, dateTo));

    [HttpGet("spreads/{id:int}")]
    public async Task<IActionResult> GetSpread(int id)
    {
        var detail = await _cutting.GetSpreadDetailAsync(id);
        return detail is null ? NotFound() : Ok(detail);
    }

    [HttpPost("spreads")]
    public async Task<IActionResult> CreateSpread([FromBody] SpreadCreateRequest request)
    {
        var (success, error, hasil) = await _cutting.CreateSpreadAsync(request, CurrentUserId);
        return success ? Ok(hasil) : BadRequest(new { message = error, hasil });
    }

    [HttpPut("spreads/{id:int}")]
    public async Task<IActionResult> UpdateSpreadHeader(int id, [FromBody] SpreadHeaderUpdateRequest request)
        => Hasil(await _cutting.UpdateSpreadHeaderAsync(id, request, CurrentUserId));

    [HttpDelete("spreads/{id:int}")]
    public async Task<IActionResult> DeleteSpread(int id)
        => Hasil(await _cutting.DeleteSpreadAsync(id, CurrentUserId));

    // bundleIds kosong = cetak semua bundle hamparan (sekalian MARK_PRINTED).
    [HttpPost("spreads/{id:int}/print")]
    public async Task<IActionResult> PrintSpread(int id, [FromBody] List<int>? bundleIds)
    {
        var (success, error, jobs) = await _cutting.PrintAsync(id, bundleIds, CurrentUserId);
        return success ? Ok(new { jobCount = jobs }) : BadRequest(new { message = error });
    }

    // ==================== bundle di dalam set ====================

    // Qty baru SELURUH bundle di satu set (total harus = lembar per set -- ditegakkan di SP).
    [HttpPut("spreads/{id:int}/bundles/qty")]
    public async Task<IActionResult> UpdateBundleQty(int id, [FromBody] SpreadBundleSaveRequest request)
        => Hasil(await _cutting.UpdateBundleQtyAsync(request.Bundles, CurrentUserId));

    [HttpPost("spreads/{id:int}/bundles")]
    public async Task<IActionResult> AddBundle(int id, [FromBody] SpreadBundleAddRequest request)
        => Hasil(await _cutting.AddBundleAsync(request, CurrentUserId));

    [HttpDelete("spreads/{id:int}/bundles/{bundleId:int}")]
    public async Task<IActionResult> RemoveBundle(int id, int bundleId, [FromBody] SpreadBundleRemoveRequest? request)
        => Hasil(await _cutting.RemoveBundleAsync(bundleId, request?.Bundles ?? new(), CurrentUserId));
}

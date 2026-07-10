using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Bundles;

namespace TerakarsaApp.API.Controllers;

// Endpoint publik, tanpa autentikasi sama sekali (JWT atau X-Station-Token) — dibuka
// untuk siapa pun yang men-scan label QR bundle (link di label = {PublicBaseUrl}/b/{serial})
// tanpa perangkat stasiun aktif. HANYA GET, read-only, tidak ada endpoint tulis di sini.
[ApiController]
[Route("api/public")]
public class PublicController : ControllerBase
{
    private readonly BundleService _bundleService;

    public PublicController(BundleService bundleService)
    {
        _bundleService = bundleService;
    }

    [HttpGet("bundles/{serial}")]
    public async Task<IActionResult> GetBundle(string serial)
    {
        var scanInfo = await _bundleService.GetScanInfoAsync(serial, null, null);
        if (scanInfo is null) return NotFound("Bundle tidak ditemukan.");

        var wip = await _bundleService.GetArticleWipAsync(scanInfo.Bundle.ArticleId);

        return Ok(new PublicBundleDetailDto { ScanInfo = scanInfo, Wip = wip });
    }
}

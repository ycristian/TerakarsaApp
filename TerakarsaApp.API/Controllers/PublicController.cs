using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.API.Controllers;

// Endpoint publik, tanpa autentikasi sama sekali (JWT atau X-Station-Token) — dibuka
// untuk siapa pun yang men-scan label QR bundle (link di label = {PublicBaseUrl}/b/{serial})
// tanpa perangkat stasiun aktif. HANYA GET, read-only, tidak ada endpoint tulis di sini.
[ApiController]
[Route("api/public")]
public class PublicController : ControllerBase
{
    private readonly BundleService _bundleService;
    private readonly PackService _packService;
    private readonly TniScanService _scanService;

    public PublicController(BundleService bundleService, PackService packService, TniScanService scanService)
    {
        _bundleService = bundleService;
        _packService = packService;
        _scanService = scanService;
    }

    // Fix: /b/{Serial} publik menerima format "{huruf}{nomor}" (mis. "D347") juga, bukan cuma
    // serial asli -- client cek 0/1/>1 hasil (kalau >1, tampilkan pilihan project dulu).
    [HttpGet("bundles/lookup-by-no")]
    public async Task<IActionResult> LookupBundleByNo([FromQuery] string bundleLetter, [FromQuery] int bundleNo)
    {
        if (string.IsNullOrWhiteSpace(bundleLetter) || bundleLetter.Trim().Length != 1 || bundleNo <= 0)
            return BadRequest("Format No. Bundle tidak valid.");

        var result = await _bundleService.LookupByLetterNoAsync(bundleLetter.Trim().ToUpperInvariant(), bundleNo);
        return Ok(result);
    }

    [HttpGet("bundles/{serial}")]
    public async Task<IActionResult> GetBundle(string serial)
    {
        var scanInfo = await _bundleService.GetScanInfoAsync(serial, null, null);
        if (scanInfo is null) return NotFound("Bundle tidak ditemukan.");

        var wip = await _bundleService.GetArticleWipAsync(scanInfo.Bundle.ArticleId);

        return Ok(new PublicBundleDetailDto { ScanInfo = scanInfo, Wip = wip });
    }

    // Prompt 25: link QR label karung = {PublicBaseUrl}/pack/{serial}.
    [HttpGet("packs/{serial}")]
    public async Task<IActionResult> GetPack(string serial)
    {
        var scanInfo = await _packService.GetScanInfoAsync(serial);
        if (scanInfo is null) return NotFound("Karung tidak ditemukan.");
        return Ok(scanInfo);
    }

    // Prompt 66: link QR kartu personel PDH TNI AD = {Tni:QrBaseUrl}/t/{qr_token}.
    // HANYA data terbatas -- sejak 2026-10-06 owner mengizinkan NRP, size, TB/BB,
    // kategori, rawatan; No HP & ukuran badan TETAP tidak, karena halaman ini bisa
    // dibuka siapa pun dari internet. Token dipakai (bukan
    // kode_ref) justru karena kode_ref berurutan sehingga mudah ditebak.
    [HttpGet("tni/{token}")]
    public async Task<IActionResult> GetTniPersonel(string token)
    {
        var personel = await _scanService.GetPublicByTokenAsync(token);
        if (personel is null) return NotFound("Kartu tidak ditemukan.");
        return Ok(personel);
    }
}

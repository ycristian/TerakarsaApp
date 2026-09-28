using System.Net.Http.Json;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.Client.Services;

// Dipakai oleh halaman publik /b/{serial} saat perangkat TIDAK punya station token
// (pengunjung tanpa login). Memakai HttpClient "API" biasa (tanpa token JWT ataupun
// X-Station-Token) — endpoint api/public/* memang tidak butuh autentikasi sama sekali.
public class PublicBundleApiService
{
    private readonly HttpClient _http;

    public PublicBundleApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<PublicBundleDetailDto?> GetBundleAsync(string serial)
    {
        var response = await _http.GetAsync($"api/public/bundles/{Uri.EscapeDataString(serial)}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<PublicBundleDetailDto>();
    }

    // Fix: /b/{Serial} publik menerima format "{huruf}{nomor}" (mis. "D347") juga.
    public async Task<List<BundleLookupMatchDto>> LookupByNoAsync(string bundleLetter, int bundleNo)
    {
        var response = await _http.GetAsync($"api/public/bundles/lookup-by-no?bundleLetter={Uri.EscapeDataString(bundleLetter)}&bundleNo={bundleNo}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<BundleLookupMatchDto>>() ?? new();
    }
}

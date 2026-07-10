using System.Net.Http.Json;
using TerakarsaApp.Shared.Bundles;

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
}

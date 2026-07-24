using System.Net.Http.Json;
using TerakarsaApp.Shared.Packs;

namespace TerakarsaApp.Client.Services;

// Dipakai oleh halaman publik /pack/{serial} saat perangkat TIDAK punya station token
// (pengunjung tanpa login). Memakai HttpClient "API" biasa -- api/public/packs/{serial}
// tidak butuh autentikasi sama sekali. Pola sama dengan PublicBundleApiService.
public class PublicPackApiService
{
    private readonly HttpClient _http;

    public PublicPackApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<PackScanInfoDto?> GetPackAsync(string serial)
    {
        var response = await _http.GetAsync($"api/public/packs/{Uri.EscapeDataString(serial)}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<PackScanInfoDto>();
    }
}

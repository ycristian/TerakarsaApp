using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 66: dipakai halaman publik /t/{token} saat pengunjung BELUM login.
// Memakai HttpClient "API" biasa -- endpoint api/public/* memang tidak butuh
// autentikasi, dan hanya mengembalikan data terbatas (tanpa No HP / ukuran badan).
public class TniPublicApiService
{
    private readonly HttpClient _http;

    public TniPublicApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<TniPublicPersonelDto?> GetByTokenAsync(string token)
    {
        var response = await _http.GetAsync($"api/public/tni/{Uri.EscapeDataString(token)}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniPublicPersonelDto>();
    }

    // Komplain ukuran -- TANPA login / perangkat (2026-10-06).
    public async Task<(bool Success, string Error)> KirimKomplainAsync(string token, TniKomplainRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/tni/komplain/{Uri.EscapeDataString(token)}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan komplain." : error.Trim('"'));
    }
}

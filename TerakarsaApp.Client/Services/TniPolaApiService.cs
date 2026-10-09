using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 61: master pola PDH TNI AD. jenis = "KEMEJA" atau "CELANA".
public class TniPolaApiService
{
    private readonly HttpClient _http;

    public TniPolaApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<TniPolaDto>> GetListAsync(string jenis, string? search = null, bool hanyaAktif = false)
    {
        var url = $"api/tni/pola?jenis={jenis}&hanyaAktif={hanyaAktif.ToString().ToLowerInvariant()}";
        if (!string.IsNullOrWhiteSpace(search))
            url += $"&search={Uri.EscapeDataString(search)}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniPolaDto>>() ?? new();
    }

    public async Task<TniPolaDto?> GetByIdAsync(string jenis, int id)
    {
        var response = await _http.GetAsync($"api/tni/pola/{jenis}/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniPolaDto>();
    }

    public async Task<(bool Success, string Error)> SaveAsync(TniPolaSaveRequest request)
    {
        var response = request.PolaId.HasValue
            ? await _http.PutAsJsonAsync($"api/tni/pola/{request.JenisItem}/{request.PolaId.Value}", request)
            : await _http.PostAsJsonAsync("api/tni/pola", request);

        return await ReadResultAsync(response);
    }

    public async Task<(bool Success, string Error)> SetAktifAsync(string jenis, int id, bool isActive)
    {
        var response = await _http.PutAsJsonAsync(
            $"api/tni/pola/{jenis}/{id}/aktif", new TniPolaSetAktifRequest { IsActive = isActive });

        return await ReadResultAsync(response);
    }

    public async Task<(bool Success, string Error)> DeleteAsync(string jenis, int id)
    {
        var response = await _http.DeleteAsync($"api/tni/pola/{jenis}/{id}");
        return await ReadResultAsync(response);
    }

    private static async Task<(bool Success, string Error)> ReadResultAsync(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }
}

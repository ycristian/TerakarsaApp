using System.Net.Http.Json;
using TerakarsaApp.Shared.Dashboards;

namespace TerakarsaApp.Client.Services;

// Dipakai khusus oleh halaman kiosk /tv-dashboard (tanpa login). HttpClient-nya disuntikkan
// lewat typed client "DashboardAPI" yang memakai DashboardTokenHandler, BUKAN HttpClient
// JWT biasa yang dipakai *ApiService lain.
public class DashboardApiService
{
    private readonly HttpClient _http;

    public DashboardApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<(bool Success, DashboardMeDto? Result)> GetMeAsync()
    {
        var response = await _http.GetAsync("api/dashboard/me");
        if (!response.IsSuccessStatusCode) return (false, null);
        return (true, await response.Content.ReadFromJsonAsync<DashboardMeDto>());
    }

    public async Task<(bool Success, DashboardTargetHarianResult? Result)> GetTargetHarianAsync(DateTime? date)
    {
        var query = date.HasValue ? $"?date={date.Value:yyyy-MM-dd}" : string.Empty;
        var response = await _http.GetAsync($"api/dashboard/target-harian{query}");
        if (!response.IsSuccessStatusCode) return (false, null);
        return (true, await response.Content.ReadFromJsonAsync<DashboardTargetHarianResult>());
    }
}

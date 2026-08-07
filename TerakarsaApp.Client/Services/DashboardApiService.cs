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

    // Prompt 45: modal drill-down per line. Prompt 51: resourceId opsional -- null = mode divisi.
    private static string ResourceQuery(int? resourceId) => resourceId.HasValue ? $"&resourceId={resourceId.Value}" : string.Empty;

    public async Task<(bool Success, List<LineEmployeeProgressDto> Result)> GetLineEmployeeProgressAsync(int divisionId, int? resourceId, DateTime tanggal)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/employees?divisionId={divisionId}{ResourceQuery(resourceId)}&tanggal={tanggal:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return (false, new());
        return (true, await response.Content.ReadFromJsonAsync<List<LineEmployeeProgressDto>>() ?? new());
    }

    public async Task<(bool Success, List<LineActiveBundleDto> Result)> GetLineActiveBundlesAsync(int divisionId, int? resourceId)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/bundles?divisionId={divisionId}{ResourceQuery(resourceId)}");
        if (!response.IsSuccessStatusCode) return (false, new());
        return (true, await response.Content.ReadFromJsonAsync<List<LineActiveBundleDto>>() ?? new());
    }

    // Prompt 52: tab "Transit".
    public async Task<(bool Success, List<LineTransitBundleDto> Result)> GetLineTransitBundlesAsync(int divisionId, int? resourceId)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/transit?divisionId={divisionId}{ResourceQuery(resourceId)}");
        if (!response.IsSuccessStatusCode) return (false, new());
        return (true, await response.Content.ReadFromJsonAsync<List<LineTransitBundleDto>>() ?? new());
    }

    // Prompt 46: tab "Selesai" & "Reject" -- periode: "hari" / "7hari" / "gajian".
    public async Task<(bool Success, List<LineCompletedBundleDto> Result)> GetLineCompletedBundlesAsync(int divisionId, int? resourceId, string periode, DateTime tanggal)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/completed?divisionId={divisionId}{ResourceQuery(resourceId)}&periode={periode}&tanggal={tanggal:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return (false, new());
        return (true, await response.Content.ReadFromJsonAsync<List<LineCompletedBundleDto>>() ?? new());
    }

    public async Task<(bool Success, List<LineRejectBundleDto> Result)> GetLineRejectBundlesAsync(int divisionId, int? resourceId, string periode, DateTime tanggal)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/rejects?divisionId={divisionId}{ResourceQuery(resourceId)}&periode={periode}&tanggal={tanggal:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return (false, new());
        return (true, await response.Content.ReadFromJsonAsync<List<LineRejectBundleDto>>() ?? new());
    }

    // Prompt 51: tab "Tren" -- rentang: "14hari" / "30hari".
    public async Task<(bool Success, List<LineTrendDailyDto> Result)> GetLineTrendDailyAsync(int divisionId, int? resourceId, string rentang, DateTime tanggal)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/trend-daily?divisionId={divisionId}{ResourceQuery(resourceId)}&rentang={rentang}&tanggal={tanggal:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return (false, new());
        return (true, await response.Content.ReadFromJsonAsync<List<LineTrendDailyDto>>() ?? new());
    }

    public async Task<(bool Success, List<LineTrendWeeklyDto> Result)> GetLineTrendWeeklyAsync(int divisionId, int? resourceId, DateTime tanggal)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/trend-weekly?divisionId={divisionId}{ResourceQuery(resourceId)}&tanggal={tanggal:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return (false, new());
        return (true, await response.Content.ReadFromJsonAsync<List<LineTrendWeeklyDto>>() ?? new());
    }

    // Prompt 51: tab "Per Jam".
    public async Task<(bool Success, LineHourlyResult? Result)> GetLineHourlyAsync(int divisionId, int? resourceId, DateTime tanggal)
    {
        var response = await _http.GetAsync($"api/dashboard/line-detail/hourly?divisionId={divisionId}{ResourceQuery(resourceId)}&tanggal={tanggal:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return (false, null);
        return (true, await response.Content.ReadFromJsonAsync<LineHourlyResult>());
    }
}

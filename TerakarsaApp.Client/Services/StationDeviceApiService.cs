using System.Net.Http.Json;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Resources;
using TerakarsaApp.Shared.Stations;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.Client.Services;

// Dipakai khusus oleh halaman /station (perangkat, tanpa login). HttpClient-nya
// disuntikkan lewat typed client "StationDeviceAPI" yang memakai StationTokenHandler,
// BUKAN HttpClient JWT biasa yang dipakai *ApiService lain.
public class StationDeviceApiService
{
    private readonly HttpClient _http;

    public StationDeviceApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<StationMeDto?> GetMeAsync()
    {
        var response = await _http.GetAsync("api/station/me");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<StationMeDto>();
    }

    public async Task<List<ResourceLookupDto>> GetResourcesAsync()
    {
        var response = await _http.GetAsync("api/station/resources");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<List<StationPendingReceiveDto>> GetPendingReceivesAsync()
    {
        var response = await _http.GetAsync("api/station/pending-receives");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationPendingReceiveDto>>() ?? new();
    }

    public async Task<List<StationActiveWorkDto>> GetActiveWorkAsync()
    {
        var response = await _http.GetAsync("api/station/active-work");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationActiveWorkDto>>() ?? new();
    }

    public async Task<List<DivisionDto>> GetTargetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/station/target-divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> ReceiveAsync(StationReceiveRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/receive", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menerima." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> CompleteAsync(StationCompleteRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/complete", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyelesaikan." : error.Trim('"'));
    }
}

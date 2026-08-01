using System.Net.Http.Json;
using TerakarsaApp.Shared.WorkSchedules;

namespace TerakarsaApp.Client.Services;

public class WorkScheduleApiService
{
    private readonly HttpClient _http;

    public WorkScheduleApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<WorkScheduleDivisionDto>> GetDefaultsAsync()
    {
        var response = await _http.GetAsync("api/work-schedule/defaults");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<WorkScheduleDivisionDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> SaveDivisionScheduleAsync(int divisionId, SaveDivisionScheduleRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/work-schedule/defaults/{divisionId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<List<WorkBreakDto>> GetBreaksAsync()
    {
        var response = await _http.GetAsync("api/work-schedule/breaks");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<WorkBreakDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateBreakAsync(WorkBreakCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/work-schedule/breaks", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateBreakAsync(WorkBreakUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/work-schedule/breaks", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteBreakAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/work-schedule/breaks/{id}");
        return response.IsSuccessStatusCode;
    }
}

using System.Net.Http.Json;
using TerakarsaApp.Shared.DailyPlans;

namespace TerakarsaApp.Client.Services;

public class DailyPlanApiService
{
    private readonly HttpClient _http;

    public DailyPlanApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<DailyPlanGetByDateResult> GetByDateAsync(DateTime date)
    {
        var response = await _http.GetAsync($"api/daily-plan?date={date:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<DailyPlanGetByDateResult>() ?? new();
    }

    public async Task<(bool Success, string Error)> SaveAsync(int divisionId, DateTime date, SaveDailyPlanRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/daily-plan/{divisionId}?date={date:yyyy-MM-dd}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int divisionId, DateTime date)
    {
        var response = await _http.DeleteAsync($"api/daily-plan/{divisionId}?date={date:yyyy-MM-dd}");
        return response.IsSuccessStatusCode;
    }

    public async Task<(bool Success, string Error, int CopiedCount)> CopyAsync(DateTime sourceDate, DateTime targetDate)
    {
        var response = await _http.PostAsJsonAsync("api/daily-plan/copy", new CopyDailyPlanRequest
        {
            SourceDate = sourceDate,
            TargetDate = targetDate
        });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyalin rencana." : error.Trim('"'), 0);
        }

        var result = await response.Content.ReadFromJsonAsync<CopyDailyPlanResult>() ?? new();
        return (true, string.Empty, result.CopiedCount);
    }

    public async Task<List<DailyPlanDateSummaryDto>> GetDatesAsync(DateTime from, DateTime to)
    {
        var response = await _http.GetAsync($"api/daily-plan/dates?from={from:yyyy-MM-dd}&to={to:yyyy-MM-dd}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DailyPlanDateSummaryDto>>() ?? new();
    }
}

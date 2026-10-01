using System.Net.Http.Json;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.UnlockRequests;

namespace TerakarsaApp.Client.Services;

// Prompt 57: client untuk module UNLOCK_REQUEST (api/unlock-requests) -- daftar/detail pengajuan
// buka lock + keputusan Setujui/Tolak. Pesan error dari API (asalnya RAISERROR di SP)
// diteruskan apa adanya ke halaman.
public class UnlockRequestApiService
{
    private readonly HttpClient _http;

    public UnlockRequestApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<UnlockRequestListItemDto>> GetListAsync(
        string state, int? divisionId, DateTime? dateFrom, DateTime? dateTo)
    {
        var query = $"api/unlock-requests?state={Uri.EscapeDataString(state)}";
        if (divisionId.HasValue) query += $"&divisionId={divisionId.Value}";
        if (dateFrom.HasValue) query += $"&dateFrom={dateFrom.Value:yyyy-MM-dd}";
        if (dateTo.HasValue) query += $"&dateTo={dateTo.Value:yyyy-MM-dd}";

        var response = await _http.GetAsync(query);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<UnlockRequestListItemDto>>() ?? new();
    }

    public async Task<List<DivisionDto>> GetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/unlock-requests/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    public async Task<(UnlockRequestDetailDto? Detail, string Error)> GetDetailAsync(int id)
    {
        var response = await _http.GetAsync($"api/unlock-requests/{id}");
        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (null, string.IsNullOrWhiteSpace(error) ? "Gagal memuat pengajuan." : error.Trim('"'));
        }
        var detail = await response.Content.ReadFromJsonAsync<UnlockRequestDetailDto>();
        return (detail, string.Empty);
    }

    public async Task<(bool Success, string Error)> ApproveAsync(int id, string? adminNote)
    {
        var response = await _http.PostAsJsonAsync($"api/unlock-requests/{id}/approve",
            new UnlockRequestDecisionRequest { AdminNote = adminNote });
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyetujui pengajuan." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> RejectAsync(int id, string adminNote)
    {
        var response = await _http.PostAsJsonAsync($"api/unlock-requests/{id}/reject",
            new UnlockRequestDecisionRequest { AdminNote = adminNote });
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menolak pengajuan." : error.Trim('"'));
    }
}

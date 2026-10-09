using System.Net.Http.Json;
using TerakarsaApp.Shared.Positions;

namespace TerakarsaApp.Client.Services;

public class PositionApiService
{
    private readonly HttpClient _http;

    public PositionApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<PositionPagedResult> GetPagedAsync(PositionPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/position/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<PositionPagedResult>() ?? new();
    }

    public async Task<List<PositionDto>> GetActiveAsync()
    {
        var response = await _http.GetAsync("api/position/active");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PositionDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateAsync(PositionCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/position", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(PositionUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/position", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    // Prompt 58 (lanjutan): jabatan yang boleh dipakai satu divisi (cascading di form
    // Master Karyawan).
    public async Task<List<PositionDto>> GetByDivisionAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/position/by-division/{divisionId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PositionDto>>() ?? new();
    }

    // Prompt 58 (lanjutan): divisi yang sudah dipetakan ke jabatan ini -- dipakai form
    // Master Jabatan untuk mencentang ulang pilihan tersimpan.
    public async Task<List<int>> GetDivisionIdsAsync(int positionId)
    {
        var response = await _http.GetAsync($"api/position/{positionId}/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<int>>() ?? new();
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/position/{id}");
        return response.IsSuccessStatusCode;
    }
}

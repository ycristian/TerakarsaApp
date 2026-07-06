using System.Net.Http.Json;
using TerakarsaApp.Shared.Divisions;

namespace TerakarsaApp.Client.Services;

public class DivisionApiService
{
    private readonly HttpClient _http;

    public DivisionApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<DivisionPagedResult> GetPagedAsync(DivisionPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/division/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<DivisionPagedResult>() ?? new();
    }

    public async Task<List<DivisionDto>> GetActiveAsync()
    {
        var response = await _http.GetAsync("api/division/active");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateAsync(DivisionCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/division", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(DivisionUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/division", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/division/{id}");
        return response.IsSuccessStatusCode;
    }
}

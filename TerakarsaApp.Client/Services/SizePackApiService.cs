using System.Net.Http.Json;
using TerakarsaApp.Shared.SizePacks;

namespace TerakarsaApp.Client.Services;

public class SizePackApiService
{
    private readonly HttpClient _http;

    public SizePackApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<SizePackPagedResult> GetPagedAsync(SizePackPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/sizepack/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<SizePackPagedResult>() ?? new();
    }

    public async Task<List<SizePackDto>> GetActiveAsync()
    {
        var response = await _http.GetAsync("api/sizepack/active");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<SizePackDto>>() ?? new();
    }

    public async Task<SizePackDto?> GetByIdAsync(int id)
    {
        var response = await _http.GetAsync($"api/sizepack/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<SizePackDto>();
    }

    public async Task<(bool Success, string Error)> CreateAsync(SizePackCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/sizepack", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(SizePackUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/sizepack", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/sizepack/{id}");
        return response.IsSuccessStatusCode;
    }
}

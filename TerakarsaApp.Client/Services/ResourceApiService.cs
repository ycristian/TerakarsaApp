using System.Net.Http.Json;
using TerakarsaApp.Shared.Resources;

namespace TerakarsaApp.Client.Services;

public class ResourceApiService
{
    private readonly HttpClient _http;

    public ResourceApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ResourcePagedResult> GetPagedAsync(ResourcePagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/resource/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ResourcePagedResult>() ?? new();
    }

    public async Task<List<ResourceLookupDto>> GetActiveByDivisionAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/resource/active-by-division/{divisionId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateAsync(ResourceCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/resource", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ResourceUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/resource", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/resource/{id}");
        return response.IsSuccessStatusCode;
    }
}

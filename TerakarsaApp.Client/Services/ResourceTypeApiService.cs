using System.Net.Http.Json;
using TerakarsaApp.Shared.ResourceTypes;

namespace TerakarsaApp.Client.Services;

public class ResourceTypeApiService
{
    private readonly HttpClient _http;

    public ResourceTypeApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ResourceTypePagedResult> GetPagedAsync(ResourceTypePagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/resourcetype/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ResourceTypePagedResult>() ?? new();
    }

    public async Task<List<ResourceTypeDto>> GetActiveAsync()
    {
        var response = await _http.GetAsync("api/resourcetype/active");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceTypeDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateAsync(ResourceTypeCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/resourcetype", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ResourceTypeUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/resourcetype", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/resourcetype/{id}");
        return response.IsSuccessStatusCode;
    }
}

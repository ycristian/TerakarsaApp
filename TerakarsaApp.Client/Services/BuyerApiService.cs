using System.Net.Http.Json;
using TerakarsaApp.Shared.Buyers;

namespace TerakarsaApp.Client.Services;

public class BuyerApiService
{
    private readonly HttpClient _http;

    public BuyerApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<BuyerPagedResult> GetPagedAsync(BuyerPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/buyer/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<BuyerPagedResult>() ?? new();
    }

    public async Task<List<BuyerDto>> GetActiveAsync()
    {
        var response = await _http.GetAsync("api/buyer/active");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<BuyerDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateAsync(BuyerCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/buyer", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(BuyerUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/buyer", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/buyer/{id}");
        return response.IsSuccessStatusCode;
    }
}

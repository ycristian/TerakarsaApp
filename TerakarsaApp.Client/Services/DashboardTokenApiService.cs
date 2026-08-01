using System.Net.Http.Json;
using TerakarsaApp.Shared.Dashboards;

namespace TerakarsaApp.Client.Services;

public class DashboardTokenApiService
{
    private readonly HttpClient _http;

    public DashboardTokenApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<DashboardTokenPagedResult> GetPagedAsync(DashboardTokenPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/dashboard-tokens/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<DashboardTokenPagedResult>() ?? new();
    }

    public async Task<(bool Success, string Error, DashboardTokenCreateResult? Result)> CreateAsync(DashboardTokenCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/dashboard-tokens", request);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<DashboardTokenCreateResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuat token." : error.Trim('"'), null);
    }

    public async Task<(bool Success, string Error)> UpdateAsync(DashboardTokenUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/dashboard-tokens", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/dashboard-tokens/{id}");
        return response.IsSuccessStatusCode;
    }

    public async Task<(bool Success, string Error, DashboardTokenCreateResult? Result)> RegenerateAsync(int id)
    {
        var response = await _http.PostAsync($"api/dashboard-tokens/{id}/regenerate", null);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<DashboardTokenCreateResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuat ulang token." : error.Trim('"'), null);
    }

    public async Task<string?> GetLinkAsync(int id)
    {
        var response = await _http.GetAsync($"api/dashboard-tokens/{id}/link");
        if (!response.IsSuccessStatusCode) return null;
        var result = await response.Content.ReadFromJsonAsync<DashboardTokenLinkDto>();
        return result?.Link;
    }
}

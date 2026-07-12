using System.Net.Http.Json;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.Client.Services;

public class StationApiService
{
    private readonly HttpClient _http;

    public StationApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<StationPagedResult> GetPagedAsync(StationPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<StationPagedResult>() ?? new();
    }

    public async Task<(bool Success, string Error, StationTokenResult? Result)> CreateAsync(StationCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station", request);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<StationTokenResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'), null);
    }

    public async Task<(bool Success, string Error)> UpdateAsync(StationUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/station", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/station/{id}");
        return response.IsSuccessStatusCode;
    }

    public async Task<(bool Success, string Error, StationPairingResult? Result)> GeneratePairingCodeAsync(int id)
    {
        var response = await _http.PostAsync($"api/station/{id}/pairing-code", null);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<StationPairingResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuat kode pairing." : error.Trim('"'), null);
    }

    public async Task<(bool Success, string Error)> UnpairAsync(int id)
    {
        var response = await _http.PostAsync($"api/station/{id}/unpair", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal memutuskan perangkat." : error.Trim('"'));
    }
}

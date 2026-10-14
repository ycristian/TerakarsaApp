using System.Net.Http.Json;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.Client.Services;

// Prompt 74: stock opname benang (api/gudang/benang/opname).
public class ThreadOpnameApiService
{
    private readonly HttpClient _http;

    public ThreadOpnameApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ThreadOpnameCurrentDto> GetCurrentAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/opname/current");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ThreadOpnameCurrentDto>() ?? new();
    }

    public async Task<ThreadOpnameRakDto> GetLinesAsync(int sessionId, int? locationId = null)
    {
        var url = $"api/gudang/benang/opname/{sessionId}/lines";
        if (locationId.HasValue) url += $"?locationId={locationId.Value}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ThreadOpnameRakDto>() ?? new();
    }

    public async Task<List<ThreadOpnameProposalDto>> PreviewCloseAsync(int sessionId)
    {
        var response = await _http.GetAsync($"api/gudang/benang/opname/{sessionId}/preview-close");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadOpnameProposalDto>>() ?? new();
    }

    public async Task<ThreadOpnameDetailDto?> GetByIdAsync(int sessionId)
    {
        var response = await _http.GetAsync($"api/gudang/benang/opname/{sessionId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ThreadOpnameDetailDto>();
    }

    public async Task<List<ThreadOpnameSessionDto>> GetRiwayatAsync(int top = 50)
    {
        var response = await _http.GetAsync($"api/gudang/benang/opname/riwayat?top={top}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadOpnameSessionDto>>() ?? new();
    }

    public async Task<List<ThreadReasonCodeDto>> GetReasonCodesAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/opname/reason-codes");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadReasonCodeDto>>() ?? new();
    }

    public Task<(bool Success, string Error, int Id)> OpenAsync(ThreadOpnameOpenRequest request) =>
        PostAsync("api/gudang/benang/opname/open", request);

    public Task<(bool Success, string Error, int Id)> AddLineAsync(ThreadOpnameAddLineRequest request) =>
        PostAsync("api/gudang/benang/opname/add-line", request);

    public Task<(bool Success, string Error, int Id)> CountAsync(ThreadOpnameCountRequest request) =>
        PostAsync("api/gudang/benang/opname/count", request);

    public async Task<(bool Success, string Error, int Id)> LocationDoneAsync(int sessionId, int locationId)
    {
        var response = await _http.PostAsync(
            $"api/gudang/benang/opname/{sessionId}/location/{locationId}/done", null);
        return await BacaAsync(response);
    }

    public Task<(bool Success, string Error, int Id)> CloseAsync(ThreadOpnameCloseRequest request) =>
        PostAsync("api/gudang/benang/opname/close", request);

    public async Task<(bool Success, string Error, int Id)> CancelAsync(int sessionId)
    {
        var response = await _http.PostAsync($"api/gudang/benang/opname/{sessionId}/cancel", null);
        return await BacaAsync(response);
    }

    private async Task<(bool Success, string Error, int Id)> PostAsync<T>(string url, T body)
    {
        var response = await _http.PostAsJsonAsync(url, body);
        return await BacaAsync(response);
    }

    private static async Task<(bool Success, string Error, int Id)> BacaAsync(HttpResponseMessage response)
    {
        var text = (await response.Content.ReadAsStringAsync()).Trim().Trim('"');

        if (response.IsSuccessStatusCode)
        {
            int.TryParse(text, out var id);
            return (true, string.Empty, id);
        }

        return (false, string.IsNullOrWhiteSpace(text) ? "Terjadi kesalahan di server." : text, 0);
    }
}

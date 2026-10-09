using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 61: order aktif module PDH TNI AD.
public class TniOrderApiService
{
    private readonly HttpClient _http;

    public TniOrderApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<TniOrderAktifDto?> GetAktifAsync()
    {
        var response = await _http.GetAsync("api/tni/order/aktif");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniOrderAktifDto>();
    }
}

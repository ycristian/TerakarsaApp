using System.Net.Http.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.Client.Services;

// Prompt 77: halaman /admin/printer -- daftar device cetak (PC & HP) dan routing
// job_type. READ + satu mutasi (pindah route).
public class PrintAdminApiService
{
    private readonly HttpClient _http;

    public PrintAdminApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<PrintDeviceDto>> GetDevicesAsync()
    {
        var response = await _http.GetAsync("api/print/devices");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PrintDeviceDto>>() ?? new();
    }

    public async Task<List<PrintJobRouteDto>> GetRoutesAsync()
    {
        var response = await _http.GetAsync("api/print/routes");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PrintJobRouteDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> SetRouteAsync(string jobType, int printDeviceId)
    {
        var response = await _http.PutAsJsonAsync("api/print/routes",
            new PrintJobRouteSetRequest { JobType = jobType, PrintDeviceId = printDeviceId });

        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = (await response.Content.ReadAsStringAsync()).Trim().Trim('"');
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal memindahkan route." : error);
    }
}

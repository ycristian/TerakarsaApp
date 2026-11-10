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

    // Prompt 88: daftar LENGKAP device tujuan job type (multi-pilih).
    public async Task<(bool Success, string Error)> SetRouteAsync(string jobType, List<int> printDeviceIds)
    {
        var response = await _http.PutAsJsonAsync("api/print/routes",
            new PrintJobRouteSetRequest { JobType = jobType, PrintDeviceIds = printDeviceIds });

        if (response.IsSuccessStatusCode) return (true, string.Empty);
        return (false, await ErrorAsync(response, "Gagal menyimpan routing."));
    }

    // ==================== Prompt 88 ====================

    // PrinterPicker untuk user login (JWT). Station memakai StationDeviceApiService.GetPrintersAsync.
    public async Task<List<PrintDeviceOptionDto>> GetForJobTypeAsync(string jobType)
    {
        var response = await _http.GetAsync($"api/print/devices/for-job?jobType={Uri.EscapeDataString(jobType)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PrintDeviceOptionDto>>() ?? new();
    }

    // id null = tambah device baru.
    public async Task<(bool Success, string Error)> SaveDeviceAsync(int? id, PrintDeviceSaveRequest request)
    {
        var response = id.HasValue
            ? await _http.PutAsJsonAsync($"api/print/devices/{id.Value}", request)
            : await _http.PostAsJsonAsync("api/print/devices", request);

        if (response.IsSuccessStatusCode) return (true, string.Empty);
        return (false, await ErrorAsync(response, "Gagal menyimpan device."));
    }

    public async Task<(bool Success, string Error)> TestPrintAsync(int id)
    {
        var response = await _http.PostAsync($"api/print/devices/{id}/test-print", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        return (false, await ErrorAsync(response, "Gagal membuat test print."));
    }

    private static async Task<string> ErrorAsync(HttpResponseMessage response, string fallback)
    {
        var error = (await response.Content.ReadAsStringAsync()).Trim().Trim('"');
        return string.IsNullOrWhiteSpace(error) ? fallback : error;
    }
}

using System.Net.Http.Json;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Resources;
using TerakarsaApp.Shared.Stations;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.Client.Services;

// Dipakai khusus oleh halaman /station (perangkat, tanpa login). HttpClient-nya
// disuntikkan lewat typed client "StationDeviceAPI" yang memakai StationTokenHandler,
// BUKAN HttpClient JWT biasa yang dipakai *ApiService lain.
public class StationDeviceApiService
{
    private readonly HttpClient _http;

    public StationDeviceApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<StationMeDto?> GetMeAsync()
    {
        var response = await _http.GetAsync("api/station/me");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<StationMeDto>();
    }

    public async Task<List<ResourceLookupDto>> GetResourcesAsync()
    {
        var response = await _http.GetAsync("api/station/resources");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<List<StationPendingReceiveDto>> GetPendingReceivesAsync()
    {
        var response = await _http.GetAsync("api/station/pending-receives");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationPendingReceiveDto>>() ?? new();
    }

    public async Task<List<StationPendingHandoverDto>> GetPendingHandoverAsync()
    {
        var response = await _http.GetAsync("api/station/pending-handover");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationPendingHandoverDto>>() ?? new();
    }

    public async Task<List<StationRecentReceivedDto>> GetRecentReceivedAsync()
    {
        var response = await _http.GetAsync("api/station/recent-received");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationRecentReceivedDto>>() ?? new();
    }

    // Prompt 14: info kuota qty step ber-bundle ("Masuk / Tercatat / Sisa") sebelum submit.
    public async Task<WorkflowQuotaInfoDto?> GetQuotaInfoAsync(int articleWorkflowId, int bundleId)
    {
        var response = await _http.GetAsync($"api/station/quota-info?articleWorkflowId={articleWorkflowId}&bundleId={bundleId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<WorkflowQuotaInfoDto>();
    }

    public async Task<BundleScanInfoDto?> ScanAsync(string serial, int? resourceId)
    {
        var url = $"api/station/scan/{Uri.EscapeDataString(serial)}";
        if (resourceId.HasValue) url += $"?resourceId={resourceId.Value}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<BundleScanInfoDto>();
    }

    public async Task<(bool Success, string Error)> ReceiveAsync(StationReceiveRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/receive", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menerima." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> CompleteAsync(StationCompleteRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/station/complete", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyelesaikan." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateLogAsync(int workflowLogId, StationLogUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/station/logs/{workflowLogId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UnreceiveAsync(int workflowLogId, StationUnreceiveRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/station/logs/{workflowLogId}/unreceive", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membatalkan penerimaan." : error.Trim('"'));
    }
}

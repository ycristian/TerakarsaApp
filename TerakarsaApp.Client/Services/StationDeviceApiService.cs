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

    // Prompt 20: tukar kode pairing dengan station_token baru. Endpoint anonim di sisi
    // server -- StationTokenHandler cukup tidak mengirim header saat belum ada token tersimpan.
    public async Task<(bool Success, string Error, StationTokenResult? Result)> ClaimAsync(string code)
    {
        var response = await _http.PostAsJsonAsync("api/station-device/claim", new StationClaimRequest { Code = code });
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<StationTokenResult>();
            return (true, string.Empty, result);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Kode pairing tidak valid atau sudah kedaluwarsa." : error.Trim('"'), null);
    }

    // Prompt 20: logout perangkat -- hanguskan token di server (UNPAIR), localStorage
    // dibersihkan di sisi Razor setelah panggilan ini.
    public async Task<bool> LogoutAsync()
    {
        var response = await _http.PostAsync("api/station-device/logout", null);
        return response.IsSuccessStatusCode;
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

    // Prompt 12e: tab "Dikerjakan".
    public async Task<List<StationInProgressDto>> GetInProgressAsync()
    {
        var response = await _http.GetAsync("api/station/in-progress");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<StationInProgressDto>>() ?? new();
    }

    // Prompt 12e: strip 3 angka besar (Masuk/Dikerjakan/Dikirim).
    public async Task<StationCountsDto> GetCountsAsync()
    {
        var response = await _http.GetAsync("api/station/counts");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<StationCountsDto>() ?? new();
    }

    // Prompt 12e: tab "Dikirim" (dulu "Menunggu Diserahkan") -- ulang pakai endpoint
    // pending-handover yang sudah cocok dengan definisi Dikirim, hanya rename di sisi client.
    public async Task<List<StationPendingHandoverDto>> GetOutboundAsync() => await GetPendingHandoverAsync();

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

    // Prompt 12e: "Batal Serah" di tab Dikirim.
    public async Task<(bool Success, string Error)> CancelHandoverAsync(int workflowLogId, StationCancelHandoverRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/station/logs/{workflowLogId}/cancel-handover", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membatalkan serah." : error.Trim('"'));
    }

    // Prompt 12e: "Revisi" di tab Dikirim.
    public async Task<(bool Success, string Error)> ReviseHandoverAsync(int workflowLogId, StationReviseHandoverRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/station/logs/{workflowLogId}/revise-handover", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan revisi." : error.Trim('"'));
    }
}

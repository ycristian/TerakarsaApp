using System.Net.Http.Json;
using TerakarsaApp.Shared.Employees;
using TerakarsaApp.Shared.Resources;
using TerakarsaApp.Shared.SuperAdmin;

namespace TerakarsaApp.Client.Services;

public class SuperAdminApiService
{
    private readonly HttpClient _http;

    public SuperAdminApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<SuperAdminBundleSearchResultDto>> SearchBundlesAsync(string? search)
    {
        var query = string.IsNullOrWhiteSpace(search) ? "" : $"?search={Uri.EscapeDataString(search)}";
        var response = await _http.GetAsync($"api/super-admin/bundles{query}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<SuperAdminBundleSearchResultDto>>() ?? new();
    }

    public async Task<SuperAdminBundleDetailDto?> GetBundleDetailAsync(int bundleId)
    {
        var response = await _http.GetAsync($"api/super-admin/bundles/{bundleId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<SuperAdminBundleDetailDto>();
    }

    public async Task<(bool Success, string Error)> UpdateBundleAsync(int bundleId, SuperAdminBundleUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/super-admin/bundles/{bundleId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan bundle." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> DeleteBundleAsync(int bundleId, string reason)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete, $"api/super-admin/bundles/{bundleId}")
        {
            Content = JsonContent.Create(new SuperAdminDeleteRequest { DeleteReason = reason })
        };

        var response = await _http.SendAsync(request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus bundle." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> ReprintBundleAsync(int bundleId, int copies = 1)
    {
        var response = await _http.PostAsync($"api/super-admin/bundles/{bundleId}/reprint?copies={copies}", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak ulang label." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateLogAsync(int workflowLogId, SuperAdminLogUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/super-admin/workflow-logs/{workflowLogId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan log." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> DeleteLogAsync(int workflowLogId, string reason)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete, $"api/super-admin/workflow-logs/{workflowLogId}")
        {
            Content = JsonContent.Create(new SuperAdminDeleteRequest { DeleteReason = reason })
        };

        var response = await _http.SendAsync(request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus log." : error.Trim('"'));
    }

    // Prompt 36: modal "Edit Log"/"Edit Bundle" (/b/{serial}, /report-bundle Riwayat) --
    // lihat SuperAdminEditPanel.razor.
    public async Task<SuperAdminLogEditInfoDto?> GetLogEditInfoAsync(int workflowLogId)
    {
        var response = await _http.GetAsync($"api/super-admin/logs/{workflowLogId}/edit-info");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<SuperAdminLogEditInfoDto>();
    }

    public async Task<(bool Success, string Error)> EditLogAsync(int workflowLogId, SuperAdminEditLogRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/super-admin/logs/{workflowLogId}/edit", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan log." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> EditBundleAsync(int bundleId, SuperAdminEditBundleRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/super-admin/bundles/{bundleId}/edit", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan bundle." : error.Trim('"'));
    }

    public async Task<List<ResourceLookupDto>> GetResourcesByDivisionAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/super-admin/resources/by-division/{divisionId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<List<EmployeeLookupDto>> GetEmployeesByResourceAsync(int resourceId)
    {
        var response = await _http.GetAsync($"api/super-admin/employees/by-resource/{resourceId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<EmployeeLookupDto>>() ?? new();
    }
}

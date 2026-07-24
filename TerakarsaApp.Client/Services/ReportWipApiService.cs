using System.Net.Http.Json;
using System.Text;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.Client.Services;

// Prompt 22: Dashboard WIP per Divisi & Resource -- read-only (module REPORT_WIP,
// halaman /wip-dashboard).
public class ReportWipApiService
{
    private readonly HttpClient _http;

    public ReportWipApiService(HttpClient http)
    {
        _http = http;
    }

    private static string BuildQuery(params (string Key, string? Value)[] parts)
    {
        var sb = new StringBuilder();
        foreach (var (key, value) in parts)
        {
            if (string.IsNullOrEmpty(value)) continue;
            sb.Append(sb.Length == 0 ? '?' : '&');
            sb.Append(key).Append('=').Append(Uri.EscapeDataString(value));
        }
        return sb.ToString();
    }

    public async Task<DivisionWipSummaryDto> GetSummaryAsync(int? projectId = null)
    {
        var query = BuildQuery(("projectId", projectId?.ToString()));
        var response = await _http.GetAsync($"api/report-wip/summary{query}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<DivisionWipSummaryDto>() ?? new();
    }

    public async Task<(bool Success, string Error, List<DivisionWipBundleDto> Result)> GetBundlesAsync(
        int divisionId, string mode, int? resourceId, bool filterResource, int? projectId = null)
    {
        var query = BuildQuery(
            ("divisionId", divisionId.ToString()),
            ("mode", mode),
            ("resourceId", resourceId?.ToString()),
            ("filterResource", filterResource ? "true" : "false"),
            ("projectId", projectId?.ToString()));

        var response = await _http.GetAsync($"api/report-wip/bundles{query}");
        if (response.IsSuccessStatusCode)
            return (true, string.Empty, await response.Content.ReadFromJsonAsync<List<DivisionWipBundleDto>>() ?? new());

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal memuat daftar bundle." : error.Trim('"'), new());
    }

    public async Task<List<ProjectWipProgressDto>> GetRunningProjectsAsync()
    {
        var response = await _http.GetAsync("api/report-wip/projects");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ProjectWipProgressDto>>() ?? new();
    }
}

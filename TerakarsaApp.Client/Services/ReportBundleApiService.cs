using System.Net.Http.Json;
using System.Text;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Projects;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.Client.Services;

public class ReportBundleApiService
{
    private readonly HttpClient _http;

    public ReportBundleApiService(HttpClient http)
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

    // Fix: order-by-klik-header + pagination -- POST + body (pola sama dengan
    // ProjectApiService.GetPagedAsync), bukan lagi GET query string.
    public async Task<BundleWipPagedResult> GetWipAsync(BundleWipPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/report-bundle/wip", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<BundleWipPagedResult>() ?? new();
    }

    public async Task<ArticleProgressResultDto> GetProgressAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/report-bundle/progress?projectId={projectId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ArticleProgressResultDto>() ?? new();
    }

    public async Task<List<BundleVarianceDto>> GetVarianceAsync(int? projectId, int? articleId)
    {
        var query = BuildQuery(
            ("projectId", projectId?.ToString()),
            ("articleId", articleId?.ToString()));

        var response = await _http.GetAsync($"api/report-bundle/variance{query}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<BundleVarianceDto>>() ?? new();
    }

    public async Task<(bool Success, string Error, BundleHistoryResultDto? Result)> GetHistoryAsync(string? serial, int? projectId, int? bundleNo)
    {
        var query = BuildQuery(
            ("serial", serial),
            ("projectId", projectId?.ToString()),
            ("bundleNo", bundleNo?.ToString()));

        var response = await _http.GetAsync($"api/report-bundle/history{query}");
        if (response.IsSuccessStatusCode)
            return (true, string.Empty, await response.Content.ReadFromJsonAsync<BundleHistoryResultDto>());

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Bundle tidak ditemukan." : error.Trim('"'), null);
    }

    // Fix: "Cetak Reject" -- nota reject untuk satu baris log timeline (tab Riwayat), tombol
    // client hanya tampil kalau baris itu punya reject > 0.
    public async Task<(bool Success, string Error)> PrintRejectAsync(int workflowLogId, int copies = 1)
    {
        var response = await _http.PostAsync($"api/report-bundle/workflow-logs/{workflowLogId}/print-reject?copies={copies}", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak nota reject." : error.Trim('"'));
    }

    public async Task<List<ProjectDto>> GetProjectsAsync()
    {
        var response = await _http.GetAsync("api/report-bundle-picker/projects");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ProjectDto>>() ?? new();
    }

    public async Task<List<ArticleListItemDto>> GetArticlesByProjectAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/report-bundle-picker/projects/{projectId}/articles");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleListItemDto>>() ?? new();
    }

    public async Task<List<DivisionDto>> GetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/report-bundle-picker/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }
}

using System.Net.Http.Json;
using TerakarsaApp.Shared.Projects;
using TerakarsaApp.Shared.Resources;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.Client.Services;

// Dipakai halaman /workflow-input (module WORKFLOW_INPUT). List + hapus riwayat log tetap
// lewat WorkflowLogApiService (WorkflowLogController kini RequireModule ganda).
public class WorkflowInputApiService
{
    private readonly HttpClient _http;

    public WorkflowInputApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ProjectDto>> GetProjectsAsync()
    {
        var response = await _http.GetAsync("api/workflow-input/projects");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ProjectDto>>() ?? new();
    }

    public async Task<ProjectDto?> GetProjectAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/workflow-input/projects/{projectId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ProjectDto>();
    }

    public async Task<List<ArticleListItemDto>> GetArticlesByProjectAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/workflow-input/projects/{projectId}/articles");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleListItemDto>>() ?? new();
    }

    public async Task<List<ArticleSearchDto>> SearchArticlesAsync(string keyword)
    {
        var response = await _http.GetAsync($"api/workflow-input/articles/search?keyword={Uri.EscapeDataString(keyword)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleSearchDto>>() ?? new();
    }

    public async Task<ArticleDto?> GetArticleAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/workflow-input/articles/{articleId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ArticleDto>();
    }

    public async Task<(byte[] Bytes, string ContentType)?> GetArticleThumbnailAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/workflow-input/articles/{articleId}/thumbnail");
        if (!response.IsSuccessStatusCode) return null;

        var bytes = await response.Content.ReadAsByteArrayAsync();
        var contentType = response.Content.Headers.ContentType?.MediaType ?? "application/octet-stream";
        return (bytes, contentType);
    }

    public async Task<List<ResourceLookupDto>> GetResourcesByDivisionAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/workflow-input/resources/active-by-division/{divisionId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<List<ArticleNonBundleStepDto>> GetNonBundleStepsAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/articles/{articleId}/nonbundle-steps");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleNonBundleStepDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateLogAsync(WorkflowInputCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/workflow-input/logs", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error, int? ArticleSizeId)> CreateLogBatchAsync(WorkflowInputBatchCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/workflow-input/logs/batch", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty, null);

        var result = await response.Content.ReadFromJsonAsync<WorkflowInputBatchResult>();
        return (false, string.IsNullOrWhiteSpace(result?.Error) ? "Gagal menyimpan data." : result.Error, result?.ArticleSizeId);
    }
}

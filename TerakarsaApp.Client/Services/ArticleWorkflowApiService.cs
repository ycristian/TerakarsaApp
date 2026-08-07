using System.Net.Http.Json;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.Client.Services;

public class ArticleWorkflowApiService
{
    private readonly HttpClient _http;

    public ArticleWorkflowApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ArticleWorkflowDto> GetByArticleAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/article-workflows/by-article/{articleId}");
        if (!response.IsSuccessStatusCode) return new() { ArticleId = articleId };
        return await response.Content.ReadFromJsonAsync<ArticleWorkflowDto>() ?? new() { ArticleId = articleId };
    }

    public async Task<(bool Success, string Error)> ApplyAsync(ArticleWorkflowApplyRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/article-workflows/apply", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menerapkan template." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> SaveAsync(ArticleWorkflowSaveRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/article-workflows/save", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan workflow." : error.Trim('"'));
    }

    public async Task<(RestructurePreviewResultDto? Result, string Error)> PreviewInsertStepAsync(RestructureInsertPreviewRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/article-workflows/{request.ArticleId}/restructure/preview-insert", request);
        if (response.IsSuccessStatusCode) return (await response.Content.ReadFromJsonAsync<RestructurePreviewResultDto>(), string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (null, string.IsNullOrWhiteSpace(error) ? "Gagal memeriksa dampak sisip step." : error.Trim('"'));
    }

    public async Task<(RestructureInsertStepResultDto? Result, string Error)> InsertStepAsync(RestructureInsertPreviewRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/article-workflows/{request.ArticleId}/restructure/insert-step", request);
        if (response.IsSuccessStatusCode) return (await response.Content.ReadFromJsonAsync<RestructureInsertStepResultDto>(), string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (null, string.IsNullOrWhiteSpace(error) ? "Gagal menyisipkan step." : error.Trim('"'));
    }

    public async Task<(RestructurePreviewResultDto? Result, string Error)> PreviewDeactivateStepAsync(RestructureDeactivatePreviewRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/article-workflows/{request.ArticleId}/restructure/preview-deactivate", request);
        if (response.IsSuccessStatusCode) return (await response.Content.ReadFromJsonAsync<RestructurePreviewResultDto>(), string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (null, string.IsNullOrWhiteSpace(error) ? "Gagal memeriksa dampak nonaktifkan step." : error.Trim('"'));
    }

    public async Task<(RestructureDeactivateStepResultDto? Result, string Error)> DeactivateStepAsync(RestructureDeactivatePreviewRequest request)
    {
        var response = await _http.PostAsJsonAsync($"api/article-workflows/{request.ArticleId}/restructure/deactivate-step", request);
        if (response.IsSuccessStatusCode) return (await response.Content.ReadFromJsonAsync<RestructureDeactivateStepResultDto>(), string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (null, string.IsNullOrWhiteSpace(error) ? "Gagal menonaktifkan step." : error.Trim('"'));
    }
}

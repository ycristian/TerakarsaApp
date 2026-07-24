using System.Net.Http.Json;
using TerakarsaApp.Shared.Projects;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.Client.Services;

public class ArticleApiService
{
    private readonly HttpClient _http;

    public ArticleApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ArticleSizeProgressResultDto> GetSizeProgressAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/articles/{articleId}/size-progress");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ArticleSizeProgressResultDto>() ?? new();
    }

    public async Task<List<ArticleListItemDto>> GetByProjectAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/articles/by-project/{projectId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleListItemDto>>() ?? new();
    }

    public async Task<List<ArticleSizeSummaryDto>> GetSizesByProjectAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/articles/by-project/{projectId}/sizes");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleSizeSummaryDto>>() ?? new();
    }

    public async Task<ArticleDto?> GetByIdAsync(int id)
    {
        var response = await _http.GetAsync($"api/articles/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ArticleDto>();
    }

    public async Task<(bool Success, string Error, int Id)> CreateAsync(ArticleCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/articles", request);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<ArticleCreateResult>();
            return (true, string.Empty, result?.Id ?? 0);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'), 0);
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ArticleUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/articles", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/articles/{id}");
        return response.IsSuccessStatusCode;
    }
}

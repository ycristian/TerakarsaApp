using System.Net.Http.Json;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.Client.Services;

public class BundleApiService
{
    private readonly HttpClient _http;

    public BundleApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ArticleBundlesDto> GetByArticleAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/articles/{articleId}/bundles");
        if (!response.IsSuccessStatusCode) return new() { ArticleId = articleId };
        return await response.Content.ReadFromJsonAsync<ArticleBundlesDto>() ?? new() { ArticleId = articleId };
    }

    public async Task<(bool Success, string Error, int BundleNo, string? BundleLetter)> CreateAsync(BundleCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/bundles", request);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<BundleCreateResult>();
            return (true, string.Empty, result?.BundleNo ?? 0, result?.BundleLetter);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuat bundle." : error.Trim('"'), 0, null);
    }

    public async Task<(bool Success, string Error)> UpdateAsync(int id, BundleUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/bundles/{id}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan perubahan." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/bundles/{id}");
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus bundle." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> ReprintAsync(int id)
    {
        var response = await _http.PostAsync($"api/bundles/{id}/reprint", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak ulang label." : error.Trim('"'));
    }

    // --- Pintu masuk halaman /bundles ---

    public async Task<List<ProjectDto>> GetProjectsAsync()
    {
        var response = await _http.GetAsync("api/bundle-picker/projects");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ProjectDto>>() ?? new();
    }

    public async Task<List<ArticleListItemDto>> GetArticlesByProjectAsync(int projectId)
    {
        var response = await _http.GetAsync($"api/bundle-picker/projects/{projectId}/articles");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleListItemDto>>() ?? new();
    }

    public async Task<List<ArticleSearchDto>> SearchArticlesAsync(string keyword)
    {
        var response = await _http.GetAsync($"api/bundle-picker/articles/search?keyword={Uri.EscapeDataString(keyword)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleSearchDto>>() ?? new();
    }

    public async Task<(byte[] Bytes, string ContentType)?> GetArticleThumbnailAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/bundle-picker/articles/{articleId}/thumbnail");
        if (!response.IsSuccessStatusCode) return null;

        var bytes = await response.Content.ReadAsByteArrayAsync();
        var contentType = response.Content.Headers.ContentType?.MediaType ?? "application/octet-stream";
        return (bytes, contentType);
    }
}

using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Components.Forms;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.Client.Services;

public class ArticlePhotoApiService
{
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;

    private readonly HttpClient _http;

    public ArticlePhotoApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ArticlePhotoDto>> GetByArticleAsync(int articleId)
    {
        try
        {
            var response = await _http.GetAsync($"api/article-photos/by-article/{articleId}");
            if (!response.IsSuccessStatusCode) return new();
            return await response.Content.ReadFromJsonAsync<List<ArticlePhotoDto>>() ?? new();
        }
        catch (HttpRequestException)
        {
            return new();
        }
    }

    public async Task<(bool Success, string Error, List<ArticlePhotoUploadResultDto> Results)> UploadManyAsync(
        int articleId, IReadOnlyList<IBrowserFile> files)
    {
        using var content = new MultipartFormDataContent();
        content.Add(new StringContent(articleId.ToString()), "articleId");

        var streams = new List<Stream>();
        try
        {
            foreach (var file in files)
            {
                var stream = file.OpenReadStream(MaxFileSizeBytes);
                streams.Add(stream);

                var fileContent = new StreamContent(stream);
                fileContent.Headers.ContentType = new MediaTypeHeaderValue(
                    string.IsNullOrWhiteSpace(file.ContentType) ? "application/octet-stream" : file.ContentType);
                content.Add(fileContent, "files", file.Name);
            }

            var response = await _http.PostAsync("api/article-photos", content);
            if (response.IsSuccessStatusCode)
            {
                var results = await response.Content.ReadFromJsonAsync<List<ArticlePhotoUploadResultDto>>() ?? new();
                return (true, string.Empty, results);
            }

            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengunggah foto." : error.Trim('"'), new());
        }
        finally
        {
            foreach (var stream in streams)
                stream.Dispose();
        }
    }

    public async Task<(byte[] Bytes, string ContentType)?> GetPrimaryPhotoAsync(int articleId)
    {
        try
        {
            var response = await _http.GetAsync($"api/article-photos/{articleId}/primary");
            if (!response.IsSuccessStatusCode) return null;

            var bytes = await response.Content.ReadAsByteArrayAsync();
            var contentType = response.Content.Headers.ContentType?.MediaType ?? "application/octet-stream";
            return (bytes, contentType);
        }
        catch (HttpRequestException)
        {
            return null;
        }
    }

    public async Task<(byte[] Bytes, string ContentType)?> GetFirstPhotoForProjectAsync(int projectId)
    {
        try
        {
            var response = await _http.GetAsync($"api/article-photos/by-project/{projectId}/first-photo");
            if (!response.IsSuccessStatusCode) return null;

            var bytes = await response.Content.ReadAsByteArrayAsync();
            var contentType = response.Content.Headers.ContentType?.MediaType ?? "application/octet-stream";
            return (bytes, contentType);
        }
        catch (HttpRequestException)
        {
            return null;
        }
    }

    public async Task<(byte[] Bytes, string ContentType, string FileName)?> DownloadAsync(int articleId, int photoId)
    {
        try
        {
            var response = await _http.GetAsync($"api/article-photos/{articleId}/{photoId}/download");
            if (!response.IsSuccessStatusCode) return null;

            var bytes = await response.Content.ReadAsByteArrayAsync();
            var contentType = response.Content.Headers.ContentType?.MediaType ?? "application/octet-stream";
            var fileName = response.Content.Headers.ContentDisposition?.FileNameStar
                ?? response.Content.Headers.ContentDisposition?.FileName?.Trim('"')
                ?? "file";
            return (bytes, contentType, fileName);
        }
        catch (HttpRequestException)
        {
            return null;
        }
    }

    public async Task<bool> SetPrimaryAsync(int id)
    {
        var response = await _http.PutAsync($"api/article-photos/{id}/set-primary", null);
        return response.IsSuccessStatusCode;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/article-photos/{id}");
        return response.IsSuccessStatusCode;
    }
}

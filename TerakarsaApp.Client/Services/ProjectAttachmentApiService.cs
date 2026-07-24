using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Components.Forms;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.Client.Services;

public class ProjectAttachmentApiService
{
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;

    private readonly HttpClient _http;

    public ProjectAttachmentApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ProjectAttachmentDto>> GetByProjectAsync(int projectId)
    {
        try
        {
            var response = await _http.GetAsync($"api/project-attachments/by-project/{projectId}");
            if (!response.IsSuccessStatusCode) return new();
            return await response.Content.ReadFromJsonAsync<List<ProjectAttachmentDto>>() ?? new();
        }
        catch (HttpRequestException)
        {
            return new();
        }
    }

    public async Task<(bool Success, string Error, List<ProjectAttachmentUploadResultDto> Results)> UploadManyAsync(
        int projectId, IReadOnlyList<IBrowserFile> files, string? description)
    {
        using var content = new MultipartFormDataContent();
        content.Add(new StringContent(projectId.ToString()), "projectId");
        if (!string.IsNullOrWhiteSpace(description))
            content.Add(new StringContent(description), "description");

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

            var response = await _http.PostAsync("api/project-attachments", content);
            if (response.IsSuccessStatusCode)
            {
                var results = await response.Content.ReadFromJsonAsync<List<ProjectAttachmentUploadResultDto>>() ?? new();
                return (true, string.Empty, results);
            }

            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengunggah lampiran." : error.Trim('"'), new());
        }
        finally
        {
            foreach (var stream in streams)
                stream.Dispose();
        }
    }

    public async Task<(byte[] Bytes, string ContentType)?> GetFirstPhotoAsync(int projectId)
    {
        try
        {
            var response = await _http.GetAsync($"api/project-attachments/{projectId}/first-photo");
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

    public async Task<(byte[] Bytes, string ContentType, string FileName)?> DownloadAsync(int projectId, int attachmentId)
    {
        try
        {
            var response = await _http.GetAsync($"api/project-attachments/{projectId}/{attachmentId}/download");
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

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/project-attachments/{id}");
        return response.IsSuccessStatusCode;
    }
}

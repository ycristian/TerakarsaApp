using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 62: import personel PDH TNI AD dari export Google Form (.xlsx).
public class TniImportApiService
{
    private readonly HttpClient _http;

    public TniImportApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<(bool Success, string Error, TniImportHasilDto? Hasil)> UploadAsync(
        Stream stream, string fileName, long length)
    {
        using var content = new MultipartFormDataContent();
        var fileContent = new StreamContent(stream);
        fileContent.Headers.ContentType =
            new System.Net.Http.Headers.MediaTypeHeaderValue(
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        content.Add(fileContent, "file", fileName);

        var response = await _http.PostAsync("api/tni/import/upload", content);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengunggah file." : error.Trim('"'), null);
        }

        var hasil = await response.Content.ReadFromJsonAsync<TniImportHasilDto>();
        return (true, string.Empty, hasil);
    }

    public async Task<TniImportHasilDto?> GetBatchAsync(int batchId)
    {
        var response = await _http.GetAsync($"api/tni/import/{batchId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniImportHasilDto>();
    }

    public async Task<List<TniImportBatchDto>> GetBatchesAsync()
    {
        var response = await _http.GetAsync("api/tni/import/batches");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniImportBatchDto>>() ?? new();
    }

    public async Task<(bool Success, string Error, TniImportCommitHasilDto? Hasil)> CommitAsync(int batchId)
    {
        var response = await _http.PostAsync($"api/tni/import/{batchId}/commit", null);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan." : error.Trim('"'), null);
        }

        var hasil = await response.Content.ReadFromJsonAsync<TniImportCommitHasilDto>();
        return (true, string.Empty, hasil);
    }
}

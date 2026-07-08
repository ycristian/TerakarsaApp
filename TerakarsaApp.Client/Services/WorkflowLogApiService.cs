using System.Net.Http.Json;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.Client.Services;

public class WorkflowLogApiService
{
    private readonly HttpClient _http;

    public WorkflowLogApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<WorkflowLogDto>> GetByArticleAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/articles/{articleId}/workflow-logs");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<WorkflowLogDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int id, string reason)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete, $"api/workflow-logs/{id}")
        {
            Content = JsonContent.Create(new WorkflowLogDeleteRequest { DeleteReason = reason })
        };

        var response = await _http.SendAsync(request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus." : error.Trim('"'));
    }
}

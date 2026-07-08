using System.Net.Http.Json;
using TerakarsaApp.Shared.WorkflowTemplates;

namespace TerakarsaApp.Client.Services;

public class WorkflowTemplateApiService
{
    private readonly HttpClient _http;

    public WorkflowTemplateApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<WorkflowTemplatePagedResult> GetPagedAsync(WorkflowTemplatePagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/workflowtemplate/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<WorkflowTemplatePagedResult>() ?? new();
    }

    public async Task<List<WorkflowTemplateDto>> GetActiveAsync()
    {
        var response = await _http.GetAsync("api/workflowtemplate/active");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<WorkflowTemplateDto>>() ?? new();
    }

    public async Task<WorkflowTemplateDto?> GetByIdAsync(int id)
    {
        var response = await _http.GetAsync($"api/workflowtemplate/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<WorkflowTemplateDto>();
    }

    public async Task<(bool Success, string Error)> CreateAsync(WorkflowTemplateCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/workflowtemplate", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(WorkflowTemplateUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/workflowtemplate", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/workflowtemplate/{id}");
        return response.IsSuccessStatusCode;
    }
}

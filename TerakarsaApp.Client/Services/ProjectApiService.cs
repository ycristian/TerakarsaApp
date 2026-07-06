using System.Net.Http.Json;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.Client.Services;

public class ProjectApiService
{
    private readonly HttpClient _http;

    public ProjectApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ProjectPagedResult> GetPagedAsync(ProjectPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/project/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ProjectPagedResult>() ?? new();
    }

    public async Task<ProjectDto?> GetByIdAsync(int id)
    {
        var response = await _http.GetAsync($"api/project/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ProjectDto>();
    }

    public async Task<(bool Success, string Error, int Id)> CreateAsync(ProjectCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/project", request);
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<ProjectCreateResult>();
            return (true, string.Empty, result?.Id ?? 0);
        }
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'), 0);
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ProjectUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/project", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/project/{id}");
        return response.IsSuccessStatusCode;
    }
}

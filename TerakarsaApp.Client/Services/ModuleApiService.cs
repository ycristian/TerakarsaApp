using System.Net.Http.Json;
using TerakarsaApp.Shared.Modules;
using TerakarsaApp.Shared.Users;

namespace TerakarsaApp.Client.Services;

public class ModuleApiService
{
    private readonly HttpClient _http;

    public ModuleApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ModuleDto>> GetMyModulesAsync()
    {
        var response = await _http.GetAsync("api/module/my");
        if (!response.IsSuccessStatusCode) return new List<ModuleDto>();
        var result = await response.Content.ReadFromJsonAsync<List<ModuleDto>>();
        return result ?? new List<ModuleDto>();
    }

    public async Task<ModulePagedResult> GetPagedAsync(ModulePagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/module/paged", request);
        if (!response.IsSuccessStatusCode) return new ModulePagedResult();
        var result = await response.Content.ReadFromJsonAsync<ModulePagedResult>();
        return result ?? new ModulePagedResult();
    }

    public async Task<bool> CreateAsync(ModuleCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/module", request);
        return response.IsSuccessStatusCode;
    }

    public async Task<bool> UpdateAsync(ModuleUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/module", request);
        return response.IsSuccessStatusCode;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/module/{id}");
        return response.IsSuccessStatusCode;
    }

    public async Task<List<int>> GetAccessAsync(int userId)
    {
        var response = await _http.GetAsync($"api/module/access/{userId}");
        if (!response.IsSuccessStatusCode) return new List<int>();
        var result = await response.Content.ReadFromJsonAsync<List<int>>();
        return result ?? new List<int>();
    }

    public async Task<bool> SetAccessAsync(UserModuleAssignRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/module/access", request);
        return response.IsSuccessStatusCode;
    }

    public async Task<List<ModuleDto>> GetAllAsync()
    {
        var response = await _http.GetAsync("api/module/all");
        if (!response.IsSuccessStatusCode) return new List<ModuleDto>();
        var result = await response.Content.ReadFromJsonAsync<List<ModuleDto>>();
        return result ?? new List<ModuleDto>();
    }

    public async Task<List<UserDto>> GetUsersAsync()
    {
        var response = await _http.GetAsync("api/module/users");
        if (!response.IsSuccessStatusCode) return new List<UserDto>();
        var result = await response.Content.ReadFromJsonAsync<List<UserDto>>();
        return result ?? new List<UserDto>();
    }
}

using System.Net.Http.Json;
using TerakarsaApp.Shared.Users;

namespace TerakarsaApp.Client.Services;

public class UserApiService
{
    private readonly HttpClient _http;

    public UserApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<UserPagedResult> GetPagedAsync(UserPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/user/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<UserPagedResult>() ?? new();
    }

    public async Task<bool> CreateAsync(UserCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/user", request);
        return response.IsSuccessStatusCode;
    }

    public async Task<bool> UpdateAsync(UserUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/user", request);
        return response.IsSuccessStatusCode;
    }

    public async Task<(bool Success, string Error)> ResetPasswordAsync(UserResetPasswordRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/user/reset-password", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal reset password." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/user/{id}");
        return response.IsSuccessStatusCode;
    }
}

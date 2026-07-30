using System.Net.Http.Json;
using TerakarsaApp.Shared.Employees;

namespace TerakarsaApp.Client.Services;

public class EmployeeApiService
{
    private readonly HttpClient _http;

    public EmployeeApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<EmployeePagedResult> GetPagedAsync(EmployeePagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/employee/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<EmployeePagedResult>() ?? new();
    }

    public async Task<List<EmployeeDto>> GetActiveAsync()
    {
        var response = await _http.GetAsync("api/employee/active");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<EmployeeDto>>() ?? new();
    }

    // Prompt 32: dropdown "Penjahit" cascading di bawah dropdown Line/resource.
    public async Task<List<EmployeeLookupDto>> GetActiveByResourceAsync(int resourceId)
    {
        var response = await _http.GetAsync($"api/employees/lookup?resourceId={resourceId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<EmployeeLookupDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateAsync(EmployeeCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/employee", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(EmployeeUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/employee", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/employee/{id}");
        return response.IsSuccessStatusCode;
    }
}

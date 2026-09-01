using System.Net.Http.Json;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Employees;
using TerakarsaApp.Shared.Positions;
using TerakarsaApp.Shared.Resources;

namespace TerakarsaApp.Client.Services;

// Prompt 53: client untuk module PPIC_EMPLOYEE (api/ppic-employee) -- terpisah dari
// EmployeeApiService (api/employee, MASTER_EMPLOYEE).
public class PpicEmployeeApiService
{
    private readonly HttpClient _http;

    public PpicEmployeeApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<EmployeePagedResult> GetPagedAsync(EmployeePagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/ppic-employee/paged", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<EmployeePagedResult>() ?? new();
    }

    public async Task<List<DivisionDto>> GetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/ppic-employee/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    public async Task<List<PositionDto>> GetPositionsAsync()
    {
        var response = await _http.GetAsync("api/ppic-employee/positions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PositionDto>>() ?? new();
    }

    public async Task<List<ResourceLookupDto>> GetResourcesByDivisionAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/ppic-employee/resources/{divisionId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<string?> GetNextCodeAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/ppic-employee/next-code?divisionId={divisionId}");
        if (!response.IsSuccessStatusCode) return null;
        var dto = await response.Content.ReadFromJsonAsync<EmployeeNextCodeDto>();
        return dto?.SuggestedCode;
    }

    public async Task<(bool Success, string Error)> CreateAsync(EmployeeCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/ppic-employee", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> UpdateAsync(EmployeeUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/ppic-employee", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/ppic-employee/{id}");
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus data." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> SetActiveAsync(int id, bool isActive)
    {
        var response = await _http.PatchAsJsonAsync("api/ppic-employee/active", new EmployeeSetActiveRequest { Id = id, IsActive = isActive });
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengubah status." : error.Trim('"'));
    }
}

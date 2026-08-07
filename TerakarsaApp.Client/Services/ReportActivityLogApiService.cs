using System.Net.Http.Json;
using System.Text;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Employees;
using TerakarsaApp.Shared.Reports;
using TerakarsaApp.Shared.Resources;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.Client.Services;

public class ReportActivityLogApiService
{
    private readonly HttpClient _http;

    public ReportActivityLogApiService(HttpClient http)
    {
        _http = http;
    }

    private static string BuildQuery(params (string Key, string? Value)[] parts)
    {
        var sb = new StringBuilder();
        foreach (var (key, value) in parts)
        {
            if (string.IsNullOrEmpty(value)) continue;
            sb.Append(sb.Length == 0 ? '?' : '&');
            sb.Append(key).Append('=').Append(Uri.EscapeDataString(value));
        }
        return sb.ToString();
    }

    // Fix: dateFrom/dateTo dikirim TANPA offset timezone -- "o" (round-trip) menyertakan offset
    // lokal browser (mis. +07:00 WIB), dan ASP.NET Core mengonversi string ber-offset itu ke
    // timezone LOKAL SERVER saat parsing [FromQuery], menggeser nilai kalau server tidak
    // berjalan di WIB (bug: filter "hari ini" 00:00-23:59 WIB bisa lompat ke tanggal
    // sebelumnya). Nilai ini wall-clock apa adanya (cocok dengan datetime2 naive di DB), bukan
    // instant berzona waktu -- format manual tanpa token offset supaya diterima persis sama.
    private const string DateQueryFormat = "yyyy-MM-ddTHH:mm:ss.fffffff";

    public async Task<ActivityLogPagedResult> GetActivityLogAsync(ActivityLogPagedRequest request)
    {
        var query = BuildQuery(
            ("dateFrom", request.DateFrom.ToString(DateQueryFormat)),
            ("dateTo", request.DateTo.ToString(DateQueryFormat)),
            ("timeBasis", request.TimeBasis),
            ("divisionId", request.DivisionId?.ToString()),
            ("resourceId", request.ResourceId?.ToString()),
            ("employeeId", request.EmployeeId?.ToString()),
            ("projectId", request.ProjectId?.ToString()),
            ("searchTerm", request.SearchTerm),
            ("pageNumber", request.PageNumber.ToString()),
            ("pageSize", request.PageSize.ToString()),
            ("sortColumn", request.SortColumn),
            ("sortDirection", request.SortDirection));

        var response = await _http.GetAsync($"api/reports/activity-log{query}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ActivityLogPagedResult>() ?? new();
    }

    public async Task<List<DivisionDto>> GetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/reports/activity-log-picker/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    public async Task<List<ResourceLookupDto>> GetResourcesAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/reports/activity-log-picker/divisions/{divisionId}/resources");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<List<EmployeeLookupDto>> GetEmployeesAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/reports/activity-log-picker/divisions/{divisionId}/employees");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<EmployeeLookupDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> PrintKuponAsync(int workflowLogId)
    {
        var response = await _http.PostAsync($"api/reports/activity-log/workflow-logs/{workflowLogId}/print-kupon", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak kupon." : error.Trim('"'));
    }

    // Fix: kartu "Rekap Produksi" -- dropdown "Penjahit" cascading dari Resource (pola sama
    // dengan StationDeviceApiService.GetEmployeesByResourceAsync).
    public async Task<List<EmployeeLookupDto>> GetEmployeesByResourceAsync(int resourceId)
    {
        var response = await _http.GetAsync($"api/reports/activity-log-picker/resources/{resourceId}/employees");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<EmployeeLookupDto>>() ?? new();
    }

    public async Task<RekapStrukResultDto?> GetRekapStrukAsync(string level, int divisionId, int? resourceId, int? employeeId, DateTime date)
    {
        var query = BuildQuery(
            ("level", level),
            ("divisionId", divisionId.ToString()),
            ("resourceId", resourceId?.ToString()),
            ("employeeId", employeeId?.ToString()),
            ("date", date.ToString("yyyy-MM-dd")));

        var response = await _http.GetAsync($"api/reports/activity-log/rekap-struk{query}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<RekapStrukResultDto>();
    }

    public async Task<(bool Success, string Error)> PrintRekapStrukAsync(RekapStrukPrintRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/reports/activity-log/rekap-struk/print", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak rekap." : error.Trim('"'));
    }

    // Fix: "Cetak Karyawan" -- tombol baru terpisah, muncul kalau checkbox "Print Karyawan"
    // dicentang.
    public async Task<(bool Success, string Error)> PrintRekapKaryawanAsync(RekapKaryawanPrintRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/reports/activity-log/rekap-karyawan/print", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mencetak rekap karyawan." : error.Trim('"'));
    }
}

using System.Net.Http.Json;
using System.Text;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Reports;
using TerakarsaApp.Shared.Resources;

namespace TerakarsaApp.Client.Services;

// Prompt 30: Laporan Produksi Periode Gajian -- read-only (module REPORT_PRODUKSI,
// halaman /reports/produksi).
public class ReportProduksiApiService
{
    private readonly HttpClient _http;

    public ReportProduksiApiService(HttpClient http)
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

    public async Task<ProduksiReportResultDto> GetReportAsync(int divisionId, int? resourceId, DateTime periodStart, DateTime periodEnd)
    {
        var query = BuildQuery(
            ("divisionId", divisionId.ToString()),
            ("resourceId", resourceId?.ToString()),
            ("periodStart", periodStart.ToString("o")),
            ("periodEnd", periodEnd.ToString("o")));

        var response = await _http.GetAsync($"api/reports/produksi{query}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ProduksiReportResultDto>() ?? new();
    }

    public async Task<List<ResourceLookupDto>> GetResourcesAsync(int divisionId)
    {
        var response = await _http.GetAsync($"api/reports/produksi/resources?divisionId={divisionId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ResourceLookupDto>>() ?? new();
    }

    public async Task<List<DivisionDto>> GetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/reports/produksi/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }
}

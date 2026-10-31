using System.Net.Http.Json;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.ManualOutputs;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.Client.Services;

// Prompt 83: client untuk module MANUAL_OUTPUT (api/manual-outputs) -- daftar output manual
// dengan filter + aksi massal "Hubungkan ke Artikel". Pesan error dari API (asalnya
// RAISERROR di SP) diteruskan apa adanya ke halaman.
//
// TIDAK ADA method harga di sini -- koreksi harga ada di PayrollRekapApiService
// (module PAYROLL_REKAP).
public class ManualOutputApiService
{
    private readonly HttpClient _http;

    public ManualOutputApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ManualOutputAdminRowDto>> GetListAsync(
        bool onlyUnlinked, int? divisionId, int? payrollPeriodId, int? resourceId, string? search)
    {
        var query = $"api/manual-outputs?onlyUnlinked={(onlyUnlinked ? "true" : "false")}";
        if (divisionId.HasValue) query += $"&divisionId={divisionId.Value}";
        if (payrollPeriodId.HasValue) query += $"&payrollPeriodId={payrollPeriodId.Value}";
        if (resourceId.HasValue) query += $"&resourceId={resourceId.Value}";
        if (!string.IsNullOrWhiteSpace(search)) query += $"&search={Uri.EscapeDataString(search)}";

        var response = await _http.GetAsync(query);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ManualOutputAdminRowDto>>() ?? new();
    }

    public async Task<List<DivisionDto>> GetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/manual-outputs/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    public async Task<List<ArticleSearchDto>> SearchArticlesAsync(string keyword)
    {
        if (string.IsNullOrWhiteSpace(keyword)) return new();
        var response = await _http.GetAsync($"api/manual-outputs/articles?q={Uri.EscapeDataString(keyword)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ArticleSearchDto>>() ?? new();
    }

    public async Task<(ManualOutputLinkArticleResultDto? Result, string Error)> LinkArticleAsync(
        List<int> manualOutputIds, int articleId)
    {
        var response = await _http.PostAsJsonAsync("api/manual-outputs/link-article",
            new ManualOutputLinkArticleRequest { ManualOutputIds = manualOutputIds, ArticleId = articleId });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (null, string.IsNullOrWhiteSpace(error) ? "Gagal menghubungkan artikel." : error.Trim('"'));
        }

        var result = await response.Content.ReadFromJsonAsync<ManualOutputLinkArticleResultDto>();
        return (result, string.Empty);
    }
}

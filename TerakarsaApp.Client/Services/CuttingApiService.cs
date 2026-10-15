using System.Net.Http.Json;
using TerakarsaApp.Shared.Cutting;

namespace TerakarsaApp.Client.Services;

// Prompt 78-80: module Cutting (stok bundle dari hamparan). Dipakai Admin Cutting
// lewat tablet dengan login -- semua endpoint di bawah [RequireModule("CUTTING")].
public class CuttingApiService
{
    private readonly HttpClient _http;

    public CuttingApiService(HttpClient http)
    {
        _http = http;
    }

    private sealed class NextCodeResponse { public string NextCode { get; set; } = string.Empty; }
    private sealed class NextFromResponse { public int NextFrom { get; set; } }
    private sealed class JobCountResponse { public int JobCount { get; set; } }
    private sealed class ErrorResponse { public string? Message { get; set; } }

    private static async Task<(bool Success, string Error)> HasilAsync(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await BacaErrorAsync(response);
        return (false, error);
    }

    private static async Task<string> BacaErrorAsync(HttpResponseMessage response)
    {
        try
        {
            var body = await response.Content.ReadFromJsonAsync<ErrorResponse>();
            if (!string.IsNullOrWhiteSpace(body?.Message)) return body!.Message!;
        }
        catch
        {
            // body bukan JSON (mis. 403 dari RequireModule) -- jatuh ke pesan umum di bawah
        }

        return response.StatusCode == System.Net.HttpStatusCode.Forbidden
            ? "Anda tidak punya akses module Cutting."
            : "Terjadi kesalahan. Coba lagi.";
    }

    // ==================== dropdown & hitungan ====================

    public async Task<List<CuttingArticleDto>> GetArticlesAsync()
        => await _http.GetFromJsonAsync<List<CuttingArticleDto>>("api/cutting/articles") ?? new();

    public async Task<List<CuttingSizeDto>> GetArticleSizesAsync(int articleId)
        => await _http.GetFromJsonAsync<List<CuttingSizeDto>>($"api/cutting/articles/{articleId}/sizes") ?? new();

    public async Task<string> GetNextSpreadCodeAsync(int articleId)
    {
        var response = await _http.GetAsync($"api/cutting/articles/{articleId}/next-code");
        if (!response.IsSuccessStatusCode) return "H01";
        var body = await response.Content.ReadFromJsonAsync<NextCodeResponse>();
        return string.IsNullOrWhiteSpace(body?.NextCode) ? "H01" : body!.NextCode;
    }

    public async Task<int> GetNextNumberAsync(int articleId, int articleSizeId)
    {
        var response = await _http.GetAsync(
            $"api/cutting/next-number?articleId={articleId}&articleSizeId={articleSizeId}");
        if (!response.IsSuccessStatusCode) return 1;
        var body = await response.Content.ReadFromJsonAsync<NextFromResponse>();
        return body?.NextFrom ?? 1;
    }

    public async Task<List<CuttingSuggestItemDto>> SuggestAsync(int sheets, int target)
    {
        var response = await _http.PostAsJsonAsync("api/cutting/suggest",
            new CuttingSuggestRequest { Sheets = sheets, Target = target });
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<CuttingSuggestItemDto>>() ?? new();
    }

    // ==================== stok bundle ====================

    public async Task<CuttingStockSummaryDto> GetStockAsync()
        => await _http.GetFromJsonAsync<CuttingStockSummaryDto>("api/cutting/stock") ?? new();

    public async Task<List<CuttingTakenTodayDto>> GetTakenTodayAsync()
        => await _http.GetFromJsonAsync<List<CuttingTakenTodayDto>>("api/cutting/taken-today") ?? new();

    // ==================== hamparan ====================

    public async Task<List<SpreadListItemDto>> GetSpreadsAsync(
        int? articleId = null, string? status = null, DateTime? dateFrom = null, DateTime? dateTo = null)
    {
        var url = "api/cutting/spreads?x=1";
        if (articleId.HasValue) url += $"&articleId={articleId.Value}";
        if (!string.IsNullOrWhiteSpace(status)) url += $"&status={status}";
        if (dateFrom.HasValue) url += $"&dateFrom={dateFrom.Value:yyyy-MM-dd}";
        if (dateTo.HasValue) url += $"&dateTo={dateTo.Value:yyyy-MM-dd}";

        return await _http.GetFromJsonAsync<List<SpreadListItemDto>>(url) ?? new();
    }

    public async Task<SpreadDetailDto?> GetSpreadAsync(int id)
    {
        var response = await _http.GetAsync($"api/cutting/spreads/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<SpreadDetailDto>();
    }

    public async Task<(bool Success, string Error, SpreadCreateResultDto? Hasil)> CreateSpreadAsync(
        SpreadCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/cutting/spreads", request);

        if (response.IsSuccessStatusCode)
        {
            var hasil = await response.Content.ReadFromJsonAsync<SpreadCreateResultDto>();
            return (true, string.Empty, hasil);
        }

        return (false, await BacaErrorAsync(response), null);
    }

    public async Task<(bool Success, string Error)> UpdateSpreadHeaderAsync(
        int id, SpreadHeaderUpdateRequest request)
        => await HasilAsync(await _http.PutAsJsonAsync($"api/cutting/spreads/{id}", request));

    public async Task<(bool Success, string Error)> DeleteSpreadAsync(int id)
        => await HasilAsync(await _http.DeleteAsync($"api/cutting/spreads/{id}"));

    // bundleIds null/kosong = cetak semua bundle hamparan (sekalian tandai sudah dicetak).
    public async Task<(bool Success, string Error, int JobCount)> PrintAsync(int id, List<int>? bundleIds = null)
    {
        var response = await _http.PostAsJsonAsync($"api/cutting/spreads/{id}/print", bundleIds ?? new List<int>());

        if (response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadFromJsonAsync<JobCountResponse>();
            return (true, string.Empty, body?.JobCount ?? 0);
        }

        return (false, await BacaErrorAsync(response), 0);
    }

    // ==================== bundle di dalam set ====================

    public async Task<(bool Success, string Error)> UpdateBundleQtyAsync(
        int spreadId, List<SpreadBundleQtyInput> bundles)
        => await HasilAsync(await _http.PutAsJsonAsync(
            $"api/cutting/spreads/{spreadId}/bundles/qty",
            new SpreadBundleSaveRequest { Bundles = bundles }));

    public async Task<(bool Success, string Error)> AddBundleAsync(
        int spreadId, SpreadBundleAddRequest request)
        => await HasilAsync(await _http.PostAsJsonAsync($"api/cutting/spreads/{spreadId}/bundles", request));

    // HttpClient.DeleteAsync tidak punya overload berbody -- pakai HttpRequestMessage.
    public async Task<(bool Success, string Error)> RemoveBundleAsync(
        int spreadId, int bundleId, List<SpreadBundleQtyInput> bundles)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete,
            $"api/cutting/spreads/{spreadId}/bundles/{bundleId}")
        {
            Content = JsonContent.Create(new SpreadBundleRemoveRequest { Bundles = bundles })
        };

        return await HasilAsync(await _http.SendAsync(request));
    }
}

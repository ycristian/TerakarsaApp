using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 63: beranda module & halaman Personel PDH TNI AD.
public class TniPersonelApiService
{
    private readonly HttpClient _http;

    public TniPersonelApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<TniBerandaSummaryDto> GetSummaryAsync()
    {
        var response = await _http.GetAsync("api/tni/personel/summary");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<TniBerandaSummaryDto>() ?? new();
    }

    public async Task<TniPersonelListResult> GetListAsync(
        string? search = null, int? areaId = null, int? satuanId = null, string? status = null,
        bool perluReview = false, int pageNumber = 1, int pageSize = 30)
    {
        var q = new List<string>
        {
            $"pageNumber={pageNumber}",
            $"pageSize={pageSize}",
            $"perluReview={perluReview.ToString().ToLowerInvariant()}"
        };

        if (!string.IsNullOrWhiteSpace(search)) q.Add($"search={Uri.EscapeDataString(search)}");
        if (areaId.HasValue) q.Add($"areaId={areaId.Value}");
        if (satuanId.HasValue) q.Add($"satuanId={satuanId.Value}");
        if (!string.IsNullOrWhiteSpace(status)) q.Add($"status={status}");

        var response = await _http.GetAsync($"api/tni/personel?{string.Join("&", q)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<TniPersonelListResult>() ?? new();
    }

    public async Task<List<TniWilayahRowDto>> GetWilayahAsync()
    {
        var response = await _http.GetAsync("api/tni/personel/wilayah");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniWilayahRowDto>>() ?? new();
    }

    public async Task<TniPersonelDetailDto?> GetByIdAsync(int id)
    {
        var response = await _http.GetAsync($"api/tni/personel/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniPersonelDetailDto>();
    }

    public async Task<(bool Success, string Error)> UpdateAsync(int id, TniPersonelUpdateRequest request)
        => await Result(await _http.PutAsJsonAsync($"api/tni/personel/{id}", request));

    public async Task<(bool Success, string Error)> SetPolaAsync(int id, TniPersonelSetPolaRequest request)
        => await Result(await _http.PutAsJsonAsync($"api/tni/personel/{id}/pola", request));

    public async Task<(bool Success, string Error)> MarkReviewedAsync(int id, string? catatan)
        => await Result(await _http.PostAsJsonAsync($"api/tni/personel/{id}/reviewed",
                new TniPersonelCatatanRequest { Catatan = catatan }));

    public async Task<(bool Success, string Error)> DeleteAsync(int id, string alasan)
        => await Result(await _http.DeleteAsync(
                $"api/tni/personel/{id}?alasan={Uri.EscapeDataString(alasan)}"));

    private static async Task<(bool Success, string Error)> Result(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }
}

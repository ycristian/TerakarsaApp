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

    public async Task<TniBerandaStokDto> GetBerandaStokAsync()
    {
        var response = await _http.GetAsync("api/tni/personel/beranda-stok");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<TniBerandaStokDto>() ?? new();
    }

    public async Task<TniPersonelListResult> GetListAsync(
        string? search = null, int? areaId = null, int? satuanId = null, string? status = null,
        bool perluReview = false, int pageNumber = 1, int pageSize = 30,
        int? polaKemejaId = null, int? polaCelanaId = null)
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
        if (polaKemejaId.HasValue) q.Add($"polaKemejaId={polaKemejaId.Value}");
        if (polaCelanaId.HasValue) q.Add($"polaCelanaId={polaCelanaId.Value}");

        var response = await _http.GetAsync($"api/tni/personel?{string.Join("&", q)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<TniPersonelListResult>() ?? new();
    }

    // Prompt 89: PDF laporan personel -- filter sama dengan GetListAsync (tanpa paging).
    // Diambil sebagai bytes (endpoint butuh header X-Tni-Token), lalu disimpan
    // lewat downloadFileFromBytes (pola sama dengan TniBoxApiService.GetPdfAsync).
    public async Task<(bool Success, string Error, byte[]? Bytes, string FileName)> GetLaporanPdfAsync(
        string? search, int? areaId, int? satuanId, string? status, bool perluReview,
        int? polaKemejaId = null, int? polaCelanaId = null)
    {
        var q = new List<string> { $"perluReview={perluReview.ToString().ToLowerInvariant()}" };

        if (!string.IsNullOrWhiteSpace(search)) q.Add($"search={Uri.EscapeDataString(search)}");
        if (areaId.HasValue) q.Add($"areaId={areaId.Value}");
        if (satuanId.HasValue) q.Add($"satuanId={satuanId.Value}");
        if (!string.IsNullOrWhiteSpace(status)) q.Add($"status={status}");
        if (polaKemejaId.HasValue) q.Add($"polaKemejaId={polaKemejaId.Value}");
        if (polaCelanaId.HasValue) q.Add($"polaCelanaId={polaCelanaId.Value}");

        var response = await _http.GetAsync($"api/tni/personel/laporan-pdf?{string.Join("&", q)}");

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengunduh laporan." : error.Trim('"'), null, string.Empty);
        }

        var bytes = await response.Content.ReadAsByteArrayAsync();
        var name = response.Content.Headers.ContentDisposition?.FileNameStar
                   ?? response.Content.Headers.ContentDisposition?.FileName
                   ?? "Laporan_Personel.pdf";

        return (true, string.Empty, bytes, name.Trim('"'));
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

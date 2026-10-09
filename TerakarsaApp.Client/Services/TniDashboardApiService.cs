using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 69: dashboard progres & kebutuhan size PDH TNI AD.
public class TniDashboardApiService
{
    private readonly HttpClient _http;

    public TniDashboardApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<TniDashboardProgresDto> GetProgresAsync()
    {
        var response = await _http.GetAsync("api/tni/dashboard/progres");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<TniDashboardProgresDto>() ?? new();
    }

    public async Task<List<TniKebutuhanSizeDto>> GetKebutuhanSizeAsync(int? areaId, string jenis, int? satuanId = null)
    {
        var q = new List<string> { $"jenis={jenis}" };
        if (areaId.HasValue) q.Add($"areaId={areaId.Value}");
        if (satuanId.HasValue) q.Add($"satuanId={satuanId.Value}");

        var response = await _http.GetAsync("api/tni/dashboard/kebutuhan-size?" + string.Join("&", q));
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniKebutuhanSizeDto>>() ?? new();
    }

    // Excel diambil sebagai bytes DENGAN auth, lalu disimpan lewat helper JS
    // downloadFileFromBytes -- endpoint-nya butuh header Authorization, jadi
    // tidak bisa pakai <a href> biasa (pola sama dengan PDF box Prompt 67).
    public async Task<(bool Success, string Error, byte[]? Bytes, string FileName)> GetExcelAsync(
        int? areaId, int? satuanId = null)
    {
        var q = new List<string>();
        if (areaId.HasValue) q.Add($"areaId={areaId.Value}");
        if (satuanId.HasValue) q.Add($"satuanId={satuanId.Value}");
        var url = "api/tni/dashboard/kebutuhan-size/excel"
                + (q.Count > 0 ? "?" + string.Join("&", q) : string.Empty);

        var response = await _http.GetAsync(url);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengunduh Excel." : error.Trim('"'),
                    null, string.Empty);
        }

        var bytes = await response.Content.ReadAsByteArrayAsync();
        var name = response.Content.Headers.ContentDisposition?.FileNameStar
                   ?? response.Content.Headers.ContentDisposition?.FileName
                   ?? "Kebutuhan-Size.xlsx";

        return (true, string.Empty, bytes, name.Trim('"'));
    }
}

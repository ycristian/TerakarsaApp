using System.Net.Http.Json;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.Client.Services;

// Prompt 75: laporan module Stok Benang (riwayat, ringkasan, pemakaian, export).
public class ThreadReportApiService
{
    private readonly HttpClient _http;

    public ThreadReportApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<ThreadMovementListResult> GetMovementsAsync(
        DateTime? dari = null, DateTime? sampai = null, string? movementTypes = null,
        string? reasonCode = null, int? itemId = null, int? locationId = null,
        int? resourceId = null, int? projectId = null, int? createdBy = null,
        int pageNumber = 1, int pageSize = 50)
    {
        var url = "api/gudang/benang/movements?"
                  + Filter(dari, sampai, movementTypes, reasonCode, itemId, locationId,
                           resourceId, projectId, createdBy)
                  + $"&pageNumber={pageNumber}&pageSize={pageSize}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ThreadMovementListResult>() ?? new();
    }

    public async Task<ThreadSummaryDto> GetSummaryAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/summary");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ThreadSummaryDto>() ?? new();
    }

    public async Task<List<ThreadLocationStockDto>> GetByLocationAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/stocks/by-location");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadLocationStockDto>>() ?? new();
    }

    public async Task<List<ThreadUsageDto>> GetUsageAsync(int? projectId, DateTime? dari, DateTime? sampai)
    {
        var url = "api/gudang/benang/usage/by-project?x=1";
        if (projectId.HasValue) url += $"&projectId={projectId.Value}";
        if (dari.HasValue) url += $"&dari={dari.Value:yyyy-MM-dd}";
        if (sampai.HasValue) url += $"&sampai={sampai.Value:yyyy-MM-dd}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadUsageDto>>() ?? new();
    }

    // Excel diambil sebagai bytes DENGAN auth lalu disimpan lewat helper JS
    // downloadFileFromBytes (fileDownload.js) -- endpoint-nya butuh header Authorization,
    // jadi tidak bisa dibuka lewat <a href> biasa. Pola sama dengan TniBoxApiService.
    public Task<(bool Success, string Error, byte[]? Bytes, string FileName)> ExportMovementsAsync(
        DateTime? dari = null, DateTime? sampai = null, string? movementTypes = null,
        string? reasonCode = null, int? itemId = null, int? locationId = null,
        int? resourceId = null, int? projectId = null, int? createdBy = null) =>
        UnduhAsync("api/gudang/benang/movements/export?"
                   + Filter(dari, sampai, movementTypes, reasonCode, itemId, locationId,
                            resourceId, projectId, createdBy),
                   "riwayat-benang.xlsx");

    public Task<(bool Success, string Error, byte[]? Bytes, string FileName)> ExportUsageAsync(
        int? projectId, DateTime? dari, DateTime? sampai)
    {
        var url = "api/gudang/benang/usage/by-project/export?x=1";
        if (projectId.HasValue) url += $"&projectId={projectId.Value}";
        if (dari.HasValue) url += $"&dari={dari.Value:yyyy-MM-dd}";
        if (sampai.HasValue) url += $"&sampai={sampai.Value:yyyy-MM-dd}";

        return UnduhAsync(url, "pemakaian-benang.xlsx");
    }

    private static string Filter(DateTime? dari, DateTime? sampai, string? movementTypes,
        string? reasonCode, int? itemId, int? locationId, int? resourceId, int? projectId, int? createdBy)
    {
        var q = new List<string> { "x=1" };

        if (dari.HasValue) q.Add($"dari={dari.Value:yyyy-MM-dd}");
        if (sampai.HasValue) q.Add($"sampai={sampai.Value:yyyy-MM-dd}");
        if (!string.IsNullOrWhiteSpace(movementTypes)) q.Add($"movementTypes={Uri.EscapeDataString(movementTypes)}");
        if (!string.IsNullOrWhiteSpace(reasonCode)) q.Add($"reasonCode={Uri.EscapeDataString(reasonCode)}");
        if (itemId.HasValue) q.Add($"itemId={itemId.Value}");
        if (locationId.HasValue) q.Add($"locationId={locationId.Value}");
        if (resourceId.HasValue) q.Add($"resourceId={resourceId.Value}");
        if (projectId.HasValue) q.Add($"projectId={projectId.Value}");
        if (createdBy.HasValue) q.Add($"createdBy={createdBy.Value}");

        return string.Join("&", q);
    }

    private async Task<(bool Success, string Error, byte[]? Bytes, string FileName)> UnduhAsync(
        string url, string namaDefault)
    {
        var response = await _http.GetAsync(url);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengunduh file." : error.Trim('"'),
                    null, string.Empty);
        }

        var bytes = await response.Content.ReadAsByteArrayAsync();
        var name = response.Content.Headers.ContentDisposition?.FileNameStar
                   ?? response.Content.Headers.ContentDisposition?.FileName
                   ?? namaDefault;

        return (true, string.Empty, bytes, name.Trim('"'));
    }
}

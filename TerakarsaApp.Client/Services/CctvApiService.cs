using System.Net.Http.Json;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.Client.Services;

// Prompt 91-94: module CCTV (api/cctv/...). Login biasa (JWT) + module CCTV.
public class CctvApiService
{
    private readonly HttpClient _http;

    public CctvApiService(HttpClient http)
    {
        _http = http;
    }

    // Base URL API (dipakai pemutar video: URL stream dibangun di klien dari base ini).
    public string ApiBaseUrl => _http.BaseAddress?.ToString().TrimEnd('/') ?? string.Empty;

    // ==================== kamera (Prompt 91) ====================

    public async Task<CctvCameraListResponse> GetCamerasAsync(bool onlyVisible = false, string? area = null)
    {
        var url = $"api/cctv/cameras?onlyVisible={onlyVisible.ToString().ToLowerInvariant()}";
        if (!string.IsNullOrWhiteSpace(area)) url += $"&area={Uri.EscapeDataString(area)}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<CctvCameraListResponse>() ?? new();
    }

    public async Task<CctvCameraDetailDto?> GetCameraAsync(int id)
    {
        var response = await _http.GetAsync($"api/cctv/cameras/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<CctvCameraDetailDto>();
    }

    public async Task<List<CctvLookupItemDto>> GetLookupAsync()
    {
        var response = await _http.GetAsync("api/cctv/cameras/lookup");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<CctvLookupItemDto>>() ?? new();
    }

    public Task<(bool Success, string Error, int Id)> CreateCameraAsync(CctvCameraSaveRequest request) =>
        Kirim(_http.PostAsJsonAsync("api/cctv/cameras", request));

    public Task<(bool Success, string Error, int Id)> UpdateCameraAsync(int id, CctvCameraSaveRequest request) =>
        Kirim(_http.PutAsJsonAsync($"api/cctv/cameras/{id}", request));

    public Task<(bool Success, string Error, int Id)> DeleteCameraAsync(int id) =>
        Kirim(_http.DeleteAsync($"api/cctv/cameras/{id}"));

    public Task<(bool Success, string Error, int Id)> SetLinksAsync(int id, CctvCameraLinksRequest request) =>
        Kirim(_http.PutAsJsonAsync($"api/cctv/cameras/{id}/links", request));

    public async Task<(bool Success, string Error, CctvSyncResultDto? Result)> SyncAsync()
    {
        try
        {
            var response = await _http.PostAsync("api/cctv/cameras/sync", null);
            if (!response.IsSuccessStatusCode)
                return (false, await PesanGagal(response), null);
            return (true, string.Empty, await response.Content.ReadFromJsonAsync<CctvSyncResultDto>());
        }
        catch (HttpRequestException ex)
        {
            return (false, ex.Message, null);
        }
    }

    // ==================== stream (Prompt 92) ====================

    public async Task<CctvStreamTokenDto?> GetStreamTokenAsync(int cameraId)
    {
        try
        {
            var response = await _http.GetAsync($"api/cctv/cameras/{cameraId}/stream-token");
            if (!response.IsSuccessStatusCode) return null;
            return await response.Content.ReadFromJsonAsync<CctvStreamTokenDto>();
        }
        catch (HttpRequestException)
        {
            return null;
        }
    }

    // URL playlist live lewat proxy API (TANPA token -- cctvPlayer.js menambahkan ?t= ke tiap request).
    public string HlsUrl(string path) => $"{ApiBaseUrl}/api/cctv/hls/{Uri.EscapeDataString(path)}/index.m3u8";

    // ==================== playback (Prompt 93) ====================

    // null = server rekaman tidak terjangkau / gagal.
    public async Task<List<CctvRecordingSpanDto>?> GetRecordingsAsync(string path, string token, DateOnly date)
    {
        try
        {
            var response = await _http.GetAsync(
                $"api/cctv/playback/{Uri.EscapeDataString(path)}/list?date={date:yyyy-MM-dd}&t={Uri.EscapeDataString(token)}");
            if (!response.IsSuccessStatusCode) return null;
            return await response.Content.ReadFromJsonAsync<List<CctvRecordingSpanDto>>() ?? new();
        }
        catch (HttpRequestException)
        {
            return null;
        }
    }

    public async Task<CctvRecordingRangeDto?> GetRecordingRangeAsync(string path, string token)
    {
        try
        {
            var response = await _http.GetAsync(
                $"api/cctv/playback/{Uri.EscapeDataString(path)}/range?t={Uri.EscapeDataString(token)}");
            if (!response.IsSuccessStatusCode) return null;
            return await response.Content.ReadFromJsonAsync<CctvRecordingRangeDto>();
        }
        catch (HttpRequestException)
        {
            return null;
        }
    }

    // URL <video src> (fMP4) / unduhan (MP4) lewat proxy API. start dikirim ISO8601 +07:00.
    public string PlaybackUrl(string path, string token, DateTimeOffset start, int durationSec, bool download = false) =>
        $"{ApiBaseUrl}/api/cctv/playback/{Uri.EscapeDataString(path)}/{(download ? "download" : "get")}" +
        $"?start={Uri.EscapeDataString(CctvWaktu.Iso(start))}&duration={durationSec}&t={Uri.EscapeDataString(token)}";

    // ==================== bantuan ====================

    private static async Task<(bool Success, string Error, int Id)> Kirim(Task<HttpResponseMessage> task)
    {
        try
        {
            var response = await task;
            if (!response.IsSuccessStatusCode) return (false, await PesanGagal(response), 0);
            var text = await response.Content.ReadAsStringAsync();
            return (true, string.Empty, int.TryParse(text, out var id) ? id : 0);
        }
        catch (HttpRequestException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    private static async Task<string> PesanGagal(HttpResponseMessage response)
    {
        var text = await response.Content.ReadAsStringAsync();
        if (response.StatusCode == System.Net.HttpStatusCode.Forbidden)
            return "Anda tidak punya akses module CCTV.";
        if (string.IsNullOrWhiteSpace(text)) return $"Gagal ({(int)response.StatusCode}).";
        return text.Trim('"');
    }
}

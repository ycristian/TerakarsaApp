using System.Text.Json;
using Microsoft.Extensions.Options;

namespace TerakarsaApp.API.Services;

// Prompt 91: konfigurasi module CCTV (section "Cctv" di appsettings).
// Semua alamat MediaMTX HANYA dipakai di sisi server -- tidak pernah dikirim ke klien.
public class CctvOptions
{
    public string MtxApiBaseUrl { get; set; } = "http://127.0.0.1:9997";
    public string MtxHlsBaseUrl { get; set; } = "http://127.0.0.1:8888";
    public string MtxWebRtcBaseUrl { get; set; } = "http://127.0.0.1:8889";
    public string MtxPlaybackBaseUrl { get; set; } = "http://127.0.0.1:9996";
    public string StreamTokenSecret { get; set; } = string.Empty;
    public int StreamTokenMinutes { get; set; } = 10;
}

public record CctvMtxPath(string Name, bool Ready, string? VideoCodec);

public record CctvMtxPathsResult(bool Reachable, List<CctvMtxPath> Paths);

// Prompt 91: klien API kontrol MediaMTX (/v3/paths/list). Typed HttpClient, timeout 5 detik.
// MediaMTX tidak terjangkau -> Reachable = false + daftar kosong, TIDAK melempar error.
public class CctvMediaMtxClient
{
    private const int ItemsPerPage = 100;
    private const int MaxPages = 20;

    private readonly HttpClient _http;
    private readonly CctvOptions _options;
    private readonly ILogger<CctvMediaMtxClient> _logger;

    public CctvMediaMtxClient(HttpClient http, IOptions<CctvOptions> options, ILogger<CctvMediaMtxClient> logger)
    {
        _http = http;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<CctvMtxPathsResult> GetPathsAsync(CancellationToken ct = default)
    {
        var hasil = new List<CctvMtxPath>();
        var baseUrl = _options.MtxApiBaseUrl.TrimEnd('/');

        try
        {
            for (var page = 0; page < MaxPages; page++)
            {
                using var resp = await _http.GetAsync(
                    $"{baseUrl}/v3/paths/list?page={page}&itemsPerPage={ItemsPerPage}", ct);
                resp.EnsureSuccessStatusCode();

                await using var stream = await resp.Content.ReadAsStreamAsync(ct);
                using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
                var root = doc.RootElement;

                if (root.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array)
                {
                    foreach (var item in items.EnumerateArray())
                    {
                        var name = item.TryGetProperty("name", out var n) ? n.GetString() : null;
                        if (string.IsNullOrWhiteSpace(name)) continue;

                        var ready = item.TryGetProperty("ready", out var r) && r.ValueKind == JsonValueKind.True;
                        hasil.Add(new CctvMtxPath(name, ready, BacaCodecVideo(item)));
                    }
                }

                var pageCount = root.TryGetProperty("pageCount", out var pc) && pc.TryGetInt32(out var p) ? p : 1;
                if (page + 1 >= pageCount) break;
            }

            return new CctvMtxPathsResult(true, hasil);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            if (ct.IsCancellationRequested) throw;
            _logger.LogWarning("MediaMTX API tidak terjangkau ({Pesan}).", ex.Message);
            return new CctvMtxPathsResult(false, new List<CctvMtxPath>());
        }
    }

    // "tracks": ["H264", "Opus"] (format lama) atau "tracks2": [{ "codec": "H264", ... }].
    // Ambil track video pertama yang dikenali.
    private static string? BacaCodecVideo(JsonElement item)
    {
        static bool IsVideo(string? c) => c is not null &&
            (c.Contains("264") || c.Contains("265") || c.Contains("HEVC", StringComparison.OrdinalIgnoreCase)
             || c.Contains("AV1", StringComparison.OrdinalIgnoreCase) || c.Contains("VP", StringComparison.OrdinalIgnoreCase)
             || c.Contains("JPEG", StringComparison.OrdinalIgnoreCase));

        if (item.TryGetProperty("tracks2", out var t2) && t2.ValueKind == JsonValueKind.Array)
        {
            foreach (var t in t2.EnumerateArray())
            {
                var codec = t.ValueKind == JsonValueKind.Object && t.TryGetProperty("codec", out var c)
                    ? c.GetString() : null;
                if (IsVideo(codec)) return codec;
            }
        }

        if (item.TryGetProperty("tracks", out var t1) && t1.ValueKind == JsonValueKind.Array)
        {
            foreach (var t in t1.EnumerateArray())
            {
                var codec = t.ValueKind == JsonValueKind.String ? t.GetString()
                    : t.ValueKind == JsonValueKind.Object && t.TryGetProperty("codec", out var c) ? c.GetString()
                    : null;
                if (IsVideo(codec)) return codec;
            }
        }

        return null;
    }
}

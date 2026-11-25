using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Services;

// Prompt 91: konfigurasi module CCTV (section "Cctv" di appsettings).
// Semua alamat MediaMTX HANYA dipakai di sisi server -- tidak pernah dikirim ke klien.
public class CctvOptions
{
    public string MtxApiBaseUrl { get; set; } = "http://127.0.0.1:9997";
    // Prompt 95: Basic Auth untuk API kontrol MediaMTX (9997) saja. Kosong = tanpa header
    // (production: API satu mesin dengan MediaMTX, localhost diizinkan). Dev: isi lewat user-secrets.
    public string MtxApiUser { get; set; } = string.Empty;
    public string MtxApiPassword { get; set; } = string.Empty;
    public string MtxHlsBaseUrl { get; set; } = "http://127.0.0.1:8888";
    public string MtxWebRtcBaseUrl { get; set; } = "http://127.0.0.1:8889";
    public string MtxPlaybackBaseUrl { get; set; } = "http://127.0.0.1:9996";
    public string StreamTokenSecret { get; set; } = string.Empty;
    public int StreamTokenMinutes { get; set; } = 10;

    // Dev: host cadangan MediaMTX (mis. TKA001 lewat Tailscale) dipakai kalau host di
    // Mtx*BaseUrl tidak bisa dihubungi saat API start (PC dev sedang di luar LAN pabrik).
    // Kosong (production) = tanpa cadangan. Dicek sekali per proses -- pindah jaringan = restart API.
    public string MtxFallbackHost { get; set; } = string.Empty;

    // Base URL WebRTC (WHEP) MediaMTX untuk BROWSER (dikirim di token stream). Kosong (production)
    // = klien memakai host halaman + :8889. Dev (klien di localhost) isi mis. http://192.168.8.233:8889
    // -- ikut dialihkan ke MtxFallbackHost bila host utama tidak terjangkau.
    public string PublicWebRtcBaseUrl { get; set; } = string.Empty;

    // Prompt 97: interval (detik) background service sinkron kualitas rekaman ke MediaMTX.
    public int QualitySyncSeconds { get; set; } = 30;

    public static void ApplyFallbackHost(CctvOptions o, ILogger logger)
    {
        if (string.IsNullOrWhiteSpace(o.MtxFallbackHost)) return;
        if (!Uri.TryCreate(o.MtxApiBaseUrl, UriKind.Absolute, out var api)) return;
        if (string.Equals(api.Host, o.MtxFallbackHost, StringComparison.OrdinalIgnoreCase)) return;
        if (BisaTerhubung(api.Host, api.Port)) return;

        string Ganti(string url) => Uri.TryCreate(url, UriKind.Absolute, out var u)
                                    && string.Equals(u.Host, api.Host, StringComparison.OrdinalIgnoreCase)
            ? new UriBuilder(u) { Host = o.MtxFallbackHost }.Uri.ToString().TrimEnd('/')
            : url;

        o.MtxApiBaseUrl = Ganti(o.MtxApiBaseUrl);
        o.MtxHlsBaseUrl = Ganti(o.MtxHlsBaseUrl);
        o.MtxWebRtcBaseUrl = Ganti(o.MtxWebRtcBaseUrl);
        o.MtxPlaybackBaseUrl = Ganti(o.MtxPlaybackBaseUrl);
        o.PublicWebRtcBaseUrl = Ganti(o.PublicWebRtcBaseUrl);
        logger.LogWarning("MediaMTX {Utama} tidak terjangkau -> memakai host cadangan {Cadangan}.",
            api.Host, o.MtxFallbackHost);
    }

    private static bool BisaTerhubung(string host, int port)
    {
        try
        {
            using var tcp = new System.Net.Sockets.TcpClient();
            return tcp.ConnectAsync(host, port).Wait(TimeSpan.FromSeconds(2)) && tcp.Connected;
        }
        catch
        {
            return false;
        }
    }
}

public record CctvMtxPath(string Name, bool Ready, string? VideoCodec);

// Prompt 93: waktu pabrik = WIB (UTC+7, tanpa DST). Semua waktu ke MediaMTX dikirim RFC3339 +07:00.
public static class CctvTime
{
    public static readonly TimeSpan Wib = TimeSpan.FromHours(7);

    public static DateTimeOffset ToWib(DateTimeOffset t) => t.ToOffset(Wib);

    public static string ToRfc3339(DateTimeOffset t) =>
        ToWib(t).ToString("yyyy-MM-dd'T'HH:mm:sszzz", System.Globalization.CultureInfo.InvariantCulture);
}

public record CctvMtxPathsResult(bool Reachable, List<CctvMtxPath> Paths);

// Prompt 97: hasil panggilan API konfigurasi path MediaMTX.
public enum CctvMtxCallOutcome { Ok, NotFound, Unreachable, Failed }

// Source berisi kredensial kamera -- JANGAN di-log / diserialisasi. ToString() disamarkan.
public record CctvMtxSourceResult(CctvMtxCallOutcome Outcome, string? Source, int? StatusCode = null)
{
    public override string ToString() => $"{Outcome} (status {StatusCode})";
}

// Prompt 97: hasil CctvMediaMtxClient.SwapQuality. CurrentQuality = kualitas URL sebelum ditukar.
public record CctvSourceSwap(bool Supported, string? Source, string? CurrentQuality)
{
    public static readonly CctvSourceSwap NotSupported = new(false, null, null);

    public override string ToString() => Supported ? $"Supported (sebelumnya {CurrentQuality})" : "NotSupported";
}

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
                using var req = new HttpRequestMessage(HttpMethod.Get,
                    $"{baseUrl}/v3/paths/list?page={page}&itemsPerPage={ItemsPerPage}");
                TambahAuthApi(req);

                using var resp = await _http.SendAsync(req, ct);
                if (resp.StatusCode == HttpStatusCode.Unauthorized)
                {
                    _logger.LogWarning(
                        "MediaMTX API menolak autentikasi ({Url}) — cek Cctv:MtxApiUser/MtxApiPassword (user terisi: {AdaUser}).",
                        baseUrl, !string.IsNullOrWhiteSpace(_options.MtxApiUser));
                    return new CctvMtxPathsResult(false, new List<CctvMtxPath>());
                }
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

    // Prompt 93: daftar rekaman dari server playback MediaMTX:
    //   GET {MtxPlaybackBaseUrl}/list?path=..&start=..&end=..   (start/end RFC3339, opsional)
    // Jawaban: [{ "start": "<RFC3339>", "duration": <detik, angka ATAU string>, "url": ... }].
    // 404 = tidak ada rekaman -> daftar kosong. Tidak terjangkau -> Reachable = false.
    public async Task<(bool Reachable, List<(DateTimeOffset Start, DateTimeOffset End)> Spans)> ListRecordingsAsync(
        string path, DateTimeOffset? start, DateTimeOffset? end, CancellationToken ct = default)
    {
        var spans = new List<(DateTimeOffset, DateTimeOffset)>();
        var url = $"{_options.MtxPlaybackBaseUrl.TrimEnd('/')}/list?path={Uri.EscapeDataString(path)}";
        if (start.HasValue) url += "&start=" + Uri.EscapeDataString(CctvTime.ToRfc3339(start.Value));
        if (end.HasValue) url += "&end=" + Uri.EscapeDataString(CctvTime.ToRfc3339(end.Value));

        try
        {
            using var resp = await _http.GetAsync(url, ct);
            if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return (true, spans);
            resp.EnsureSuccessStatusCode();

            await using var stream = await resp.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return (true, spans);

            foreach (var item in doc.RootElement.EnumerateArray())
            {
                if (!item.TryGetProperty("start", out var s) || s.ValueKind != JsonValueKind.String) continue;
                if (!DateTimeOffset.TryParse(s.GetString(), System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.None, out var st)) continue;

                double dur = 0;
                if (item.TryGetProperty("duration", out var d))
                {
                    if (d.ValueKind == JsonValueKind.Number) dur = d.GetDouble();
                    else if (d.ValueKind == JsonValueKind.String)
                        double.TryParse(d.GetString(), System.Globalization.NumberStyles.Float,
                            System.Globalization.CultureInfo.InvariantCulture, out dur);
                }
                if (dur <= 0) continue;

                spans.Add((st, st.AddSeconds(dur)));
            }

            return (true, spans);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            if (ct.IsCancellationRequested) throw;
            _logger.LogWarning("Server playback MediaMTX tidak terjangkau ({Pesan}).", ex.Message);
            return (false, spans);
        }
    }

    // Prompt 95: header per request -- HttpClient yang sama dipakai playback /list (9996).
    private void TambahAuthApi(HttpRequestMessage req)
    {
        if (string.IsNullOrWhiteSpace(_options.MtxApiUser)) return;
        var token = Convert.ToBase64String(
            Encoding.UTF8.GetBytes($"{_options.MtxApiUser}:{_options.MtxApiPassword}"));
        req.Headers.Authorization = new AuthenticationHeaderValue("Basic", token);
    }

    // ==================== Prompt 97: kualitas rekaman (source path) ====================
    // URL source berisi user & kode RTSP kamera: HANYA dipegang di memori selama baca -> tukar -> PATCH.
    // Tidak pernah ditulis ke log, database, maupun dikirim ke browser. Method di bawah TIDAK menulis
    // log sama sekali -- pemanggil (CctvQualitySync) yang mengatur log supaya tidak membanjiri.

    //   GET {MtxApiBaseUrl}/v3/config/paths/get/{name}  -> konfigurasi path (termasuk "source").
    // 404 = path tidak ada di konfigurasi MediaMTX.
    public async Task<CctvMtxSourceResult> GetPathSourceAsync(string path, CancellationToken ct = default)
    {
        var url = $"{_options.MtxApiBaseUrl.TrimEnd('/')}/v3/config/paths/get/{Uri.EscapeDataString(path)}";
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            TambahAuthApi(req);
            using var resp = await _http.SendAsync(req, ct);

            if (resp.StatusCode == HttpStatusCode.NotFound) return new(CctvMtxCallOutcome.NotFound, null);
            if (!resp.IsSuccessStatusCode) return new(CctvMtxCallOutcome.Failed, null, (int)resp.StatusCode);

            await using var stream = await resp.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            var source = doc.RootElement.ValueKind == JsonValueKind.Object
                         && doc.RootElement.TryGetProperty("source", out var s) && s.ValueKind == JsonValueKind.String
                ? s.GetString()
                : null;
            return new(CctvMtxCallOutcome.Ok, source);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            if (ct.IsCancellationRequested) throw;
            return new(CctvMtxCallOutcome.Unreachable, null);
        }
    }

    //   PATCH {MtxApiBaseUrl}/v3/config/paths/patch/{name}   body { "source": "..." }
    // Hanya mengubah konfigurasi di memori MediaMTX (mediamtx.yml tidak ditulis).
    public async Task<CctvMtxCallOutcome> PatchPathSourceAsync(string path, string source, CancellationToken ct = default)
    {
        var url = $"{_options.MtxApiBaseUrl.TrimEnd('/')}/v3/config/paths/patch/{Uri.EscapeDataString(path)}";
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Patch, url)
            {
                Content = new StringContent(JsonSerializer.Serialize(new { source }), Encoding.UTF8, "application/json")
            };
            TambahAuthApi(req);
            using var resp = await _http.SendAsync(req, ct);

            if (resp.StatusCode == HttpStatusCode.NotFound) return CctvMtxCallOutcome.NotFound;
            return resp.IsSuccessStatusCode ? CctvMtxCallOutcome.Ok : CctvMtxCallOutcome.Failed;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            if (ct.IsCancellationRequested) throw;
            return CctvMtxCallOutcome.Unreachable;
        }
    }

    // Akhiran ".../Streaming/Channels/<channel><01|02>" dengan / tanpa "/" penutup.
    // <channel> = digit di depan dua digit terakhir (minimal satu digit), tidak pernah diubah.
    private static readonly System.Text.RegularExpressions.Regex SourcePattern = new(
        @"^(?<pre>.+/Streaming/Channels/\d+?)(?<q>0[12])(?<post>/?)$",
        System.Text.RegularExpressions.RegexOptions.IgnoreCase
        | System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    // Fungsi murni: tukar kualitas pada URL source. Hanya dua digit terakhir yang berganti
    // (01 = MAIN, 02 = SUB); user, kode, IP, port, channel, dan "/" penutup tetap.
    // URL tidak cocok pola / kualitas tidak dikenal -> Supported = false (jangan PATCH).
    public static CctvSourceSwap SwapQuality(string? source, string quality)
    {
        var digit = quality switch
        {
            CctvRecordQuality.Main => "01",
            CctvRecordQuality.Sub => "02",
            _ => null
        };
        if (digit is null || string.IsNullOrWhiteSpace(source)) return CctvSourceSwap.NotSupported;

        var m = SourcePattern.Match(source);
        if (!m.Success) return CctvSourceSwap.NotSupported;

        var hasil = m.Groups["pre"].Value + digit + m.Groups["post"].Value;
        return new CctvSourceSwap(true, hasil, m.Groups["q"].Value == "01" ? CctvRecordQuality.Main : CctvRecordQuality.Sub);
    }

    // Untuk log: samarkan "user:kode@" pada URL (rtsp://***@ip:554/...). Tidak pernah melempar.
    public static string MaskCredentials(string? url)
    {
        if (string.IsNullOrEmpty(url)) return string.Empty;
        var scheme = url.IndexOf("://", StringComparison.Ordinal);
        var start = scheme < 0 ? 0 : scheme + 3;
        var at = url.LastIndexOf('@');
        return at >= start ? url[..start] + "***" + url[at..] : url;
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

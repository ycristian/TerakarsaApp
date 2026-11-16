using System.Globalization;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using Microsoft.Net.Http.Headers;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Controllers;

// Prompt 93: playback rekaman lewat server playback MediaMTX (port 9996 di 127.0.0.1).
// TANPA JWT (dipakai <video src> & unduhan) -- wajib token stream (?t=) untuk {path},
// sama dengan Prompt 92. API TIDAK PERNAH membaca D:\rekaman langsung; tidak ada fitur hapus.
[ApiController]
[Route("api/cctv/playback")]
[AllowAnonymous]
[EnableRateLimiting(CctvRateLimit.Policy)]
public class CctvPlaybackController : ControllerBase
{
    private const int MaxDurationSeconds = 600;          // maks 10 menit per permintaan
    private static readonly TimeSpan MergeGap = TimeSpan.FromSeconds(2);

    private readonly CctvStreamTokenService _tokens;
    private readonly CctvProxyService _proxy;
    private readonly CctvMediaMtxClient _mtx;
    private readonly CctvCameraService _cameras;
    private readonly CctvOptions _options;

    public CctvPlaybackController(CctvStreamTokenService tokens, CctvProxyService proxy, CctvMediaMtxClient mtx,
        CctvCameraService cameras, IOptions<CctvOptions> options)
    {
        _tokens = tokens;
        _proxy = proxy;
        _mtx = mtx;
        _cameras = cameras;
        _options = options.Value;
    }

    // Rentang rekaman pada satu tanggal (WIB): dipotong ke batas hari, digabung bila bersambung.
    [HttpGet("{path}/list")]
    public async Task<IActionResult> List(string path, [FromQuery] string? date, [FromQuery(Name = "t")] string? token,
        CancellationToken ct)
    {
        var cek = Cek(path, token);
        if (cek is not null) return cek;

        if (!DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
            return BadRequest("Tanggal wajib format yyyy-MM-dd.");

        var dayStart = new DateTimeOffset(d.ToDateTime(TimeOnly.MinValue), CctvTime.Wib);
        var dayEnd = dayStart.AddDays(1);

        var (reachable, spans) = await _mtx.ListRecordingsAsync(path, dayStart, dayEnd, ct);
        if (!reachable) return StatusCode(StatusCodes.Status502BadGateway, "Server rekaman tidak terjangkau.");

        return Ok(Gabung(spans, dayStart, dayEnd));
    }

    // Rekaman paling lama / paling baru yang masih ada (teks "Rekaman paling lama: ...").
    [HttpGet("{path}/range")]
    public async Task<IActionResult> Range(string path, [FromQuery(Name = "t")] string? token, CancellationToken ct)
    {
        var cek = Cek(path, token);
        if (cek is not null) return cek;

        var (reachable, spans) = await _mtx.ListRecordingsAsync(path, null, null, ct);
        if (!reachable) return StatusCode(StatusCodes.Status502BadGateway, "Server rekaman tidak terjangkau.");

        return Ok(new CctvRecordingRangeDto
        {
            Oldest = spans.Count == 0 ? null : CctvTime.ToWib(spans.Min(s => s.Start)),
            Newest = spans.Count == 0 ? null : CctvTime.ToWib(spans.Max(s => s.End))
        });
    }

    // Putar: streaming fMP4 dari MediaMTX, header Range diteruskan.
    [HttpGet("{path}/get")]
    public Task<IActionResult> Get(string path, [FromQuery] string? start, [FromQuery] int? duration,
        [FromQuery(Name = "t")] string? token)
        => Teruskan(path, start, duration, token, unduh: false);

    // Unduh klip: format=mp4 + Content-Disposition attachment <namaKamera>_<yyyyMMdd_HHmmss>.mp4.
    [HttpGet("{path}/download")]
    public Task<IActionResult> Download(string path, [FromQuery] string? start, [FromQuery] int? duration,
        [FromQuery(Name = "t")] string? token)
        => Teruskan(path, start, duration, token, unduh: true);

    // ==================== bantuan ====================

    private async Task<IActionResult> Teruskan(string path, string? start, int? duration, string? token, bool unduh)
    {
        var cek = Cek(path, token);
        if (cek is not null) return cek;

        if (duration is null || duration < 1 || duration > MaxDurationSeconds)
            return BadRequest($"Durasi wajib 1–{MaxDurationSeconds} detik.");

        // start WAJIB ISO8601 dengan offset (mis. 2026-11-16T14:32:00+07:00).
        // "+" yang tidak di-escape klien terbaca spasi di query -> kembalikan.
        start = start?.Trim().Replace(' ', '+');
        if (string.IsNullOrWhiteSpace(start)
            || !DateTimeOffset.TryParseExact(start, new[] { "yyyy-MM-dd'T'HH:mm:sszzz", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz", "yyyy-MM-dd'T'HH:mm:ssK", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK" },
                CultureInfo.InvariantCulture, DateTimeStyles.None, out var mulai))
            return BadRequest("Waktu mulai wajib ISO8601 dengan offset, mis. 2026-11-16T14:32:00+07:00.");

        var target = $"{_options.MtxPlaybackBaseUrl.TrimEnd('/')}/get?path={Uri.EscapeDataString(path)}"
                     + $"&start={Uri.EscapeDataString(CctvTime.ToRfc3339(mulai))}"
                     + $"&duration={duration.Value.ToString(CultureInfo.InvariantCulture)}"
                     + (unduh ? "&format=mp4" : string.Empty);

        string? namaFile = null;
        if (unduh)
        {
            var nama = await _cameras.GetNameByPathAsync(path, HttpContext.RequestAborted) ?? path;
            namaFile = $"{AmanUntukFile(nama)}_{CctvTime.ToWib(mulai):yyyyMMdd_HHmmss}.mp4";
        }

        await _proxy.ForwardGetAsync(HttpContext, target, forwardRange: !unduh,
            onUpstreamStatus: async upstream =>
            {
                if (upstream.IsSuccessStatusCode) return true;

                // Jawaban galat MediaMTX tidak diteruskan mentah -- pesan sendiri.
                var notFound = upstream.StatusCode == System.Net.HttpStatusCode.NotFound;
                Response.StatusCode = notFound ? StatusCodes.Status404NotFound : StatusCodes.Status502BadGateway;
                Response.ContentType = "text/plain; charset=utf-8";
                await Response.WriteAsync(notFound
                    ? "Tidak ada rekaman pada jam itu"
                    : $"Server rekaman menolak permintaan (HTTP {(int)upstream.StatusCode}).", HttpContext.RequestAborted);
                return false;
            },
            beforeBody: resp =>
            {
                if (namaFile is null) return;
                resp.Headers[HeaderNames.ContentDisposition] = new ContentDispositionHeaderValue("attachment")
                {
                    FileName = namaFile,
                    FileNameStar = namaFile
                }.ToString();
                if (!resp.Headers.ContainsKey(HeaderNames.ContentType)) resp.ContentType = "video/mp4";
            });

        return new EmptyResult();
    }

    private IActionResult? Cek(string path, string? token)
    {
        if (!CctvPathRules.IsValidPath(path)) return BadRequest("Path tidak valid.");
        var check = _tokens.Validate(token, path);
        return check == CctvTokenCheck.Ok ? null : CctvRateLimit.TokenResult(check);
    }

    // Potong ke [dayStart, dayEnd), urutkan, gabung bila selisih <= 2 detik. Hasil dalam WIB.
    private static List<CctvRecordingSpanDto> Gabung(
        List<(DateTimeOffset Start, DateTimeOffset End)> spans, DateTimeOffset dayStart, DateTimeOffset dayEnd)
    {
        var hasil = new List<CctvRecordingSpanDto>();

        foreach (var (s0, e0) in spans.OrderBy(x => x.Start))
        {
            var s = s0 < dayStart ? dayStart : s0;
            var e = e0 > dayEnd ? dayEnd : e0;
            if (e <= s) continue;

            var last = hasil.Count > 0 ? hasil[^1] : null;
            if (last is not null && s - last.End <= MergeGap)
            {
                if (e > last.End) last.End = CctvTime.ToWib(e);
                continue;
            }

            hasil.Add(new CctvRecordingSpanDto { Start = CctvTime.ToWib(s), End = CctvTime.ToWib(e) });
        }

        return hasil;
    }

    private static string AmanUntukFile(string nama)
    {
        var sb = new StringBuilder(nama.Length);
        foreach (var ch in nama.Trim())
            sb.Append(char.IsLetterOrDigit(ch) || ch is '-' or '_' ? ch : '_');
        var s = sb.ToString().Trim('_');
        while (s.Contains("__")) s = s.Replace("__", "_");
        return s.Length == 0 ? "kamera" : (s.Length > 60 ? s[..60] : s);
    }
}

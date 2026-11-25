using System.Text;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// 2026-11-25 (lanjutan Prompt 92 §4): proxy SINYAL WebRTC (WHEP) ke MediaMTX :8889.
// Supaya live view memakai WebRTC 8889 dari alamat mana pun yang membuka Client
// (app.terakarsa.id via Cloudflare = https -> tidak boleh fetch http://host:8889 langsung,
// mixed content). Yang lewat API hanya pertukaran SDP (beberapa KB per kamera); MEDIA tetap
// mengalir langsung browser <-> MediaMTX (UDP/TCP 8189) -- jadi hanya tersambung bila browser
// bisa menjangkau server (LAN pabrik / Tailscale). Dari internet ICE gagal -> cctvPlayer.js
// otomatis pindah ke HLS proxy.
//
// TANPA JWT (dipanggil dari JS pemutar) -- wajib token stream (?t=) untuk {path}, sama dengan
// proxy HLS. Header Location jawaban MediaMTX ditulis ulang ke rute proxy ini; alamat MediaMTX
// tidak pernah dikirim ke klien.
[ApiController]
[Route("api/cctv/whep")]
[AllowAnonymous]
[EnableRateLimiting(CctvRateLimit.Policy)]
public partial class CctvWhepController : ControllerBase
{
    private const int MaxSdpBytes = 64 * 1024;
    private static readonly TimeSpan SignalTimeout = TimeSpan.FromSeconds(15);

    private readonly CctvStreamTokenService _tokens;
    private readonly IHttpClientFactory _httpFactory;
    private readonly CctvOptions _options;
    private readonly ILogger<CctvWhepController> _logger;

    public CctvWhepController(CctvStreamTokenService tokens, IHttpClientFactory httpFactory,
        IOptions<CctvOptions> options, ILogger<CctvWhepController> logger)
    {
        _tokens = tokens;
        _httpFactory = httpFactory;
        _options = options.Value;
        _logger = logger;
    }

    // Buka sesi: body = SDP offer browser -> jawab 201 + SDP answer MediaMTX.
    [HttpPost("{path}")]
    public async Task<IActionResult> Offer(string path, [FromQuery(Name = "t")] string? token)
    {
        if (!CctvPathRules.IsValidPath(path)) return BadRequest("Path tidak valid.");

        var check = _tokens.Validate(token, path);
        if (check != CctvTokenCheck.Ok) return CctvRateLimit.TokenResult(check);

        if (Request.ContentLength is > MaxSdpBytes) return BadRequest("SDP terlalu besar.");
        string offer;
        using (var reader = new StreamReader(Request.Body, Encoding.UTF8))
            offer = await reader.ReadToEndAsync(HttpContext.RequestAborted);
        if (offer.Length == 0 || offer.Length > MaxSdpBytes) return BadRequest("SDP tidak valid.");

        var target = $"{_options.MtxWebRtcBaseUrl.TrimEnd('/')}/{path}/whep";
        using var req = new HttpRequestMessage(HttpMethod.Post, target)
        {
            Content = new StringContent(offer, Encoding.UTF8)
        };
        req.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/sdp");

        // HttpClient proxy tanpa timeout (dipakai streaming) -> batasi sendiri untuk sinyal.
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(HttpContext.RequestAborted);
        cts.CancelAfter(SignalTimeout);

        HttpResponseMessage upstream;
        try
        {
            upstream = await Client().SendAsync(req, cts.Token);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            if (HttpContext.RequestAborted.IsCancellationRequested) return new EmptyResult();
            _logger.LogWarning("Proxy WHEP gagal menghubungi MediaMTX: {Pesan}", ex.Message);
            return StatusCode(StatusCodes.Status502BadGateway, "Server rekaman tidak terjangkau.");
        }

        using (upstream)
        {
            var body = await upstream.Content.ReadAsStringAsync(HttpContext.RequestAborted);
            if ((int)upstream.StatusCode != StatusCodes.Status201Created)
                return StatusCode((int)upstream.StatusCode, body);

            // Location MediaMTX: /{path}/whep/{session} -> rute DELETE proxy ini.
            var loc = upstream.Headers.Location?.OriginalString;
            var session = loc is null ? null : loc.TrimEnd('/').Split('/').LastOrDefault();
            if (session is not null && SessionRegex().IsMatch(session))
                Response.Headers.Location = $"{Request.PathBase}/api/cctv/whep/{path}/{session}";

            Response.StatusCode = StatusCodes.Status201Created;
            Response.ContentType = "application/sdp";
            Response.Headers.CacheControl = "no-store";
            await Response.WriteAsync(body, HttpContext.RequestAborted);
            return new EmptyResult();
        }
    }

    // Tutup sesi (dipanggil saat pemutar berhenti / ganti halaman).
    [HttpDelete("{path}/{session}")]
    public async Task<IActionResult> Close(string path, string session, [FromQuery(Name = "t")] string? token)
    {
        if (!CctvPathRules.IsValidPath(path) || !SessionRegex().IsMatch(session))
            return BadRequest("Path tidak valid.");

        var check = _tokens.Validate(token, path);
        if (check != CctvTokenCheck.Ok) return CctvRateLimit.TokenResult(check);

        var target = $"{_options.MtxWebRtcBaseUrl.TrimEnd('/')}/{path}/whep/{session}";
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(HttpContext.RequestAborted);
        cts.CancelAfter(SignalTimeout);
        try
        {
            using var resp = await Client().DeleteAsync(target, cts.Token);
            return StatusCode((int)resp.StatusCode);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return StatusCode(StatusCodes.Status502BadGateway);
        }
    }

    private HttpClient Client() => _httpFactory.CreateClient(CctvProxyService.HttpClientName);

    // id sesi WHEP MediaMTX = UUID.
    [GeneratedRegex("^[A-Za-z0-9-]{1,64}$")]
    private static partial Regex SessionRegex();
}

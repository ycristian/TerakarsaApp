using Microsoft.AspNetCore.Http.Features;
using Microsoft.Extensions.Primitives;

namespace TerakarsaApp.API.Services;

// Prompt 92-93: penerus (proxy) HTTP dari API ke MediaMTX di 127.0.0.1.
// - Streaming langsung ke response (tanpa buffer ke memori; buffering response dimatikan).
// - Request ke MediaMTX dibatalkan saat klien putus (HttpContext.RequestAborted).
// - URL tujuan dibangun pemanggil dari base URL KONFIGURASI + path/file yang sudah divalidasi
//   (CctvPathRules) -- tidak pernah dari input user mentah.
// - Header balasan yang diteruskan dibatasi daftar putih; alamat MediaMTX tidak pernah bocor.
public class CctvProxyService
{
    public const string HttpClientName = "cctv-proxy";
    private const int MaxRedirects = 2;

    private static readonly string[] ResponseHeaderWhitelist =
    {
        "Content-Type", "Cache-Control", "Content-Length", "Content-Range", "Accept-Ranges",
        "Last-Modified", "ETag", "Expires"
    };

    private readonly IHttpClientFactory _httpFactory;
    private readonly ILogger<CctvProxyService> _logger;

    public CctvProxyService(IHttpClientFactory httpFactory, ILogger<CctvProxyService> logger)
    {
        _httpFactory = httpFactory;
        _logger = logger;
    }

    // Query string asli tanpa parameter tertentu (mis. token "t").
    public static string QueryWithout(IQueryCollection query, params string[] exclude)
    {
        var pairs = query
            .Where(kv => !exclude.Contains(kv.Key, StringComparer.OrdinalIgnoreCase))
            .SelectMany(kv => kv.Value.Select(v => new KeyValuePair<string, string?>(kv.Key, v)));
        return QueryString.Create(pairs).ToUriComponent();
    }

    /// <summary>
    /// Teruskan GET ke <paramref name="targetUrl"/> dan alirkan jawabannya ke response klien.
    /// </summary>
    /// <param name="forwardRange">teruskan header Range dari klien (seek video).</param>
    /// <param name="onUpstreamStatus">dipanggil sebelum body ditulis; kembalikan false untuk
    /// tidak meneruskan body (pemanggil sudah menulis jawaban sendiri).</param>
    public async Task ForwardGetAsync(HttpContext ctx, string targetUrl, bool forwardRange = false,
        Func<HttpResponseMessage, Task<bool>>? onUpstreamStatus = null,
        Action<HttpResponse>? beforeBody = null)
    {
        var ct = ctx.RequestAborted;
        var http = _httpFactory.CreateClient(HttpClientName);
        HttpResponseMessage upstream;
        try
        {
            // MediaMTX (HLS) menjawab request pertama dengan 302 ke "?cookieCheck=1". Redirect
            // diikuti DI SINI (maks. MaxRedirects), hanya ke host:port yang sama dengan tujuan
            // awal -- tujuan tetap base URL konfigurasi. Cookie tidak dikirim -> MediaMTX memakai
            // mode tanpa cookie (?session=... di URI playlist, ikut diteruskan klien).
            var url = new Uri(targetUrl);
            var hop = 0;
            while (true)
            {
                using var req = new HttpRequestMessage(HttpMethod.Get, url);
                if (forwardRange && ctx.Request.Headers.TryGetValue("Range", out var range))
                    req.Headers.TryAddWithoutValidation("Range", (IEnumerable<string>)range!);

                upstream = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);

                var code = (int)upstream.StatusCode;
                if (code is < 300 or > 399 || upstream.Headers.Location is null || hop >= MaxRedirects)
                    break;

                var next = upstream.Headers.Location.IsAbsoluteUri
                    ? upstream.Headers.Location
                    : new Uri(url, upstream.Headers.Location);
                if (Uri.Compare(next, url, UriComponents.SchemeAndServer, UriFormat.Unescaped,
                        StringComparison.OrdinalIgnoreCase) != 0)
                    break; // redirect ke host lain -> tidak diikuti

                upstream.Dispose();
                url = next;
                hop++;
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            return;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogWarning("Proxy CCTV gagal menghubungi server rekaman: {Pesan}", ex.Message);
            if (!ctx.Response.HasStarted)
            {
                ctx.Response.StatusCode = StatusCodes.Status502BadGateway;
                ctx.Response.ContentType = "text/plain; charset=utf-8";
                await ctx.Response.WriteAsync("Server rekaman tidak terjangkau.", CancellationToken.None);
            }
            return;
        }

        using (upstream)
        {
            if (onUpstreamStatus is not null && !await onUpstreamStatus(upstream)) return;

            ctx.Response.StatusCode = (int)upstream.StatusCode;
            CopyHeaders(upstream, ctx.Response);
            beforeBody?.Invoke(ctx.Response);

            ctx.Features.Get<IHttpResponseBodyFeature>()?.DisableBuffering();

            try
            {
                await using var body = await upstream.Content.ReadAsStreamAsync(ct);
                await body.CopyToAsync(ctx.Response.Body, 64 * 1024, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                // klien putus -- request ke MediaMTX ikut dibatalkan lewat ct.
            }
            catch (IOException) when (ct.IsCancellationRequested)
            {
            }
        }
    }

    public static void CopyHeaders(HttpResponseMessage upstream, HttpResponse response)
    {
        foreach (var name in ResponseHeaderWhitelist)
        {
            if (upstream.Headers.TryGetValues(name, out var v) || upstream.Content.Headers.TryGetValues(name, out v))
                response.Headers[name] = new StringValues(v.ToArray());
        }
    }
}

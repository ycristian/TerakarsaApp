using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Prompt 92: proxy HLS live ke MediaMTX. TANPA JWT (dipanggil <video>/hls.js) -- wajib token
// stream (?t=) yang valid untuk {path}. Token diterbitkan CctvCameraController.StreamToken
// (hanya untuk user ber-module CCTV).
//
// Isi playlist TIDAK ditulis ulang: URI di dalamnya relatif, token ditambahkan klien
// (cctvPlayer.js -> xhrSetup) ke setiap request playlist & segmen.
[ApiController]
[Route("api/cctv/hls")]
[AllowAnonymous]
[EnableRateLimiting(CctvRateLimit.Policy)]
public class CctvHlsController : ControllerBase
{
    private readonly CctvStreamTokenService _tokens;
    private readonly CctvProxyService _proxy;
    private readonly CctvOptions _options;

    public CctvHlsController(CctvStreamTokenService tokens, CctvProxyService proxy, IOptions<CctvOptions> options)
    {
        _tokens = tokens;
        _proxy = proxy;
        _options = options.Value;
    }

    [HttpGet("{path}/{**file}")]
    public async Task<IActionResult> Get(string path, string file, [FromQuery(Name = "t")] string? token)
    {
        if (!CctvPathRules.IsValidPath(path) || !CctvPathRules.IsValidFile(file))
            return BadRequest("Path tidak valid.");

        var check = _tokens.Validate(token, path);
        if (check != CctvTokenCheck.Ok) return CctvRateLimit.TokenResult(check);

        var target = $"{_options.MtxHlsBaseUrl.TrimEnd('/')}/{path}/{file}"
                     + CctvProxyService.QueryWithout(Request.Query, "t");

        await _proxy.ForwardGetAsync(HttpContext, target);
        return new EmptyResult();
    }
}

public static class CctvRateLimit
{
    // Rate limit LONGGAR per IP untuk rute video (segmen diminta terus-menerus) --
    // BUKAN limiter login ("auth"). Didaftarkan di Program.cs.
    public const string Policy = "cctv-stream";

    public static IActionResult TokenResult(CctvTokenCheck check) => check switch
    {
        CctvTokenCheck.WrongPath => new ObjectResult("Token bukan untuk kamera ini.") { StatusCode = StatusCodes.Status403Forbidden },
        CctvTokenCheck.Expired => new UnauthorizedObjectResult("Token kedaluwarsa."),
        CctvTokenCheck.Missing => new UnauthorizedObjectResult("Token wajib."),
        _ => new UnauthorizedObjectResult("Token tidak valid.")
    };
}

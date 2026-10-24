using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Foto artikel lewat URL biasa, TANPA header apa pun -- supaya bisa dipasang langsung di
// <img src="..."> pada kartu WIP /station.
//
// Kenapa controller terpisah: StationDeviceController memasang [RequireStationToken] di
// level kelas, dan tag <img> tidak bisa mengirim header X-Station-Token. Dulu jalan
// keluarnya adalah mengunduh foto lewat HttpClient lalu menanamkannya sebagai data: URI
// base64 -- yang membuat browser tidak bisa men-cache apa pun, jadi SETIAP reload /station
// mengunduh ulang seluruh foto. Dengan URL biasa + ETag, reload berikutnya nol unduhan.
//
// Endpoint ini anonim: foto artikel garmen bukan data rahasia, dan ini pola yang sama
// dengan halaman publik /pack/{serial} dan /bundle/{serial}.
[ApiController]
[Route("api/article-photo")]
public class ArticlePhotoPublicController : ControllerBase
{
    // Kotak foto di kartu WIP 64x64 CSS px; 200 px masih tajam di tablet rasio 2x/3x.
    private const int ThumbnailWidth = 200;
    // Satu jam: reload dalam satu shift tidak menembak jaringan sama sekali, dan foto yang
    // diganti tetap muncul tanpa perlu operator membersihkan cache.
    private const int CacheSeconds = 3600;

    private readonly ArticlePhotoService _photoService;

    public ArticlePhotoPublicController(ArticlePhotoService photoService)
    {
        _photoService = photoService;
    }

    // BELUM DIPAKAI UI, TAPI SENGAJA DIPERTAHANKAN. Thumbnail di kartu WIP /station
    // dimatikan (markup-nya di-comment di StationDevice.razor) karena memuat foto tiap
    // kartu membuat halaman lambat dibuka. Endpoint ini tetap siap kalau thumbnail
    // dihidupkan lagi -- jangan dihapus karena "tidak ada pemanggilnya".
    [HttpGet("{articleId:int}/thumb")]
    public async Task<IActionResult> GetThumbnail(int articleId)
    {
        var result = await _photoService.GetPrimaryThumbnailAsync(articleId, ThumbnailWidth);
        return BuildResponse(result);
    }

    [HttpGet("{articleId:int}")]
    public async Task<IActionResult> GetOriginal(int articleId)
    {
        var result = await _photoService.GetPrimaryOriginalAsync(articleId);
        return BuildResponse(result);
    }

    private IActionResult BuildResponse((Stream Stream, string ContentType, string ETag)? result)
    {
        // Artikel tanpa foto wajar terjadi; kartu WIP menyembunyikan <img> lewat onerror.
        if (result is null) return NotFound();

        var (stream, contentType, etag) = result.Value;

        // private: thumbnail hanya perlu nangkring di cache tablet, bukan di proxy bersama.
        Response.Headers[HeaderNames.CacheControl] = $"private, max-age={CacheSeconds}";
        return File(stream, contentType, lastModified: null, entityTag: new EntityTagHeaderValue(etag));
    }
}

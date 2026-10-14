using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Prompt 71: penyaji foto SKU benang. Dipisah dari ThreadStockController karena
// SENGAJA tanpa [Authorize]/[RequireModule]: foto dipasang di <img src> (daftar SKU
// penuh thumbnail), dan tag img tidak bisa mengirim header Authorization. Yang bisa
// diminta hanya file di folder upload `thread/` dengan nama GUID acak, jadi tidak
// bisa dipakai menjelajah file lain -- pola sama dengan halaman publik QR
// (/b/{serial}, /t/{token}) yang juga mengandalkan kode acak.
//
// JANGAN menambah endpoint lain di controller ini.
[ApiController]
[Route("api/gudang/benang/photo")]
public class ThreadPhotoController : ControllerBase
{
    private readonly ThreadStockService _threadService;

    public ThreadPhotoController(ThreadStockService threadService)
    {
        _threadService = threadService;
    }

    [HttpGet("{fileName}")]
    public IActionResult Get(string fileName)
    {
        var result = _threadService.OpenPhoto(fileName);
        if (result is null) return NotFound();

        var (stream, contentType) = result.Value;
        return File(stream, contentType);
    }
}

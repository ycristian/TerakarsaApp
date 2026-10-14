using Microsoft.AspNetCore.Mvc;

namespace TerakarsaApp.API.Controllers;

// Prompt 76: dipakai app Android untuk memilih alamat server.
//
// App memanggil endpoint ini dengan timeout 1,5 detik saat dibuka / saat jaringan
// berubah: kalau alamat LOKAL menjawab, app memakai server pabrik; kalau tidak,
// jatuh ke alamat publik.
//
// SENGAJA tanpa autentikasi (belum login pun harus bisa memilih alamat) dan tidak
// menyentuh database -- ini satu-satunya perubahan di API untuk seri app Android.
[ApiController]
[Route("api/health")]
public class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult Get() => Ok(new
    {
        status = "ok",
        server = Environment.MachineName
    });
}

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Controllers;

// Prompt 61: master pola PDH TNI AD. {jenis} di rute = KEMEJA atau CELANA.
[ApiController]
[Route("api/tni/pola")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniPolaController : ControllerBase
{
    private readonly TniPolaService _polaService;

    public TniPolaController(TniPolaService polaService)
    {
        _polaService = polaService;
    }

    // created_by: user login bila ada, kalau tidak user sistem tni_system.
    private int CurrentUserId => this.TniActorUserId();

    // Jenis divalidasi di sini supaya SP tidak dipanggil dengan nilai ngawur.
    private static bool JenisValid(string? jenis) =>
        jenis is "KEMEJA" or "CELANA";

    [HttpGet]
    public async Task<IActionResult> GetList(
        [FromQuery] string jenis = "KEMEJA",
        [FromQuery] string? search = null,
        [FromQuery] bool hanyaAktif = false)
    {
        if (!JenisValid(jenis)) return BadRequest("Jenis harus KEMEJA atau CELANA.");

        var result = await _polaService.GetListAsync(jenis, search, hanyaAktif);
        return Ok(result);
    }

    [HttpGet("{jenis}/{id:int}")]
    public async Task<IActionResult> GetById(string jenis, int id)
    {
        if (!JenisValid(jenis)) return BadRequest("Jenis harus KEMEJA atau CELANA.");

        var pola = await _polaService.GetByIdAsync(jenis, id);
        if (pola is null) return NotFound();
        return Ok(pola);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] TniPolaSaveRequest request)
    {
        if (!JenisValid(request.JenisItem)) return BadRequest("Jenis harus KEMEJA atau CELANA.");
        if (string.IsNullOrWhiteSpace(request.Kode)) return BadRequest("Kode pola wajib diisi.");

        request.PolaId = null;
        var (success, error) = await _polaService.SaveAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut("{jenis}/{id:int}")]
    public async Task<IActionResult> Update(string jenis, int id, [FromBody] TniPolaSaveRequest request)
    {
        if (!JenisValid(jenis)) return BadRequest("Jenis harus KEMEJA atau CELANA.");
        if (string.IsNullOrWhiteSpace(request.Kode)) return BadRequest("Kode pola wajib diisi.");

        request.PolaId = id;
        request.JenisItem = jenis;
        var (success, error) = await _polaService.SaveAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut("{jenis}/{id:int}/aktif")]
    public async Task<IActionResult> SetAktif(string jenis, int id, [FromBody] TniPolaSetAktifRequest request)
    {
        if (!JenisValid(jenis)) return BadRequest("Jenis harus KEMEJA atau CELANA.");

        var (success, error) = await _polaService.SetAktifAsync(jenis, id, request.IsActive, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{jenis}/{id:int}")]
    public async Task<IActionResult> Delete(string jenis, int id)
    {
        if (!JenisValid(jenis)) return BadRequest("Jenis harus KEMEJA atau CELANA.");

        var (success, error) = await _polaService.DeleteAsync(jenis, id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

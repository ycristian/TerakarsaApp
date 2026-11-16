using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Controllers;

// Prompt 91: master kamera CCTV. Hanya user dengan module CCTV.
// Status kamera dibaca dari MediaMTX di sisi server; alamat MediaMTX tidak pernah
// dikirim ke klien.
[ApiController]
[Route("api/cctv/cameras")]
[Authorize]
[RequireModule("CCTV")]
public class CctvCameraController : ControllerBase
{
    private readonly CctvCameraService _cameraService;
    private readonly CctvStreamTokenService _tokens;

    public CctvCameraController(CctvCameraService cameraService, CctvStreamTokenService tokens)
    {
        _cameraService = cameraService;
        _tokens = tokens;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<IActionResult> GetList([FromQuery] bool onlyVisible = false, [FromQuery] string? area = null,
        CancellationToken ct = default)
        => Ok(await _cameraService.GetListAsync(onlyVisible, area, ct));

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id, CancellationToken ct)
    {
        var detail = await _cameraService.GetByIdAsync(id, ct);
        if (detail is null) return NotFound();
        return Ok(detail);
    }

    // Prompt 92: token stream pendek untuk satu kamera hidup (dipakai rute proxy ?t=).
    [HttpGet("{id:int}/stream-token")]
    public async Task<IActionResult> StreamToken(int id, CancellationToken ct)
    {
        var cam = await _cameraService.GetPathAsync(id, ct);
        if (cam is null) return NotFound("Kamera tidak ditemukan.");

        var (token, expiresAt) = _tokens.Create(cam.Value.MtxPath, CurrentUserId);
        return Ok(new CctvStreamTokenDto
        {
            CameraId = id,
            Path = cam.Value.MtxPath,
            Name = cam.Value.Name,
            Token = token,
            ExpiresAt = expiresAt
        });
    }

    // Prompt 94: kamera untuk transaksi -- dari resource dulu, kalau tidak ada dari divisi.
    [HttpGet("for-event")]
    public async Task<IActionResult> ForEvent([FromQuery] int? resourceId, [FromQuery] int? divisionId, CancellationToken ct)
        => Ok(await _cameraService.GetForEventAsync(resourceId, divisionId, ct));

    [HttpGet("lookup")]
    public async Task<IActionResult> Lookup(CancellationToken ct) => Ok(await _cameraService.GetLookupAsync(ct));

    [HttpPost]
    public Task<IActionResult> Create([FromBody] CctvCameraSaveRequest request)
        => Hasil(_cameraService.CreateAsync(request, CurrentUserId));

    [HttpPut("{id:int}")]
    public Task<IActionResult> Update(int id, [FromBody] CctvCameraSaveRequest request)
        => Hasil(_cameraService.UpdateAsync(id, request, CurrentUserId));

    [HttpDelete("{id:int}")]
    public Task<IActionResult> Delete(int id)
        => Hasil(_cameraService.DeleteAsync(id, CurrentUserId));

    [HttpPut("{id:int}/links")]
    public Task<IActionResult> SetLinks(int id, [FromBody] CctvCameraLinksRequest request)
        => Hasil(_cameraService.SetLinksAsync(id, request, CurrentUserId));

    // Ambil path dari MediaMTX -> tambah kamera yang belum ada.
    [HttpPost("sync")]
    public async Task<IActionResult> Sync(CancellationToken ct)
    {
        var hasil = await _cameraService.SyncAsync(CurrentUserId, ct);
        if (!hasil.Reachable)
            return BadRequest("Server rekaman tidak terjangkau — tidak ada kamera yang diambil.");
        return Ok(hasil);
    }

    private static async Task<IActionResult> Hasil(Task<(bool Success, string Error, int Id)> task)
    {
        var (success, error, id) = await task;
        if (!success) return new BadRequestObjectResult(error);
        return new OkObjectResult(id);
    }
}

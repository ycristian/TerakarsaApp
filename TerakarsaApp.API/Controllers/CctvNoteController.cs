using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Controllers;

// Catatan kejadian di rekaman CCTV (halaman Playback). Hak akses = module CCTV,
// sama dengan master kamera -- tidak ada permission baru.
[ApiController]
[Route("api/cctv/notes")]
[Authorize]
[RequireModule("CCTV")]
public class CctvNoteController : ControllerBase
{
    private readonly CctvNoteService _notes;

    public CctvNoteController(CctvNoteService notes)
    {
        _notes = notes;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    // ?date=yyyy-MM-dd (WIB) [&cameraId=] -> kejadian urut waktu.
    [HttpGet]
    public async Task<IActionResult> GetByDate([FromQuery] string? date, [FromQuery] int? cameraId, CancellationToken ct)
    {
        if (!DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
            return BadRequest("Tanggal wajib format yyyy-MM-dd.");
        return Ok(await _notes.GetByDateAsync(d, cameraId, ct));
    }

    [HttpGet("tags")]
    public async Task<IActionResult> Tags(CancellationToken ct) => Ok(await _notes.GetTagsAsync(ct));

    [HttpPost]
    public Task<IActionResult> Create([FromBody] CctvNoteSaveRequest request)
        => Hasil(_notes.CreateAsync(request, CurrentUserId));

    [HttpPut("{id:int}")]
    public Task<IActionResult> Update(int id, [FromBody] CctvNoteSaveRequest request)
        => Hasil(_notes.UpdateAsync(id, request, CurrentUserId));

    [HttpDelete("{id:int}")]
    public Task<IActionResult> Delete(int id)
        => Hasil(_notes.DeleteAsync(id, CurrentUserId));

    private static async Task<IActionResult> Hasil(Task<(bool Success, string Error, int Id)> task)
    {
        var (success, error, id) = await task;
        if (!success) return new BadRequestObjectResult(error);
        return new OkObjectResult(id);
    }
}

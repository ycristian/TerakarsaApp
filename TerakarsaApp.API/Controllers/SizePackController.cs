using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.SizePacks;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("MASTER_SIZE_PACK")]
public class SizePackController : ControllerBase
{
    private readonly SizePackService _sizePackService;

    public SizePackController(SizePackService sizePackService)
    {
        _sizePackService = sizePackService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] SizePackPagedRequest request)
    {
        var result = await _sizePackService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive()
    {
        var result = await _sizePackService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var sizePack = await _sizePackService.GetByIdAsync(id);
        if (sizePack is null) return NotFound();
        return Ok(sizePack);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] SizePackCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.SizePackName))
            return BadRequest("Nama size pack wajib diisi.");

        if (request.Details is null || request.Details.Count == 0)
            return BadRequest("Minimal 1 baris ukuran wajib diisi.");

        if (request.Details.Any(d => string.IsNullOrWhiteSpace(d.SizeName)))
            return BadRequest("Nama ukuran wajib diisi untuk setiap baris.");

        var (success, error, id) = await _sizePackService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new SizePackCreateResult { Id = id });
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] SizePackUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.SizePackName))
            return BadRequest("Nama size pack wajib diisi.");

        if (request.Details is null || request.Details.Count == 0)
            return BadRequest("Minimal 1 baris ukuran wajib diisi.");

        if (request.Details.Any(d => string.IsNullOrWhiteSpace(d.SizeName)))
            return BadRequest("Nama ukuran wajib diisi untuk setiap baris.");

        var (success, error) = await _sizePackService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _sizePackService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

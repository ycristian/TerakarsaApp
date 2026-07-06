using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Positions;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("MASTER_POSITION")]
public class PositionController : ControllerBase
{
    private readonly PositionService _positionService;

    public PositionController(PositionService positionService)
    {
        _positionService = positionService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] PositionPagedRequest request)
    {
        var result = await _positionService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive()
    {
        var result = await _positionService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var position = await _positionService.GetByIdAsync(id);
        if (position is null) return NotFound();
        return Ok(position);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] PositionCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.PositionName))
            return BadRequest("Nama jabatan wajib diisi.");

        var (success, error) = await _positionService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] PositionUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.PositionName))
            return BadRequest("Nama jabatan wajib diisi.");

        var (success, error) = await _positionService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _positionService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

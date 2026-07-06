using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Divisions;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("MASTER_DIVISION")]
public class DivisionController : ControllerBase
{
    private readonly DivisionService _divisionService;

    public DivisionController(DivisionService divisionService)
    {
        _divisionService = divisionService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] DivisionPagedRequest request)
    {
        var result = await _divisionService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var division = await _divisionService.GetByIdAsync(id);
        if (division is null) return NotFound();
        return Ok(division);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] DivisionCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DivisionCode))
            return BadRequest("Kode divisi wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.DivisionName))
            return BadRequest("Nama divisi wajib diisi.");

        var (success, error) = await _divisionService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] DivisionUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DivisionCode))
            return BadRequest("Kode divisi wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.DivisionName))
            return BadRequest("Nama divisi wajib diisi.");

        var (success, error) = await _divisionService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _divisionService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

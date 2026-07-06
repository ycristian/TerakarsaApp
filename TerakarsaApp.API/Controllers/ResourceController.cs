using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Resources;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("MASTER_RESOURCE")]
public class ResourceController : ControllerBase
{
    private readonly ResourceService _resourceService;

    public ResourceController(ResourceService resourceService)
    {
        _resourceService = resourceService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] ResourcePagedRequest request)
    {
        var result = await _resourceService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("active-by-division/{divisionId}")]
    public async Task<IActionResult> GetActiveByDivision(int divisionId)
    {
        var result = await _resourceService.GetActiveByDivisionAsync(divisionId);
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var resource = await _resourceService.GetByIdAsync(id);
        if (resource is null) return NotFound();
        return Ok(resource);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] ResourceCreateRequest request)
    {
        if (request.DivisionId <= 0)
            return BadRequest("Divisi wajib dipilih.");

        if (request.ResourceTypeId <= 0)
            return BadRequest("Tipe resource wajib dipilih.");

        if (string.IsNullOrWhiteSpace(request.ResourceName))
            return BadRequest("Nama resource wajib diisi.");

        var (success, error) = await _resourceService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] ResourceUpdateRequest request)
    {
        if (request.DivisionId <= 0)
            return BadRequest("Divisi wajib dipilih.");

        if (request.ResourceTypeId <= 0)
            return BadRequest("Tipe resource wajib dipilih.");

        if (string.IsNullOrWhiteSpace(request.ResourceName))
            return BadRequest("Nama resource wajib diisi.");

        var (success, error) = await _resourceService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _resourceService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

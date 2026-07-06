using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.ResourceTypes;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("MASTER_RESOURCE_TYPE")]
public class ResourceTypeController : ControllerBase
{
    private readonly ResourceTypeService _resourceTypeService;

    public ResourceTypeController(ResourceTypeService resourceTypeService)
    {
        _resourceTypeService = resourceTypeService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] ResourceTypePagedRequest request)
    {
        var result = await _resourceTypeService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive()
    {
        var result = await _resourceTypeService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var resourceType = await _resourceTypeService.GetByIdAsync(id);
        if (resourceType is null) return NotFound();
        return Ok(resourceType);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] ResourceTypeCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ResourceTypeCode))
            return BadRequest("Kode tipe resource wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.ResourceTypeName))
            return BadRequest("Nama tipe resource wajib diisi.");

        var (success, error) = await _resourceTypeService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] ResourceTypeUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ResourceTypeCode))
            return BadRequest("Kode tipe resource wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.ResourceTypeName))
            return BadRequest("Nama tipe resource wajib diisi.");

        var (success, error) = await _resourceTypeService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _resourceTypeService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

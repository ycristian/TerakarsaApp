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
    private readonly EmployeeService _employeeService;

    public ResourceController(ResourceService resourceService, EmployeeService employeeService)
    {
        _resourceService = resourceService;
        _employeeService = employeeService;
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

    // Prompt 32: dropdown "Penjahit" (employee) cascading di bawah dropdown Line di
    // BundleManager.razor -- module SAMA dengan active-by-division di atas (MASTER_RESOURCE)
    // supaya user yang sudah bisa pilih Line juga bisa pilih penjahitnya, tanpa perlu
    // MASTER_EMPLOYEE. Route di-override ke luar "api/resource" karena ini secara konsep
    // lookup employee, bukan resource.
    [HttpGet("~/api/employees/lookup")]
    public async Task<IActionResult> GetEmployeeLookup([FromQuery] int resourceId)
    {
        var result = await _employeeService.GetActiveByResourceAsync(resourceId);
        return Ok(result);
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

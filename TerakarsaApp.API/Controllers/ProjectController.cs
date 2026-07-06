using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("ORDER_PROJECT")]
public class ProjectController : ControllerBase
{
    private readonly ProjectService _projectService;

    public ProjectController(ProjectService projectService)
    {
        _projectService = projectService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] ProjectPagedRequest request)
    {
        var result = await _projectService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var project = await _projectService.GetByIdAsync(id);
        if (project is null) return NotFound();
        return Ok(project);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] ProjectCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ProjectName))
            return BadRequest("Nama project wajib diisi.");

        if (request.CustomerId <= 0)
            return BadRequest("Buyer wajib dipilih.");

        var (success, error, newId) = await _projectService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new ProjectCreateResult { Id = newId });
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] ProjectUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.ProjectName))
            return BadRequest("Nama project wajib diisi.");

        if (request.CustomerId <= 0)
            return BadRequest("Buyer wajib dipilih.");

        var (success, error) = await _projectService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _projectService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

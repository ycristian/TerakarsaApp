using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Modules;
using TerakarsaApp.Shared.Users;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ModuleController : ControllerBase
{
    private readonly ModuleService _moduleService;
    private readonly UserService _userService;

    public ModuleController(ModuleService moduleService, UserService userService)
    {
        _moduleService = moduleService;
        _userService = userService;
    }

    [HttpGet("my")]
    public async Task<IActionResult> GetMyModules()
    {
        var userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        var modules = await _moduleService.GetByUserIdAsync(userId);
        return Ok(modules);
    }

    [HttpPost("paged")]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-setting")]
    public async Task<IActionResult> GetPaged([FromBody] ModulePagedRequest request)
    {
        var result = await _moduleService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-setting")]
    public async Task<IActionResult> Create([FromBody] ModuleCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Code))
            return BadRequest("Code wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.Name))
            return BadRequest("Nama module wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.Category))
            return BadRequest("Category wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.Route))
            return BadRequest("Route wajib diisi.");

        await _moduleService.CreateAsync(request);
        return Ok();
    }

    [HttpPut]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-setting")]
    public async Task<IActionResult> Update([FromBody] ModuleUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Code))
            return BadRequest("Code wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.Name))
            return BadRequest("Nama module wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.Category))
            return BadRequest("Category wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.Route))
            return BadRequest("Route wajib diisi.");

        await _moduleService.UpdateAsync(request);
        return Ok();
    }

    [HttpDelete("{id}")]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-setting")]
    public async Task<IActionResult> Delete(int id)
    {
        await _moduleService.DeleteAsync(id);
        return Ok();
    }

    [HttpGet("access/{userId}")]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-access")]
    public async Task<IActionResult> GetAccess(int userId)
    {
        var moduleIds = await _moduleService.GetAssignedIdsAsync(userId);
        return Ok(moduleIds);
    }

    [HttpPut("access")]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-access")]
    public async Task<IActionResult> SetAccess([FromBody] UserModuleAssignRequest request)
    {
        await _moduleService.AssignAsync(request);
        return Ok();
    }

    // Daftar module & user untuk keperluan layar Module Access — sengaja terpisah dari
    // endpoint "paged" (privilege module-setting) dan UserController (privilege users),
    // supaya admin yang hanya punya privilege module-access tetap bisa mengelola akses.
    [HttpGet("all")]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-access")]
    public async Task<IActionResult> GetAll()
    {
        var result = await _moduleService.GetPagedAsync(new ModulePagedRequest { PageSize = 1000 });
        return Ok(result.Items);
    }

    [HttpGet("users")]
    [Authorize(Roles = "Admin")]
    [RequireModule("module-access")]
    public async Task<IActionResult> GetUsersForAssignment()
    {
        var result = await _userService.GetPagedAsync(new UserPagedRequest { PageSize = 1000 });
        return Ok(result.Items);
    }
}

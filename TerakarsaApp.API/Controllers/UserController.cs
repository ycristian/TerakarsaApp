using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Users;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Roles = "Admin")]
[RequireModule("users")]
public class UserController : ControllerBase
{
    private readonly UserService _userService;

    public UserController(UserService userService)
    {
        _userService = userService;
    }

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] UserPagedRequest request)
    {
        var result = await _userService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] UserCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Username) || request.Username.Length < 3)
            return BadRequest("Username minimal 3 karakter.");

        if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 6)
            return BadRequest("Password minimal 6 karakter.");

        if (string.IsNullOrWhiteSpace(request.FullName))
            return BadRequest("Nama lengkap wajib diisi.");

        if (request.Role != "Admin" && request.Role != "User")
            return BadRequest("Role harus Admin atau User.");

        await _userService.CreateAsync(request);
        return Ok();
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] UserUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.FullName))
            return BadRequest("Nama lengkap wajib diisi.");

        if (request.Role != "Admin" && request.Role != "User")
            return BadRequest("Role harus Admin atau User.");

        await _userService.UpdateAsync(request);
        return Ok();
    }

    [HttpPut("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] UserResetPasswordRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.NewPassword) || request.NewPassword.Length < 6)
            return BadRequest("Password minimal 6 karakter.");

        await _userService.ResetPasswordAsync(request);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _userService.DeleteAsync(id);
        return Ok();
    }
}

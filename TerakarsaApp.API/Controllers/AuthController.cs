using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Auth;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly AuthService _authService;

    public AuthController(AuthService authService)
    {
        _authService = authService;
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Username) ||
            string.IsNullOrWhiteSpace(request.Password))
            return BadRequest("Username dan password wajib diisi.");

        var response = await _authService.LoginAsync(request);

        if (response is null)
            return Unauthorized("Username atau password salah.");

        return Ok(response);
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh([FromBody] RefreshTokenRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.RefreshToken))
            return BadRequest("Refresh token wajib diisi.");

        var response = await _authService.RefreshAsync(request.RefreshToken);

        if (response is null)
            return Unauthorized("Refresh token tidak valid atau sudah kedaluwarsa.");

        return Ok(response);
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout([FromBody] RefreshTokenRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.RefreshToken))
            await _authService.RevokeRefreshTokenAsync(request.RefreshToken);

        return Ok();
    }
}
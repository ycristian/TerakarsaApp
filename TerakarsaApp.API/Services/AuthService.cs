using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Auth;

namespace TerakarsaApp.API.Services;

public class AuthService
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;
    private readonly ModuleService _moduleService;

    public AuthService(AppDbContext db, IConfiguration config, ModuleService moduleService)
    {
        _db = db;
        _config = config;
        _moduleService = moduleService;
    }

    public async Task<LoginResponse?> LoginAsync(LoginRequest request)
    {
        var usernameParam = new SqlParameter("@Username", request.Username);

        var result = await _db.Database
            .SqlQueryRaw<UserResult>(
                "EXEC SIS_User_GetByUsername @Username = @Username",
                usernameParam)
            .ToListAsync();

        var user = result.FirstOrDefault();
        if (user is null) return null;
        if (!PasswordHasher.Verify(request.Password, user.Password)) return null;

        return await IssueTokensAsync(user);
    }

    public async Task<LoginResponse?> RefreshAsync(string refreshToken)
    {
        var tokenParam = new SqlParameter("@Token", refreshToken);

        var result = await _db.Database
            .SqlQueryRaw<RefreshTokenResult>(
                "EXEC SIS_RefreshToken_Manage @Action = 'GET', @Token = @Token",
                tokenParam)
            .ToListAsync();

        var stored = result.FirstOrDefault();
        if (stored is null) return null;
        if (stored.RevokedAt is not null) return null;
        if (stored.TokenExpiresAt < DateTime.UtcNow) return null;
        if (!stored.IsActive) return null;

        // Rotasi: token lama dicabut, token baru diterbitkan setiap kali refresh dipakai.
        await RevokeRefreshTokenAsync(refreshToken);

        return await IssueTokensAsync(new UserResult
        {
            Id = stored.UserId,
            Username = stored.Username,
            FullName = stored.FullName,
            Role = stored.Role,
            IsActive = stored.IsActive,
            Password = string.Empty
        });
    }

    public async Task RevokeRefreshTokenAsync(string refreshToken)
    {
        var tokenParam = new SqlParameter("@Token", refreshToken);
        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_RefreshToken_Manage @Action = 'REVOKE', @Token = @Token",
            tokenParam);
    }

    private async Task<LoginResponse> IssueTokensAsync(UserResult user)
    {
        var accessExpireMinutes = int.Parse(_config["JwtSettings:ExpireMinutes"]!);
        var refreshExpireDays = int.Parse(_config["JwtSettings:RefreshExpireDays"]!);

        var moduleCodes = (await _moduleService.GetByUserIdAsync(user.Id)).Select(m => m.Code);
        var token = GenerateJwt(user, moduleCodes);
        var refreshToken = GenerateRefreshToken();
        var refreshExpiresAt = DateTime.UtcNow.AddDays(refreshExpireDays);

        var userIdParam = new SqlParameter("@UserId", user.Id);
        var tokenParam = new SqlParameter("@Token", refreshToken);
        var expiresParam = new SqlParameter("@ExpiresAt", refreshExpiresAt);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_RefreshToken_Manage @Action = 'INSERT', @UserId = @UserId, @Token = @Token, @ExpiresAt = @ExpiresAt",
            userIdParam, tokenParam, expiresParam);

        return new LoginResponse
        {
            Token = token,
            Expires = DateTime.UtcNow.AddMinutes(accessExpireMinutes),
            RefreshToken = refreshToken
        };
    }

    private static string GenerateRefreshToken()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
    }

    private string GenerateJwt(UserResult user, IEnumerable<string> moduleCodes)
    {
        var key = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(_config["JwtSettings:Key"]!));

        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Username),
            new Claim(ClaimTypes.GivenName, user.FullName),
            new Claim(ClaimTypes.Role, user.Role)
        };
        claims.AddRange(moduleCodes.Select(code => new Claim("module", code)));

        var token = new JwtSecurityToken(
            issuer: _config["JwtSettings:Issuer"],
            audience: _config["JwtSettings:Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(
                int.Parse(_config["JwtSettings:ExpireMinutes"]!)),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256)
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}

// Model internal untuk mapping hasil SP
public class UserResult
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public bool IsActive { get; set; }
}

public class RefreshTokenResult
{
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime TokenExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
}
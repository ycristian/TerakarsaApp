using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Json;
using TerakarsaApp.Shared.Auth;

namespace TerakarsaApp.Client.Auth;

public class AuthApiService
{
    private readonly HttpClient _http;
    private readonly CustomAuthStateProvider _authStateProvider;

    public AuthApiService(
        IHttpClientFactory httpFactory,
        Microsoft.AspNetCore.Components.Authorization.AuthenticationStateProvider authStateProvider)
    {
        // Client "AuthAPI" sengaja tidak memakai AuthorizedHandler, agar gagal login/refresh
        // tidak ikut memicu logika refresh-token/redirect yang ada di handler tersebut.
        _http = httpFactory.CreateClient("AuthAPI");
        _authStateProvider = (CustomAuthStateProvider)authStateProvider;
    }

    public async Task<(bool Success, string? Error)> LoginAsync(string username, string password)
    {
        var response = await _http.PostAsJsonAsync("api/auth/login", new LoginRequest
        {
            Username = username,
            Password = password
        });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Login gagal." : error);
        }

        var result = await response.Content.ReadFromJsonAsync<LoginResponse>();
        if (result is null) return (false, "Response tidak valid.");

        await _authStateProvider.MarkUserAsAuthenticated(result.Token, result.RefreshToken);

        return (true, null);
    }

    public async Task LogoutAsync()
    {
        var refreshToken = await _authStateProvider.GetRefreshToken();
        if (!string.IsNullOrWhiteSpace(refreshToken))
        {
            try
            {
                await _http.PostAsJsonAsync("api/auth/logout", new RefreshTokenRequest { RefreshToken = refreshToken });
            }
            catch (HttpRequestException)
            {
                // Best-effort revoke di server; logout lokal tetap lanjut walau API tidak bisa dihubungi.
            }
        }

        await _authStateProvider.MarkUserAsLoggedOut();
    }

    public async Task<bool> TryRefreshTokenAsync()
    {
        var refreshToken = await _authStateProvider.GetRefreshToken();
        if (string.IsNullOrWhiteSpace(refreshToken)) return false;

        var response = await _http.PostAsJsonAsync("api/auth/refresh", new RefreshTokenRequest { RefreshToken = refreshToken });
        if (!response.IsSuccessStatusCode) return false;

        var result = await response.Content.ReadFromJsonAsync<LoginResponse>();
        if (result is null) return false;

        await _authStateProvider.MarkUserAsAuthenticated(result.Token, result.RefreshToken);
        return true;
    }

    public async Task InitializeAsync()
    {
        var token = await _authStateProvider.GetAccessToken();
        if (string.IsNullOrWhiteSpace(token)) return;

        if (IsExpired(token))
            await TryRefreshTokenAsync();
    }

    private static bool IsExpired(string jwt)
    {
        var handler = new JwtSecurityTokenHandler();
        return handler.ReadJwtToken(jwt).ValidTo < DateTime.UtcNow;
    }
}
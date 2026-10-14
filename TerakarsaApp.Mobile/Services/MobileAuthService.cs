using System.Net.Http.Json;
using TerakarsaApp.Shared.Auth;
using TerakarsaApp.Shared.Modules;

namespace TerakarsaApp.Mobile.Services;

// Prompt 76: login native app Android. Memakai endpoint YANG SAMA dengan web
// (api/auth/login, api/auth/refresh, api/auth/logout) dan DTO bersama dari
// TerakarsaApp.Shared -- mekanisme auth API tidak diubah sama sekali.
//
// Token disimpan di SecureStorage (bukan Preferences). Nama key-nya SENGAJA sama
// dengan yang dipakai web di localStorage ("authToken" / "refreshToken") supaya
// penyuntikan token ke WebView (WebPage) tidak perlu daftar nama terpisah.
public class MobileAuthService
{
    public const string TokenKey = "authToken";
    public const string RefreshTokenKey = "refreshToken";

    private readonly ServerResolver _resolver;

    public MobileAuthService(ServerResolver resolver)
    {
        _resolver = resolver;
    }

    public string? AccessToken { get; private set; }
    public string? RefreshToken { get; private set; }
    public List<ModuleDto> Modules { get; private set; } = new();

    public bool SudahLogin => !string.IsNullOrWhiteSpace(AccessToken);

    public async Task MuatTokenTersimpanAsync()
    {
        try
        {
            AccessToken = await SecureStorage.GetAsync(TokenKey);
            RefreshToken = await SecureStorage.GetAsync(RefreshTokenKey);
        }
        catch (Exception)
        {
            // SecureStorage bisa gagal kalau keystore perangkat bermasalah -- anggap
            // belum login, user tinggal login ulang.
            AccessToken = null;
            RefreshToken = null;
        }
    }

    public async Task<(bool Success, string Error)> LoginAsync(string username, string password)
    {
        try
        {
            using var http = ServerResolver.BuatHttpClientAktif(_resolver);

            var response = await http.PostAsJsonAsync("api/auth/login",
                new LoginRequest { Username = username, Password = password });

            if (!response.IsSuccessStatusCode)
            {
                var pesan = (await response.Content.ReadAsStringAsync()).Trim().Trim('"');
                return (false, string.IsNullOrWhiteSpace(pesan) ? "Login gagal." : pesan);
            }

            var hasil = await response.Content.ReadFromJsonAsync<LoginResponse>();
            if (hasil is null || string.IsNullOrWhiteSpace(hasil.Token))
                return (false, "Server tidak mengirim token.");

            await SimpanTokenAsync(hasil.Token, hasil.RefreshToken);
            await MuatModuleAsync();

            return (true, string.Empty);
        }
        catch (Exception ex)
        {
            return (false, $"Tidak bisa menghubungi server: {ex.Message}");
        }
    }

    // Rotasi manual, pola sama dengan AuthApiService di web: refresh token lama
    // dicabut server dan diganti yang baru.
    public async Task<bool> RefreshAsync()
    {
        if (string.IsNullOrWhiteSpace(RefreshToken)) return false;

        try
        {
            using var http = ServerResolver.BuatHttpClientAktif(_resolver);

            var response = await http.PostAsJsonAsync("api/auth/refresh",
                new RefreshTokenRequest { RefreshToken = RefreshToken });

            if (!response.IsSuccessStatusCode)
            {
                await LogoutAsync(hubungiServer: false);
                return false;
            }

            var hasil = await response.Content.ReadFromJsonAsync<LoginResponse>();
            if (hasil is null || string.IsNullOrWhiteSpace(hasil.Token))
            {
                await LogoutAsync(hubungiServer: false);
                return false;
            }

            await SimpanTokenAsync(hasil.Token, hasil.RefreshToken);
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    public async Task<bool> MuatModuleAsync()
    {
        if (!SudahLogin) return false;

        try
        {
            using var http = ServerResolver.BuatHttpClientAktif(_resolver);
            http.DefaultRequestHeaders.Authorization = new("Bearer", AccessToken);

            var response = await http.GetAsync("api/module/my");

            if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            {
                if (!await RefreshAsync()) return false;
                return await MuatModuleAsync();
            }

            if (!response.IsSuccessStatusCode) return false;

            Modules = await response.Content.ReadFromJsonAsync<List<ModuleDto>>() ?? new();
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    public bool PunyaModule(string code) =>
        Modules.Any(m => string.Equals(m.Code, code, StringComparison.OrdinalIgnoreCase));

    public async Task LogoutAsync(bool hubungiServer = true)
    {
        if (hubungiServer && !string.IsNullOrWhiteSpace(RefreshToken))
        {
            try
            {
                using var http = ServerResolver.BuatHttpClientAktif(_resolver);
                await http.PostAsJsonAsync("api/auth/logout",
                    new RefreshTokenRequest { RefreshToken = RefreshToken });
            }
            catch (Exception)
            {
                // Logout lokal tetap dilanjutkan walau server tidak terjangkau.
            }
        }

        AccessToken = null;
        RefreshToken = null;
        Modules = new();

        try
        {
            SecureStorage.Remove(TokenKey);
            SecureStorage.Remove(RefreshTokenKey);
        }
        catch (Exception)
        {
        }
    }

    private async Task SimpanTokenAsync(string token, string refreshToken)
    {
        AccessToken = token;
        RefreshToken = refreshToken;

        try
        {
            await SecureStorage.SetAsync(TokenKey, token);
            await SecureStorage.SetAsync(RefreshTokenKey, refreshToken ?? string.Empty);
        }
        catch (Exception)
        {
            // Token tetap dipakai selama app hidup walau gagal disimpan.
        }
    }
}

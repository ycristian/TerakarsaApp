using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace TerakarsaApp.Mobile.Services;

public class HealthDto
{
    public string? Status { get; set; }
    public string? Server { get; set; }
}

// Prompt 76: menentukan alamat server yang dipakai app.
//
// Mode Auto: cek GET {apiBase(lokal)}/api/health (timeout 1,5 s) saat start, saat
// jaringan berubah, dan saat app kembali aktif. Jalan -> pakai alamat LOKAL;
// gagal -> pakai alamat PUBLIK.
//
// CATATAN alamat: prompt menulis "GET {LocalBaseUrl}/api/health", tapi LocalBaseUrl
// di app ini adalah alamat WEB (yang dibuka WebView), sedangkan API berada di port
// lain. Alamat API diturunkan dengan aturan yang SAMA PERSIS seperti
// TerakarsaApp.Client/Program.cs (ResolveApiBaseUrl) supaya app dan web selalu
// menunjuk API yang sama: host *.terakarsa.id -> https://api.terakarsa.id,
// selain itu host yang sama dengan port 5281 (http) / 7130 (https).
public class ServerResolver
{
    public const string ModeAuto = "Auto";
    public const string ModeLocal = "Local";
    public const string ModePublic = "Public";

    private static readonly TimeSpan HealthTimeout = TimeSpan.FromMilliseconds(1500);

    public event Action? Changed;

    // Alamat web yang sedang dipakai (tanpa garis miring di akhir).
    public string ActiveBaseUrl { get; private set; } = AppPrefs.PublicBaseUrl;

    public bool IsLocal { get; private set; }

    // Badge kecil di layar pilih tujuan & Setting.
    public string BadgeLabel => IsLocal ? "Lokal" : "Internet";

    public string ActiveApiBaseUrl => ApiBaseUrlFrom(ActiveBaseUrl);

    public async Task<bool> RefreshAsync()
    {
        var sebelum = ActiveBaseUrl;
        var sebelumLokal = IsLocal;

        var mode = AppPrefs.UrlMode;
        var lokal = AppPrefs.LocalBaseUrl;
        var publik = AppPrefs.PublicBaseUrl;

        if (mode == ModeLocal && !string.IsNullOrWhiteSpace(lokal))
        {
            ActiveBaseUrl = lokal;
            IsLocal = true;
        }
        else if (mode == ModePublic || string.IsNullOrWhiteSpace(lokal))
        {
            ActiveBaseUrl = publik;
            IsLocal = false;
        }
        else
        {
            var hidup = await CekHealthAsync(lokal);
            ActiveBaseUrl = hidup ? lokal : publik;
            IsLocal = hidup;
        }

        var berubah = sebelum != ActiveBaseUrl || sebelumLokal != IsLocal;
        if (berubah) Changed?.Invoke();
        return berubah;
    }

    public async Task<(bool Ok, string Pesan)> UjiAsync(string webBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(webBaseUrl)) return (false, "Alamat belum diisi.");

        try
        {
            using var http = BuatHttpClient(webBaseUrl);
            http.Timeout = HealthTimeout;

            var hasil = await http.GetFromJsonAsync<HealthDto>("api/health");
            return hasil?.Status == "ok"
                ? (true, $"OK — {hasil.Server}")
                : (false, "Server menjawab tapi bukan TMOS.");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    private async Task<bool> CekHealthAsync(string webBaseUrl)
    {
        var (ok, _) = await UjiAsync(webBaseUrl);
        return ok;
    }

    // HttpClient untuk API yang diturunkan dari alamat web yang diberikan.
    // Sertifikat self-signed server LOKAL hanya diterima kalau fingerprint-nya cocok
    // dengan yang tersimpan (AppPrefs.LocalCertSha256) DAN host-nya memang host lokal.
    public static HttpClient BuatHttpClient(string webBaseUrl)
    {
        var apiBase = ApiBaseUrlFrom(webBaseUrl);
        var handler = new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = (_, cert, _, errors) =>
            {
                if (errors == System.Net.Security.SslPolicyErrors.None) return true;
                return cert is not null && CocokSidikJariLokal(cert, apiBase);
            }
        };

        return new HttpClient(handler)
        {
            BaseAddress = new Uri(apiBase),
            Timeout = TimeSpan.FromSeconds(30)
        };
    }

    public static HttpClient BuatHttpClientAktif(ServerResolver resolver) =>
        BuatHttpClient(resolver.ActiveBaseUrl);

    // Dipakai juga oleh WebView (lihat Platforms/Android/TerakarsaWebViewClient).
    public static bool CocokSidikJariLokal(X509Certificate2 cert, string? apiBaseUrl = null)
    {
        var tersimpan = AppPrefs.LocalCertSha256;
        if (string.IsNullOrEmpty(tersimpan)) return false;

        // Hanya untuk host server lokal.
        var hostLokal = HostDari(AppPrefs.LocalBaseUrl);
        if (string.IsNullOrEmpty(hostLokal)) return false;

        if (!string.IsNullOrEmpty(apiBaseUrl))
        {
            var hostDiminta = HostDari(apiBaseUrl);
            if (!string.Equals(hostDiminta, hostLokal, StringComparison.OrdinalIgnoreCase)) return false;
        }

        return string.Equals(SidikJari(cert), tersimpan, StringComparison.OrdinalIgnoreCase);
    }

    public static string SidikJari(X509Certificate2 cert) =>
        Convert.ToHexString(SHA256.HashData(cert.RawData));

    public static string SidikJari(byte[] derBytes) =>
        Convert.ToHexString(SHA256.HashData(derBytes));

    public static string? HostDari(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri.Host : null;

    // SAMA dengan TerakarsaApp.Client/Program.cs ResolveApiBaseUrl -- kalau yang di sana
    // berubah, ubah juga di sini.
    public static string ApiBaseUrlFrom(string webBaseUrl)
    {
        if (!Uri.TryCreate(webBaseUrl, UriKind.Absolute, out var uri))
            return AppPrefs.DefaultPublicBaseUrl.Replace("app.", "api.") + "/";

        if (uri.Host.EndsWith("terakarsa.id", StringComparison.OrdinalIgnoreCase))
            return "https://api.terakarsa.id/";

        var apiPort = uri.Scheme == "https" ? 7130 : 5281;
        return $"{uri.Scheme}://{uri.Host}:{apiPort}/";
    }
}

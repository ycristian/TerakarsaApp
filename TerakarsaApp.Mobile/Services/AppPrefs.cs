namespace TerakarsaApp.Mobile.Services;

// Prompt 76: pengaturan app yang disimpan di perangkat.
//
// Preferences = pengaturan biasa (alamat server, mode, fingerprint sertifikat).
// Token login TIDAK disimpan di sini -- lihat MobileAuthService (SecureStorage).
public static class AppPrefs
{
    // Alamat WEB (bukan API): yang dibuka di WebView. Alamat API diturunkan dari ini
    // dengan aturan yang SAMA seperti TerakarsaApp.Client (lihat ServerResolver).
    public const string DefaultPublicBaseUrl = "https://app.terakarsa.id";

    public static string LocalBaseUrl
    {
        get => Preferences.Get(nameof(LocalBaseUrl), string.Empty);
        set => Preferences.Set(nameof(LocalBaseUrl), (value ?? string.Empty).Trim().TrimEnd('/'));
    }

    public static string PublicBaseUrl
    {
        get => Preferences.Get(nameof(PublicBaseUrl), DefaultPublicBaseUrl);
        set => Preferences.Set(nameof(PublicBaseUrl),
            string.IsNullOrWhiteSpace(value) ? DefaultPublicBaseUrl : value.Trim().TrimEnd('/'));
    }

    // Auto | Local | Public
    public static string UrlMode
    {
        get => Preferences.Get(nameof(UrlMode), "Auto");
        set => Preferences.Set(nameof(UrlMode), value is "Local" or "Public" ? value : "Auto");
    }

    // Fingerprint SHA-256 sertifikat server lokal (self-signed), format hex tanpa pemisah.
    // Hanya dipakai untuk host LocalBaseUrl -- alamat publik tetap validasi normal.
    public static string LocalCertSha256
    {
        get => Preferences.Get(nameof(LocalCertSha256), string.Empty);
        set => Preferences.Set(nameof(LocalCertSha256), Normalisasi(value));
    }

    // Buang spasi/titik dua dan samakan ke huruf besar supaya perbandingan tidak
    // tergantung format yang ditempel user (openssl memakai "AA:BB:...").
    public static string Normalisasi(string? sidikJari) =>
        new string((sidikJari ?? string.Empty)
            .Where(char.IsLetterOrDigit)
            .Select(char.ToUpperInvariant)
            .ToArray());
}

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

    // ---------------------------------------------------------------------------------
    // Prompt 86: Mode Stasiun -- app langsung membuka /station tanpa login user. Kode login
    // stasiun (kode terkunci 10 karakter dari Kelola Stasiun), ID, dan nama perangkat
    // disuntik ke localStorage WebView; klaim, peringatan ambil alih, dan login ulang
    // otomatis semuanya dikerjakan halaman web (Prompt 85). App TIDAK menyimpan stationToken.
    // Preferences biasa (bukan SecureStorage): owner harus bisa melihat & mengedit kodenya.

    public const string PesanKodeStasiunTidakValid =
        "Pakai kode login terkunci (10 karakter) dari menu Kelola Stasiun. Kode pairing 5 huruf hanya berlaku sekali.";

    public static bool StationMode
    {
        get => Preferences.Get(nameof(StationMode), false);
        set => Preferences.Set(nameof(StationMode), value);
    }

    public static string StationLoginCode
    {
        get => Preferences.Get(nameof(StationLoginCode), string.Empty);
        set => Preferences.Set(nameof(StationLoginCode), Normalisasi(value));
    }

    public static string DefaultStationDeviceName =>
        $"{DeviceInfo.Current.Manufacturer} {DeviceInfo.Current.Model}".Trim();

    // Muncul di peringatan "DIPAKAI|" di perangkat lain dan di daftar Kelola Stasiun.
    public static string StationDeviceName
    {
        get
        {
            var nama = Preferences.Get(nameof(StationDeviceName), string.Empty);
            return string.IsNullOrWhiteSpace(nama) ? DefaultStationDeviceName : nama;
        }
        set => Preferences.Set(nameof(StationDeviceName), (value ?? string.Empty).Trim());
    }

    // Dibuat sekali, tidak bisa diedit. Terpisah dari PrintPrefs.DeviceCode (print service
    // punya siklus daftar ulang sendiri). Server mengenali "perangkat yang sama" dari ID ini,
    // jadi login ulang perangkat ini tidak memunculkan peringatan ambil alih.
    public static string StationDeviceId
    {
        get
        {
            var id = Preferences.Get(nameof(StationDeviceId), string.Empty);
            if (string.IsNullOrEmpty(id))
            {
                id = Guid.NewGuid().ToString("N");
                Preferences.Set(nameof(StationDeviceId), id);
            }
            return id;
        }
    }

    public static bool KodeStasiunValid(string? kode) =>
        kode is { Length: 10 } && kode.All(c => c is >= 'A' and <= 'Z' or >= '0' and <= '9');

    // Mode Stasiun hanya aktif kalau kodenya juga valid -- kalau tidak, app tetap ke alur login.
    public static bool StationModeSiap => StationMode && KodeStasiunValid(StationLoginCode);

    // Isi QR modal "Kode Login" = "{web}/station/{kode}"; teks mentah juga diterima.
    public static string AmbilKodeDariQr(string? isi)
    {
        var teks = (isi ?? string.Empty).Trim();

        var posisi = teks.IndexOf("/station/", StringComparison.OrdinalIgnoreCase);
        if (posisi >= 0)
        {
            teks = teks[(posisi + "/station/".Length)..];
            var akhir = teks.IndexOfAny(['/', '?', '#']);
            if (akhir >= 0) teks = teks[..akhir];
        }

        return Normalisasi(teks);
    }
}

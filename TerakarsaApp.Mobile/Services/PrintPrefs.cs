namespace TerakarsaApp.Mobile.Services;

// Prompt 77: pengaturan print service di HP.
//
// device_token TIDAK PERNAH disimpan di Preferences -- hanya SecureStorage
// (lihat TokenAsync/SimpanTokenAsync).
public static class PrintPrefs
{
    private const string TokenKey = "printDeviceToken";

    public static string DeviceCode
    {
        get => Preferences.Get(nameof(DeviceCode), string.Empty);
        set => Preferences.Set(nameof(DeviceCode), (value ?? string.Empty).Trim().ToUpperInvariant());
    }

    public static string DeviceName
    {
        get => Preferences.Get(nameof(DeviceName), "HP Gudang");
        set => Preferences.Set(nameof(DeviceName), string.IsNullOrWhiteSpace(value) ? "HP Gudang" : value.Trim());
    }

    // Nama + MAC printer Bluetooth yang dipilih dari daftar pairing.
    public static string PrinterName
    {
        get => Preferences.Get(nameof(PrinterName), string.Empty);
        set => Preferences.Set(nameof(PrinterName), value ?? string.Empty);
    }

    public static string PrinterMac
    {
        get => Preferences.Get(nameof(PrinterMac), string.Empty);
        set => Preferences.Set(nameof(PrinterMac), value ?? string.Empty);
    }

    // Switch "Aktif" di halaman Print Service -> foreground service jalan/berhenti.
    public static bool Aktif
    {
        get => Preferences.Get(nameof(Aktif), false);
        set => Preferences.Set(nameof(Aktif), value);
    }

    public static int PollSeconds
    {
        get => Preferences.Get(nameof(PollSeconds), 3);
        set => Preferences.Set(nameof(PollSeconds), value < 1 ? 3 : value);
    }

    public static bool SudahTerdaftar => !string.IsNullOrWhiteSpace(DeviceCode);

    public static async Task<string?> TokenAsync()
    {
        try
        {
            return await SecureStorage.GetAsync(TokenKey);
        }
        catch (Exception)
        {
            return null;
        }
    }

    public static async Task SimpanTokenAsync(string token)
    {
        try
        {
            await SecureStorage.SetAsync(TokenKey, token);
        }
        catch (Exception)
        {
            // Kalau keystore perangkat bermasalah, token tidak tersimpan -- admin
            // tinggal mendaftarkan ulang HP ini.
        }
    }

    public static void HapusToken()
    {
        try
        {
            SecureStorage.Remove(TokenKey);
        }
        catch (Exception)
        {
        }
    }
}

// Log 50 baris terakhir, dibagi antara foreground service dan halaman Setting.
public static class PrintLog
{
    private const int Maks = 50;
    private static readonly List<string> Baris = new();
    private static readonly object Kunci = new();

    public static event Action? Changed;

    public static void Tulis(string pesan)
    {
        lock (Kunci)
        {
            Baris.Insert(0, $"{DateTime.Now:HH:mm:ss}  {pesan}");
            if (Baris.Count > Maks) Baris.RemoveRange(Maks, Baris.Count - Maks);
        }

        Changed?.Invoke();
    }

    public static List<string> Semua()
    {
        lock (Kunci) return Baris.ToList();
    }
}

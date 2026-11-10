using System.Globalization;

namespace TerakarsaApp.Client;

// Prompt 85: tampilan kehadiran perangkat stasiun -- dipakai peringatan ambil alih di /station
// dan daftar Kelola Stasiun. Waktu dari server (SYSDATETIME, tanpa offset) dibandingkan dengan
// jam perangkat; keduanya WIB.
public static class StationDisplay
{
    public const string TakeoverPrefix = "DIPAKAI|";

    public static string FormatLastSeen(DateTime? at)
    {
        if (at is null) return "tidak diketahui";

        var diff = DateTime.Now - at.Value;
        if (diff.TotalMinutes < 1) return "baru saja";
        if (diff.TotalMinutes < 60) return $"{(int)diff.TotalMinutes} menit lalu";
        if (diff.TotalHours < 24) return $"{(int)diff.TotalHours} jam lalu";
        return at.Value.ToString("dd MMM HH:mm", new CultureInfo("id-ID"));
    }

    // Error klaim "DIPAKAI|nama|yyyy-MM-ddTHH:mm:ss" (SIS_Station_Manage CLAIM_PAIRING) ->
    // nama perangkat pemegang + waktu terakhir aktif. false kalau bukan error DIPAKAI.
    public static bool TryParseTakeover(string? error, out string holder, out DateTime? lastSeen)
    {
        holder = string.Empty;
        lastSeen = null;
        if (string.IsNullOrEmpty(error) || !error.StartsWith(TakeoverPrefix, StringComparison.Ordinal))
            return false;

        var parts = error.Split('|');
        holder = parts.Length > 1 && !string.IsNullOrWhiteSpace(parts[1]) ? parts[1] : "Perangkat lama";
        if (parts.Length > 2 && DateTime.TryParse(parts[2], CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
            lastSeen = parsed;
        return true;
    }
}

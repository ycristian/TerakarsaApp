using System.Collections.Concurrent;

namespace TerakarsaApp.API.Services;

// Prompt 85: pembatas TOUCH (stations.last_seen_at + adopsi perangkat lama) supaya polling
// stasiun tiap 15 detik tidak menulis ke DB di setiap request -- paling sering sekali per
// 60 detik per stasiun. Singleton: state dibagi semua request. Hilang saat API restart, dan
// itu tidak masalah (TOUCH berikutnya cukup terjadi lebih cepat).
public class StationPresenceTracker
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(60);

    private readonly ConcurrentDictionary<int, DateTime> _lastTouch = new();

    // true = pemanggil sebaiknya TOUCH sekarang. Langsung mencatat waktu supaya request
    // paralel dari stasiun yang sama tidak ikut TOUCH.
    public bool ShouldTouch(int stationId)
    {
        var now = DateTime.UtcNow;

        while (true)
        {
            if (!_lastTouch.TryGetValue(stationId, out var last))
            {
                if (_lastTouch.TryAdd(stationId, now)) return true;
                continue;
            }

            if (now - last < Interval) return false;
            if (_lastTouch.TryUpdate(stationId, now, last)) return true;
        }
    }
}

// Prompt 85: normalisasi identitas perangkat yang dikirim client (body claim atau header
// X-Station-Device-Id / X-Station-Device-Name). Kosong -> null (= client lama).
public static class StationDeviceIdentity
{
    public static string? CleanId(string? deviceId)
    {
        var value = deviceId?.Trim();
        if (string.IsNullOrEmpty(value)) return null;
        return value.Length > 64 ? value[..64] : value;
    }

    // "|" dibuang karena nama dikirim balik di pesan "DIPAKAI|nama|waktu".
    public static string? CleanName(string? deviceName)
    {
        var value = deviceName?.Replace("|", string.Empty).Trim();
        if (string.IsNullOrEmpty(value)) return null;
        return value.Length > 100 ? value[..100] : value;
    }

    // Header dikirim URI-escaped (header HTTP hanya ASCII).
    public static string? CleanHeaderName(string? escapedName)
    {
        if (string.IsNullOrWhiteSpace(escapedName)) return null;
        try
        {
            return CleanName(Uri.UnescapeDataString(escapedName));
        }
        catch (UriFormatException)
        {
            return CleanName(escapedName);
        }
    }
}

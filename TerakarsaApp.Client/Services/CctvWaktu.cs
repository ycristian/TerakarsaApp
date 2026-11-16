using System.Globalization;

namespace TerakarsaApp.Client.Services;

// Prompt 93-94: waktu module CCTV selalu WIB (UTC+7, tanpa DST) -- tidak bergantung zona
// waktu perangkat (owner bisa membuka dari luar pabrik).
public static class CctvWaktu
{
    public static readonly TimeSpan Wib = TimeSpan.FromHours(7);

    private static readonly string[] Bulan =
        { "Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des" };

    public static DateTimeOffset Now() => DateTimeOffset.UtcNow.ToOffset(Wib);

    public static DateTimeOffset ToWib(DateTimeOffset t) => t.ToOffset(Wib);

    // DateTime tanpa offset dianggap SUDAH WIB kalau Kind Unspecified, UTC kalau Kind Utc,
    // waktu lokal perangkat kalau Kind Local.
    public static DateTimeOffset FromDateTime(DateTime t) => t.Kind switch
    {
        DateTimeKind.Utc => new DateTimeOffset(t, TimeSpan.Zero).ToOffset(Wib),
        DateTimeKind.Local => new DateTimeOffset(t).ToOffset(Wib),
        _ => new DateTimeOffset(t, Wib)
    };

    public static DateTimeOffset Of(DateOnly d, TimeOnly t) => new(d.ToDateTime(t), Wib);

    public static DateTimeOffset DayStart(DateOnly d) => new(d.ToDateTime(TimeOnly.MinValue), Wib);

    public static string Iso(DateTimeOffset t) =>
        ToWib(t).ToString("yyyy-MM-dd'T'HH:mm:sszzz", CultureInfo.InvariantCulture);

    public static string Jam(DateTimeOffset t) => ToWib(t).ToString("HH:mm:ss", CultureInfo.InvariantCulture);

    public static string Tanggal(DateTimeOffset t)
    {
        var w = ToWib(t);
        return $"{w.Day} {Bulan[w.Month - 1]} {w.Year}";
    }

    public static string Tanggal(DateOnly d) => $"{d.Day} {Bulan[d.Month - 1]} {d.Year}";

    public static string TanggalPendek(DateTimeOffset t)
    {
        var w = ToWib(t);
        return $"{w.Day} {Bulan[w.Month - 1]}";
    }
}

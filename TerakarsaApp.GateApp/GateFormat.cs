using System.Globalization;

namespace TerakarsaApp.GateApp;

// Prompt 70: tanggal & durasi di layar gate selalu bahasa Indonesia. Culture sistem tablet tidak
// dipercaya (tablet Windows baru sering en-US), jadi id-ID dipakai eksplisit di satu tempat.
public static class GateFormat
{
    private static readonly CultureInfo Id = CultureInfo.GetCultureInfo("id-ID");

    // Kode hasil LOKAL (tidak pernah dari/ke server): bacaan reader kurang dari 10 digit.
    public const string BadReadCode = "BACA_ULANG";

    // "0851****451": 4 digit awal + 3 digit akhir, sisanya ditutup -- layar gate terlihat orang
    // yang antre, jadi nomor lengkap tidak pernah ditampilkan. Spasi/strip/titik dibuang dulu.
    // Nomor terlalu pendek (< 8 digit) hanya menampilkan 3 digit akhir. null = tidak ada nomor.
    public static string? MaskPhone(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return null;
        var p = new string(phone.Where(c => char.IsDigit(c) || c == '+').ToArray());
        if (p.Length == 0) return null;
        if (p.Length >= 8) return p[..4] + "****" + p[^3..];
        return p.Length > 3 ? "****" + p[^3..] : "****";
    }

    // "Kamis, 8 Oktober 2026"
    public static string LongDate(DateTime value) => value.ToString("dddd, d MMMM yyyy", Id);

    // "Rab 09:00" -- dipakai layar konfirmasi sesi panjang, yang harus membedakan hari.
    public static string ShortDayTime(DateTime value) =>
        $"{Id.DateTimeFormat.GetAbbreviatedDayName(value.DayOfWeek)} {value:HH:mm}";

    // "9j 13m" / "18 jam" (durasi >= 24 jam tetap ditulis jam, bukan hari -- satpam membacanya
    // sebagai "berapa lama kartu di luar", bukan sebagai kalender).
    public static string Duration(int? minutes)
    {
        if (minutes is null) return "-";
        var total = Math.Max(0, minutes.Value);
        var hours = total / 60;
        var mins = total % 60;
        return mins == 0 ? $"{hours} jam" : $"{hours}j {mins:00}m";
    }

    public static string Time(DateTime? value) => value?.ToString("HH:mm") ?? "-";

    // Badge resource memakai warna holder fisik (resources.color_hex). NULL = netral.
    public static string BadgeColor(string? colorHex) =>
        string.IsNullOrWhiteSpace(colorHex) ? "#39425A" : colorHex.Trim();
}

namespace TerakarsaApp.Client;

// Prompt 27: format tampilan nomor bundle -- "{huruf}-{bundle_no}" (mis. "B-27") kalau
// project ybs sudah punya bundle_letter, atau cuma nomor (mis. "27") utk project lama.
public static class BundleDisplay
{
    public static string Format(string? letter, int? bundleNo) =>
        string.IsNullOrEmpty(letter) ? $"{bundleNo}" : $"{letter}-{bundleNo}";

    // Prompt 32/35: prioritas tampilan penjahit bundle -- EmployeeName (master employees),
    // selalu digabung dengan resourceName (Line) kalau ada. Dipakai di semua tempat yang
    // menampilkan penjahit bundle (list, report, station, scan). Prompt 35: tier
    // resourcePersonName (teks bebas lama) DIHAPUS -- kolom itu sudah direname jadi
    // bundles.remarks (catatan bebas, bukan identitas lagi).
    //   1. EmployeeName terisi -> "{resourceName} - {EmployeeName}"
    //   2. Hanya resourceName  -> "{resourceName}"
    //   3. Kosong semua        -> "-"
    public static string FormatPenjahit(string? resourceName, string? employeeName)
    {
        if (!string.IsNullOrEmpty(resourceName) && !string.IsNullOrEmpty(employeeName))
            return $"{resourceName} - {employeeName}";
        if (!string.IsNullOrEmpty(resourceName))
            return resourceName;
        if (!string.IsNullOrEmpty(employeeName))
            return employeeName;
        return "-";
    }

    // Dropdown "Cari penjahit" di station: tampilkan kode di depan nama kalau ada
    // (mis. "SW-001 / ABUY"), supaya operator bisa cari/bedakan penjahit dari kodenya.
    public static string FormatEmployeeOption(string? employeeCode, string employeeName) =>
        string.IsNullOrEmpty(employeeCode) ? employeeName : $"{employeeCode} / {employeeName}";
}

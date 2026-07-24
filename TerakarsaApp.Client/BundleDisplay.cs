namespace TerakarsaApp.Client;

// Prompt 27: format tampilan nomor bundle -- "{huruf}-{bundle_no}" (mis. "B-27") kalau
// project ybs sudah punya bundle_letter, atau cuma nomor (mis. "27") utk project lama.
public static class BundleDisplay
{
    public static string Format(string? letter, int? bundleNo) =>
        string.IsNullOrEmpty(letter) ? $"{bundleNo}" : $"{letter}-{bundleNo}";
}

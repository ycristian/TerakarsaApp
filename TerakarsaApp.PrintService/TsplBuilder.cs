using System.Text;
using System.Text.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

// Label bundle 6 x 4 cm untuk TSC TTP-244 Pro. Perkiraan 8 dot/mm (203 dpi):
// area 60x40mm ~ 480x320 dot. Kolom kiri: QR + serial cadangan. Kolom kanan
// (mulai x=210): project_name, "No. <bundle_no>" (elemen terbesar), size/qty,
// article_name, style/color, tanggal cetak.
public static class TsplBuilder
{
    // Font bitmap bawaan TSPL: nama -> (lebar, tinggi) dot per karakter sebelum magnifikasi.
    private static readonly Dictionary<string, (int Width, int Height)> FontSizes = new()
    {
        ["1"] = (8, 12),
        ["2"] = (12, 20),
        ["3"] = (16, 24),
        ["4"] = (24, 32),
        ["5"] = (32, 48),
    };

    private const int RightColX = 210;
    private const int RightEdge = 460;

    public static BundleLabelPayload ParseBundleLabelPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<BundleLabelPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload BUNDLE_LABEL kosong atau tidak valid.");
    }

    public static string BuildBundleLabel(BundleLabelPayload data)
    {
        var sb = new StringBuilder();
        sb.Append("SIZE 60 mm, 40 mm\r\n");
        sb.Append("GAP 3 mm, 0\r\n");
        sb.Append("DIRECTION 1\r\n");
        sb.Append("CLS\r\n");

        // QR: cell 6 dot diasumsikan versi ~3 (29x29 modul) untuk qr_content sepanjang
        // PublicBaseUrl + "/b/" + serial -> ~174 dot (~21.75 mm), mendekati target 23 mm.
        // Margin kiri 8 dot (~1 mm) dan jarak ke kolom kanan 28 dot (~3.5 mm) -- dikurangi
        // 0.2 cm & 0.3 cm dari revisi awal atas permintaan.
        const int qrX = 8, qrY = 72, qrCell = 6, qrModulesEstimate = 29;
        var qrSize = qrCell * qrModulesEstimate;
        var qrCenterX = qrX + qrSize / 2;
        sb.Append($"QRCODE {qrX},{qrY},M,{qrCell},A,0,\"{Sanitize(data.QrContent)}\"\r\n");

        var serial = Sanitize(data.Serial);
        sb.Append(Text(CenterAlignX(qrCenterX, "1", 1, serial), qrY + qrSize + 16, "1", 1, 1, serial));

        // Kolom kanan (rata kiri semua)
        var projectName = Truncate(Sanitize(data.ProjectName).ToUpperInvariant(), 22);
        sb.Append(Text(RightColX, 8, "1", 1, 1, projectName));

        var bundleNoText = $"No. {data.BundleNo}";
        sb.Append(Text(RightColX, 26, "2", 2, 4, bundleNoText));

        sb.Append($"BAR {RightColX},114,{RightEdge - RightColX},3\r\n");

        var sizeName = Sanitize(data.SizeName);
        sb.Append(Text(RightColX, 128, "3", 1, 1, sizeName));
        // qty ditempel 5 mm (40 dot) setelah size_name, bukan rata kanan.
        var qtyText = $"{data.Qty} pcs";
        var qtyX = RightColX + CharWidth("3", 1) * sizeName.Length + 40;
        sb.Append(Text(qtyX, 132, "2", 1, 1, qtyText));

        sb.Append($"BAR {RightColX},162,{RightEdge - RightColX},3\r\n");

        // Batas 20 karakter dari spek meluap di font "2" (12 dot/char x 20 = 240 dot,
        // melebihi lebar kolom kanan 210 dot) -- batasi juga oleh lebar fisik supaya
        // teks tidak menabrak tepi label.
        var articleName = TruncateToFit(Sanitize(data.ArticleName), 20, "2", 1, RightEdge - RightColX);
        sb.Append(Text(RightColX, 174, "2", 1, 1, articleName));

        var styleColor = Truncate(Join(" - ", data.Style, data.Color), 24);
        sb.Append(Text(RightColX, 200, "1", 1, 1, styleColor));

        var printedAt = DateTime.Now.ToString("ddMM HH:mm");
        sb.Append(Text(RightColX, 220, "1", 1, 1, printedAt));

        // Resource target (line/penjahit) -- opsional, baris dilewati kalau payload
        // tidak punya keduanya.
        var lineInfo = Join(" / ", data.ResourceName, data.ResourcePersonName);
        if (lineInfo.Length > 0)
        {
            sb.Append(Text(RightColX, 236, "1", 1, 1, $"Line : {Truncate(lineInfo, 24)}"));
        }

        sb.Append("PRINT 1,1\r\n");
        return sb.ToString();
    }

    private static string Text(int x, int y, string font, int xMult, int yMult, string content) =>
        $"TEXT {x},{y},\"{font}\",0,{xMult},{yMult},\"{content}\"\r\n";

    private static int CenterAlignX(int centerX, string font, int xMult, string text) =>
        centerX - (CharWidth(font, xMult) * text.Length) / 2;

    private static int CharWidth(string font, int xMult) => FontSizes[font].Width * xMult;

    // TSPL/printer memakai encoding ASCII (lihat Worker.cs), jadi tanda potong dan
    // pemisah pakai karakter ASCII biasa supaya tidak berubah jadi "?" saat dicetak.
    private static string Truncate(string value, int maxLen)
    {
        if (value.Length <= maxLen) return value;
        return maxLen <= 3 ? value.Substring(0, maxLen) : value.Substring(0, maxLen - 3) + "...";
    }

    private static string TruncateToFit(string value, int maxLen, string font, int xMult, int availableWidthDot)
    {
        var widthCap = availableWidthDot / CharWidth(font, xMult);
        return Truncate(value, Math.Min(maxLen, widthCap));
    }

    private static string Join(string separator, params string?[] parts) =>
        string.Join(separator, parts.Where(p => !string.IsNullOrWhiteSpace(p)).Select(Sanitize));

    // TSPL tidak punya mekanisme escape untuk tanda kutip di dalam argumen string;
    // data (article_name/style/color, dst.) berasal dari input pengguna di aplikasi utama,
    // jadi diamankan di sini supaya tidak merusak perintah TSPL yang dikirim ke printer.
    private static string Sanitize(string? value) =>
        (value ?? string.Empty).Replace("\"", "'").Replace("\r", " ").Replace("\n", " ");
}

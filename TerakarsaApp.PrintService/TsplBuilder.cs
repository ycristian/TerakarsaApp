using System.Text;
using System.Text.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

// Label bundle 6 x 4 cm untuk TSC TTP-244 Pro. Stok fisik terpasang LANDSCAPE
// (60mm melintang kepala cetak x 40mm searah tarikan -> SIZE 60mm,40mm, kanvas
// 480x320 dot @ 8 dot/mm) -- tidak perlu rotasi. Kolom kiri: QR + serial cadangan.
// Kolom kanan (mulai x=210): project_name+no_po, "No. <bundle_no>" (elemen
// terbesar), size/qty, article_name+style/color, line+waktu mulai, bahan+size pack.
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

        // QR: cell 5 dot, versi ~3 (29x29 modul) untuk qr_content sepanjang PublicBaseUrl +
        // "/b/" + serial -> ~145 dot (~18 mm). Quiet zone wajib ISO/IEC 18004 >= 4 modul
        // (4*5=20 dot) polos di semua sisi -- sebelumnya cuma 8 dot kiri & 16 dot atas/bawah,
        // cukup untuk scanner Android (ZXing/ML Kit, toleran) tapi Camera iPhone (Apple
        // Vision, ketat soal quiet zone) gagal baca. Margin dinaikkan ke 24 dot (~3 mm) di
        // semua sisi supaya konsisten kebaca di kedua platform.
        const int qrX = 24, qrY = 118, qrCell = 5, qrModulesEstimate = 29, qrQuietGap = 24;
        var qrSize = qrCell * qrModulesEstimate;
        var qrCenterX = qrX + qrSize / 2;
        // Model wajib di-set eksplisit ke 2. Command TSPL QRCODE punya parameter opsional
        // "Model" (1 = versi asli 1994, 2 = enhanced/current) sebelum content -- kalau tidak
        // diisi, firmware TSC defaultnya Model 1. Semua generator QR modern (termasuk yang
        // dipakai preview di layar) selalu pakai Model 2, dan AVFoundation/Vision di iOS
        // TIDAK mendukung decode Model 1 sama sekali (beda struktur alignment pattern),
        // sementara ZXing/ML Kit di Android lebih permisif -- ini yang bikin qr_content
        // identik tetap kebaca dari layar & Android tapi gagal dari label cetak di iPhone.
        sb.Append($"QRCODE {qrX},{qrY},M,{qrCell},A,0,2,\"{Sanitize(data.QrContent)}\"\r\n");

        var serial = Sanitize(data.Serial);
        sb.Append(Text(CenterAlignX(qrCenterX, "1", 1, serial), qrY + qrSize + qrQuietGap, "1", 1, 1, serial));
    
        sb.Append(Text(qrX, 20, "3", 1, 1, data.ProjectName?.ToUpperInvariant() ?? string.Empty));
        sb.Append(Text(qrX, 50, "1", 1, 1, "#"+data.NoPo?.ToUpperInvariant() ?? string.Empty));
        sb.Append(Text(qrX, 70, "3", 1, 1, data.ArticleName?.ToUpperInvariant() ?? string.Empty));


        // // Kolom kanan (rata kiri semua)
        // var projectLine = Truncate(Join(" ", data.ProjectName?.ToUpperInvariant(), data.NoPo), 26);
        // sb.Append(Text(RightColX, 8, "3", 1, 1, projectLine));

        var bundleNoText = $"{data.BundleNo}";
        // sb.Append(Text(RightColX, 300, "3", 1, 1, "000010000100001000010000100001"));
        sb.Append(Text(RightAlignX(RightEdge, "3", 3, bundleNoText), 26, "3", 3, 3, bundleNoText));

        sb.Append($"BAR {RightColX},114,{RightEdge - RightColX},3\r\n");

        var sizeName = Sanitize(data.SizeName);
        sb.Append(Text(RightColX, 128, "3", 1, 1, sizeName));
        // size_name rata kiri, qty rata kanan (kolom kanan).
        var qtyText = $"{data.Qty} pcs";
        sb.Append(Text(RightAlignX(RightEdge, "2", 1, qtyText + "  "), 132, "2", 1, 1, qtyText));

        sb.Append($"BAR {RightColX},162,{RightEdge - RightColX},3\r\n");

        // article_name + style/color digabung 1 baris (bukan 2) supaya sisa baris info
        // di bawah bisa pakai font lebih besar & tidak numpuk (feedback: terlalu padat
        // untuk dibaca sekilas di lantai produksi).
        // var styleColor = Join(" - ", data.Style, data.Color);
        // var articleLine = styleColor.Length > 0 ? $"{data.ArticleName} ({styleColor})" : data.ArticleName;
        // articleLine = TruncateToFit(Sanitize(articleLine), 28, "2", 1, RightEdge - RightColX);
        sb.Append(Text(RightColX-100, 174, "2", 1, 1, data.MaterialName?.ToUpperInvariant() ?? string.Empty));
        sb.Append(Text(RightColX, 200, "2", 1, 1, data.ResourceName?.ToUpperInvariant() ?? string.Empty +" - " + data.ResourcePersonName?.ToUpperInvariant() ?? string.Empty));
        sb.Append(Text(RightColX, 226, "2", 1, 1, "> " + data.ResourcePersonName?.ToUpperInvariant() ?? string.Empty));
        sb.Append(Text(RightColX, 252, "1", 1, 1, data.SizePackName?.ToUpperInvariant() ?? string.Empty));
        
        var mulaiText = data.StartedAt.ToString("dd/MM HH:mm");
        sb.Append(Text(RightAlignX(RightEdge, "2", 1, mulaiText + "   "), 290, "2", 1, 1, mulaiText));

        // // Line (penjahit) + waktu mulai digabung 1 baris -- paling relevan operasional,
        // // jadi tetap dapat font "2".
        // var lineInfo = Join(" / ", data.ResourceName, data.ResourcePersonName);
        // var lineDimulai = Join(" - ", lineInfo, data.StartedAt.ToString("dd/MM HH:mm"));
        // lineDimulai = TruncateToFit(Sanitize(lineDimulai), 28, "2", 1, RightEdge - RightColX);
        // sb.Append(Text(RightColX, 200, "2", 1, 1, lineDimulai));

        // // Bahan + Size Pack -- info referensi, prioritas lebih rendah, cukup font "1".
        // var bahanSizePack = Join(" - ", data.MaterialName, data.SizePackName);
        // bahanSizePack = TruncateToFit(Sanitize(bahanSizePack), 40, "1", 1, RightEdge - RightColX);
        // sb.Append(Text(RightColX, 226, "1", 1, 1, bahanSizePack));

        sb.Append("PRINT 1,1\r\n");
        return sb.ToString();
    }

    private static string Text(int x, int y, string font, int xMult, int yMult, string content) =>
        $"TEXT {x},{y},\"{font}\",0,{xMult},{yMult},\"{content}\"\r\n";

    private static int CenterAlignX(int centerX, string font, int xMult, string text) =>
        centerX - (CharWidth(font, xMult) * text.Length) / 2;

    private static int RightAlignX(int rightEdge, string font, int xMult, string text) =>
        rightEdge - CharWidth(font, xMult) * text.Length;

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

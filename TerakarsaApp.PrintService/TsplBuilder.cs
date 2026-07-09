using System.Text;
using System.Text.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

// Label bundle 10 x 5 cm untuk TSC TTP-244 Pro. Perkiraan 8 dot/mm (203 dpi):
// area 100x50mm ~ 800x400 dot. QR di kiri (~35-40mm), teks di kanan.
public static class TsplBuilder
{
    public static BundleLabelPayload ParseBundleLabelPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<BundleLabelPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload BUNDLE_LABEL kosong atau tidak valid.");
    }

    public static string BuildBundleLabel(BundleLabelPayload data)
    {
        var sb = new StringBuilder();
        sb.Append("SIZE 100 mm, 50 mm\r\n");
        sb.Append("GAP 3 mm, 0\r\n");
        sb.Append("DIRECTION 1\r\n");
        sb.Append("CLS\r\n");
        sb.Append($"QRCODE 40,100,M,8,A,0,\"{Sanitize(data.QrContent)}\"\r\n");
        sb.Append($"TEXT 360,40,\"3\",0,3,3,\"No. {data.BundleNo}\"\r\n");
        sb.Append($"TEXT 360,150,\"2\",0,1,1,\"{Sanitize(data.Serial)}\"\r\n");
        sb.Append($"TEXT 360,190,\"2\",0,1,1,\"{Sanitize(data.ArticleName)}\"\r\n");
        sb.Append($"TEXT 360,230,\"2\",0,1,1,\"{Sanitize(JoinNonEmpty(data.Style, data.Color))}\"\r\n");
        sb.Append($"TEXT 360,270,\"2\",0,1,1,\"{Sanitize(data.SizeName)} - {data.Qty} pcs\"\r\n");
        sb.Append($"TEXT 360,330,\"1\",0,1,1,\"{Sanitize(data.ProjectName)}\"\r\n");
        sb.Append("PRINT 1,1\r\n");
        return sb.ToString();
    }

    // TSPL tidak punya mekanisme escape untuk tanda kutip di dalam argumen string;
    // data (article_name/style/color, dst.) berasal dari input pengguna di aplikasi utama,
    // jadi diamankan di sini supaya tidak merusak perintah TSPL yang dikirim ke printer.
    private static string Sanitize(string? value) =>
        (value ?? string.Empty).Replace("\"", "'").Replace("\r", " ").Replace("\n", " ");

    private static string JoinNonEmpty(params string?[] parts) =>
        string.Join(" ", parts.Where(p => !string.IsNullOrWhiteSpace(p)));
}

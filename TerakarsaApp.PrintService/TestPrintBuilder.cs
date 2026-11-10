using System.Text;
using System.Text.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

// Prompt 88: isi job TEST_PRINT (tombol "Test print" di /admin/printer). Sengaja TERPISAH
// dari TsplBuilder (label produksi tidak diubah) -- cukup teks pendek untuk memastikan
// printer menerima data.
//   RAW_TSPL -> label kecil berisi teks (ukuran kanvas sama dengan label bundle 60x40 mm).
//   TOKEN    -> beberapa baris token, diterjemahkan EscPosRenderer seperti struk biasa.
public static class TestPrintBuilder
{
    public static TestPrintPayload ParsePayload(string json) =>
        JsonSerializer.Deserialize<TestPrintPayload>(json)
        ?? throw new InvalidOperationException("Payload TEST_PRINT kosong.");

    public static byte[] BuildTspl(TestPrintPayload data)
    {
        var sb = new StringBuilder();
        sb.Append("SIZE 60 mm, 40 mm\r\n");
        sb.Append("GAP 3 mm, 0\r\n");
        sb.Append("DIRECTION 1\r\n");
        sb.Append("CLS\r\n");
        sb.Append(Text(24, 24, "4", "TEST PRINT"));
        sb.Append(Text(24, 96, "3", Trunc(data.DeviceName, 28)));
        sb.Append(Text(24, 136, "3", Trunc(data.DeviceCode, 28)));
        sb.Append(Text(24, 176, "3", data.RequestedAt.ToString("dd-MM-yyyy HH:mm:ss")));
        sb.Append(Text(24, 240, "2", "TMOS - printer OK"));
        sb.Append("PRINT 1,1\r\n");
        return Encoding.ASCII.GetBytes(sb.ToString());
    }

    public static string BuildTokenText(TestPrintPayload data)
    {
        var lines = new[]
        {
            "{C}{S2}{B}TEST PRINT",
            "{C}" + Escape(data.DeviceName),
            "{C}" + Escape(data.DeviceCode),
            "{C}" + data.RequestedAt.ToString("dd-MM-yyyy HH:mm:ss"),
            "{HR}",
            "{C}TMOS - printer OK",
            "{CUT}"
        };
        return string.Join("\n", lines);
    }

    private static string Text(int x, int y, string font, string content) =>
        $"TEXT {x},{y},\"{font}\",0,1,1,\"{content.Replace("\"", "'")}\"\r\n";

    private static string Trunc(string? s, int len)
    {
        s ??= string.Empty;
        return s.Length <= len ? s : s[..(len - 3)] + "...";
    }

    private static string Escape(string? s) =>
        (s ?? string.Empty).Replace("{", "{{").Replace("\r", " ").Replace("\n", " ");
}

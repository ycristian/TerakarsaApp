using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using QRCoder;

namespace TerakarsaApp.PrintService;

// Prompt 48: menerjemahkan teks ber-token hasil SIS_Print_Dispatch (lihat kamus token di
// claude prompt/prompt_48_thermal_token_render.md bagian 2) menjadi byte ESC/POS. Lebar
// kertas/font diambil dari data job (CharsPerLine/CharsPerLineSmall hasil klaim), bukan
// konstanta. Token tidak dikenal diabaikan (baris sisanya tetap dicetak) dan dicatat sebagai
// warning -- satu token asing tidak boleh menggagalkan seluruh cetakan.
public static class EscPosRenderer
{
    private const byte ESC = 0x1B;
    private const byte GS = 0x1D;

    public sealed class RenderResult
    {
        public byte[] Bytes { get; init; } = Array.Empty<byte>();
        public string PlainText { get; init; } = string.Empty;
        public List<string> Warnings { get; init; } = new();
    }

    private abstract class Unit;

    private sealed class TextUnit : Unit
    {
        public string Text = string.Empty;   // dikirim apa adanya ke printer -- alignment diserahkan ke ESC a
        public string DisplayText = string.Empty; // sudah dipad manual utk pratinjau .txt
        public bool Bold;
        public bool Underline;
        public byte Size;
        public bool FontB;
        public char Align = 'L';
    }

    private sealed class FeedUnit : Unit { public int Lines; }
    private sealed class CutUnit : Unit;
    private sealed class DrawerUnit : Unit;
    private sealed class QrUnit : Unit { public string Content = string.Empty; }
    private sealed class BarcodeUnit : Unit { public string Content = string.Empty; }

    private sealed class FormatState
    {
        public bool Bold;
        public bool Underline;
        public byte Size;
        public bool FontB;
        public char Align = 'L';
    }

    private static readonly (string Token, Action<FormatState> Apply)[] FormatPrefixes =
    {
        ("{S1}", f => f.Size = 0x00),
        ("{S2}", f => f.Size = 0x11),
        ("{S3}", f => f.Size = 0x22),
        ("{SH2}", f => f.Size = 0x10),
        ("{SW2}", f => f.Size = 0x01),
        ("{B}", f => f.Bold = true),
        ("{U}", f => f.Underline = true),
        ("{FA}", f => f.FontB = false),
        ("{FB}", f => f.FontB = true),
        ("{L}", f => f.Align = 'L'),
        ("{C}", f => f.Align = 'C'),
        ("{R}", f => f.Align = 'R'),
    };

    private static readonly Regex FeedRegex = new(@"^\{FEED:(\d+)\}$", RegexOptions.Compiled);
    private static readonly Regex QrRegex = new(@"^\{QR:(.*)\}$", RegexOptions.Compiled | RegexOptions.Singleline);
    private static readonly Regex BcRegex = new(@"^\{BC:(.*)\}$", RegexOptions.Compiled | RegexOptions.Singleline);
    private static readonly Regex RowRegex = new(@"^\{ROW:([0-9,]+)\}(.*)$", RegexOptions.Compiled | RegexOptions.Singleline);

    public static RenderResult Render(string tokenText, int charsPerLine, int charsPerLineSmall)
    {
        var width = charsPerLine > 0 ? charsPerLine : 48;
        var widthSmall = charsPerLineSmall > 0 ? charsPerLineSmall : 64;
        var warnings = new List<string>();
        var units = new List<Unit>();

        var normalized = (tokenText ?? string.Empty).Replace("\r\n", "\n").Replace("\r", "\n");
        foreach (var raw in normalized.Split('\n'))
        {
            units.AddRange(ParseLine(raw, width, widthSmall, warnings));
        }

        // Akhir dokumen: kalau SP tidak menulis {CUT}, worker otomatis menambahkan {FEED:4}{CUT}.
        if (!units.Any(u => u is CutUnit))
        {
            units.Add(new FeedUnit { Lines = 4 });
            units.Add(new CutUnit());
        }

        return new RenderResult
        {
            Bytes = EmitBytes(units),
            PlainText = EmitPlainText(units),
            Warnings = warnings,
        };
    }

    private static List<Unit> ParseLine(string raw, int width, int widthSmall, List<string> warnings)
    {
        var units = new List<Unit>();
        var pos = 0;
        var fmt = new FormatState();

        while (pos < raw.Length && raw[pos] == '{')
        {
            var matched = false;
            foreach (var (token, apply) in FormatPrefixes)
            {
                if (string.CompareOrdinal(raw, pos, token, 0, token.Length) == 0)
                {
                    apply(fmt);
                    pos += token.Length;
                    matched = true;
                    break;
                }
            }
            if (!matched) break;
        }

        var w = fmt.FontB ? widthSmall : width;
        var remainder = raw.Substring(pos);

        while (true)
        {
            if (remainder.StartsWith("{{", StringComparison.Ordinal)) break; // "{" literal -> teks biasa
            if (!remainder.StartsWith("{", StringComparison.Ordinal)) break; // teks biasa

            if (remainder == "{HR}")
            {
                units.Add(MakeRawUnit(new string('-', w), fmt));
                return units;
            }
            if (remainder == "{HR=}")
            {
                units.Add(MakeRawUnit(new string('=', w), fmt));
                return units;
            }
            if (remainder == "{CUT}")
            {
                units.Add(new CutUnit());
                return units;
            }
            if (remainder == "{DRAWER}")
            {
                units.Add(new DrawerUnit());
                return units;
            }

            var feedMatch = FeedRegex.Match(remainder);
            if (feedMatch.Success)
            {
                units.Add(new FeedUnit { Lines = Math.Clamp(int.Parse(feedMatch.Groups[1].Value, CultureInfo.InvariantCulture), 0, 255) });
                return units;
            }

            var qrMatch = QrRegex.Match(remainder);
            if (qrMatch.Success)
            {
                units.Add(new QrUnit { Content = UnescapeBraces(qrMatch.Groups[1].Value) });
                return units;
            }

            var bcMatch = BcRegex.Match(remainder);
            if (bcMatch.Success)
            {
                units.Add(new BarcodeUnit { Content = UnescapeBraces(bcMatch.Groups[1].Value) });
                return units;
            }

            if (remainder.StartsWith("{2COL}", StringComparison.Ordinal))
            {
                var content = remainder.Substring("{2COL}".Length);
                var idx = content.IndexOf('|');
                var left = UnescapeBraces(idx >= 0 ? content.Substring(0, idx) : content);
                var right = UnescapeBraces(idx >= 0 ? content.Substring(idx + 1) : string.Empty);
                units.Add(MakeRawUnit(BuildTwoCol(SanitizeAscii(left), SanitizeAscii(right), w), fmt));
                return units;
            }

            var rowMatch = RowRegex.Match(remainder);
            if (rowMatch.Success)
            {
                var widths = rowMatch.Groups[1].Value.Split(',').Select(s => int.Parse(s, CultureInfo.InvariantCulture)).ToList();
                var content = SanitizeAscii(UnescapeBraces(rowMatch.Groups[2].Value));
                units.Add(MakeRawUnit(BuildRow(content, widths), fmt));
                return units;
            }

            // Token tidak dikenal -- abaikan token itu, cetak sisanya, catat warning.
            var closeIdx = remainder.IndexOf('}');
            if (closeIdx < 0) break; // tidak ditutup -- perlakukan sisanya sebagai teks biasa
            var unknown = remainder.Substring(0, closeIdx + 1);
            warnings.Add($"Token tidak dikenal: {unknown}");
            remainder = remainder.Substring(closeIdx + 1);
        }

        var text = SanitizeAscii(UnescapeBraces(remainder));
        foreach (var line in WrapText(text, w))
        {
            units.Add(MakeWrappedUnit(line, fmt, w));
        }
        return units;
    }

    private static string UnescapeBraces(string s) => s.Replace("{{", "{");

    private static TextUnit MakeRawUnit(string text, FormatState fmt) => new()
    {
        Text = text,
        DisplayText = text,
        Bold = fmt.Bold,
        Underline = fmt.Underline,
        Size = fmt.Size,
        FontB = fmt.FontB,
        Align = fmt.Align,
    };

    private static TextUnit MakeWrappedUnit(string text, FormatState fmt, int width) => new()
    {
        Text = text,
        DisplayText = PadForDisplay(text, width, fmt.Align),
        Bold = fmt.Bold,
        Underline = fmt.Underline,
        Size = fmt.Size,
        FontB = fmt.FontB,
        Align = fmt.Align,
    };

    private static string PadForDisplay(string text, int width, char align)
    {
        if (text.Length >= width) return text;
        var space = width - text.Length;
        return align switch
        {
            'C' => new string(' ', space / 2) + text + new string(' ', space - space / 2),
            'R' => new string(' ', space) + text,
            _ => text,
        };
    }

    // Word-wrap otomatis, patah di spasi terdekat (pola sama dengan EscPosBuilder.WrapLines
    // lama) -- baris lanjutan mewarisi format baris induk (dipanggil dgn fmt yang sama).
    private static IEnumerable<string> WrapText(string text, int width)
    {
        if (width <= 0) width = 1;
        if (text.Length == 0)
        {
            yield return string.Empty;
            yield break;
        }

        var remaining = text;
        while (remaining.Length > width)
        {
            var breakAt = remaining.LastIndexOf(' ', Math.Min(width, remaining.Length - 1));
            if (breakAt <= 0) breakAt = width;
            yield return remaining.Substring(0, breakAt).TrimEnd();
            remaining = remaining.Substring(breakAt).TrimStart();
        }
        if (remaining.Length > 0) yield return remaining;
    }

    // {2COL}kiri|kanan -- kiri rata kiri, kanan rata kanan, spasi di tengah. Isi yang melebihi
    // lebar dipotong dengan "..." (bukan di-wrap).
    private static string BuildTwoCol(string left, string right, int width)
    {
        if (right.Length >= width) return Trunc(right, width);

        var available = width - right.Length;
        if (left.Length > available - 1)
            left = Trunc(left, Math.Max(0, available - 1));

        var pad = width - left.Length - right.Length;
        if (pad < 1) pad = 1;
        return left + new string(' ', pad) + right;
    }

    // {ROW:w1,w2,...}a|b|c -- kolom lebar tetap, kolom terakhir rata kanan, sisanya rata kiri.
    // Isi yang melebihi lebar kolomnya dipotong dengan "...".
    private static string BuildRow(string content, List<int> widths)
    {
        var cells = content.Split('|', widths.Count);
        var sb = new StringBuilder();
        for (var i = 0; i < widths.Count; i++)
        {
            var colWidth = Math.Max(0, widths[i]);
            var cell = Trunc(i < cells.Length ? cells[i] : string.Empty, colWidth);
            var pad = Math.Max(0, colWidth - cell.Length);
            if (i == widths.Count - 1)
                sb.Append(' ', pad).Append(cell);
            else
                sb.Append(cell).Append(' ', pad);
        }
        return sb.ToString();
    }

    // Potongan ASCII "..." (sama pola dengan TsplBuilder.Truncate/EscPosBuilder lama --
    // ESC/POS di sini dikirim ASCII, bukan unicode ellipsis).
    private static string Trunc(string value, int maxLen)
    {
        if (maxLen <= 0) return string.Empty;
        if (value.Length <= maxLen) return value;
        return maxLen <= 3 ? value.Substring(0, maxLen) : value.Substring(0, maxLen - 3) + "...";
    }

    // Karakter non-ASCII dipetakan ke padanan ASCII terdekat: tanda baca tipografis umum
    // (kutip lengkung, en/em dash, ellipsis) dipetakan manual, huruf berdiakritik dilipat ke
    // huruf dasarnya lewat normalisasi NFD (é -> e), sisanya yang masih di luar ASCII cetak
    // jadi '?'. Printer tetap diberi ESC t 0 (codepage CP437) sesuai kamus token, tapi teks
    // yang dikirim sudah ASCII murni -- codepage-nya sendiri jadi tidak kritis.
    private static string SanitizeAscii(string? value)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;

        // Ganti pakai kode karakter (bukan literal glyph) supaya file source ini tetap ASCII murni.
        var s = value
            .Replace((char)0x2018, '\'').Replace((char)0x2019, '\'') // kutip satu miring kiri/kanan
            .Replace((char)0x201C, '"').Replace((char)0x201D, '"')   // kutip dua miring kiri/kanan
            .Replace((char)0x2013, '-').Replace((char)0x2014, '-')   // en dash / em dash
            .Replace(((char)0x2026).ToString(), "...");             // unicode ellipsis

        s = s.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(s.Length);
        foreach (var ch in s)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            sb.Append(ch is >= (char)0x20 and <= (char)0x7E ? ch : '?');
        }
        return sb.ToString();
    }

    private static byte[] EmitBytes(List<Unit> units)
    {
        using var ms = new MemoryStream();
        void W(params byte[] b) => ms.Write(b, 0, b.Length);
        void WriteAscii(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            ms.Write(bytes, 0, bytes.Length);
        }
        void ResetFormat()
        {
            W(ESC, 0x45, 0x00); // ESC E 0 : bold off
            W(ESC, 0x2D, 0x00); // ESC - 0 : underline off
            W(GS, 0x21, 0x00);  // GS ! 0 : ukuran normal
            W(ESC, 0x4D, 0x00); // ESC M 0 : font A
            W(ESC, 0x61, 0x00); // ESC a 0 : rata kiri
        }

        W(ESC, 0x40);       // ESC @ : initialize
        W(ESC, 0x74, 0x00); // ESC t 0 : codepage CP437 (lihat kamus token)
        W(ESC, 0x61, 0x00); // ESC a 0 : rata kiri default

        foreach (var unit in units)
        {
            switch (unit)
            {
                case TextUnit t:
                    W(ESC, 0x61, t.Align switch { 'C' => (byte)1, 'R' => (byte)2, _ => (byte)0 }); // ESC a n
                    W(ESC, 0x4D, (byte)(t.FontB ? 1 : 0)); // ESC M n : font A/B
                    W(GS, 0x21, t.Size);                    // GS ! n : ukuran
                    if (t.Bold) W(ESC, 0x45, 0x01);         // ESC E 1 : bold
                    if (t.Underline) W(ESC, 0x2D, 0x01);    // ESC - 1 : underline
                    WriteAscii(t.Text);
                    WriteAscii("\n");
                    ResetFormat();
                    break;

                case FeedUnit f:
                    W(ESC, 0x64, (byte)f.Lines); // ESC d n : feed n baris
                    break;

                case CutUnit:
                    W(GS, 0x56, 0x01); // GS V 1 : partial cut (diabaikan printer tanpa cutter)
                    break;

                case DrawerUnit:
                    W(ESC, 0x70, 0x00, 0x19, 0xFA); // ESC p 0 25 250 : pulsa buka laci kasir
                    break;

                case QrUnit q:
                    EmitQr(ms, q.Content);
                    break;

                case BarcodeUnit b:
                    EmitBarcode(ms, b.Content);
                    break;
            }
        }

        return ms.ToArray();
    }

    // QR digenerate sendiri lewat QRCoder (sama pola dengan TsplBuilder -- printer thermal
    // tidak diberi kesempatan salah render QR lewat command native) lalu dicetak sebagai
    // raster bit image (GS v 0), bukan command QR native ESC/POS.
    private static void EmitQr(MemoryStream ms, string content)
    {
        void W(params byte[] b) => ms.Write(b, 0, b.Length);

        var sanitized = SanitizeAscii(content);
        if (sanitized.Length == 0) return;

        const int quietModules = 2;
        const int cellDots = 4;
        var qrGenerator = new QRCodeGenerator();
        var qrData = qrGenerator.CreateQrCode(sanitized, QRCodeGenerator.ECCLevel.M);
        var modules = ToModuleArray(qrData.ModuleMatrix, quietModules);
        var bitmap = BuildRasterBitmap(modules, cellDots, out var widthBytes, out var heightDots);

        W(ESC, 0x61, 0x01); // ESC a 1 : rata tengah
        W(GS, 0x76, 0x30, 0x00, (byte)(widthBytes & 0xFF), (byte)((widthBytes >> 8) & 0xFF), (byte)(heightDots & 0xFF), (byte)((heightDots >> 8) & 0xFF)); // GS v 0 : raster bit image
        ms.Write(bitmap, 0, bitmap.Length);
        W(ESC, 0x64, 0x01); // ESC d 1 : feed 1 baris
        W(ESC, 0x61, 0x00); // ESC a 0 : kembali rata kiri
    }

    // Code128 Set B (ASCII 32-126) lewat command barcode native ESC/POS GS k (m=73), dengan
    // teks (HRI) dicetak di bawah barcode.
    private static void EmitBarcode(MemoryStream ms, string content)
    {
        void W(params byte[] b) => ms.Write(b, 0, b.Length);

        var data = SanitizeAscii(content);
        if (data.Length == 0) return;

        var payload = "{B" + data;
        if (payload.Length > 255) payload = payload.Substring(0, 255);
        var payloadBytes = Encoding.ASCII.GetBytes(payload);

        W(ESC, 0x61, 0x01);       // ESC a 1 : rata tengah
        W(GS, 0x48, 0x02);        // GS H 2 : teks HRI di bawah barcode
        W(GS, 0x68, 0x50);        // GS h 80 : tinggi barcode 80 dot
        W(GS, 0x77, 0x02);        // GS w 2 : lebar modul
        W(GS, 0x6B, 0x49, (byte)payloadBytes.Length); // GS k 73 n : CODE128
        ms.Write(payloadBytes, 0, payloadBytes.Length);
        W(ESC, 0x64, 0x01);       // ESC d 1 : feed 1 baris
        W(ESC, 0x61, 0x00);       // ESC a 0 : kembali rata kiri
    }

    // QRCoder selalu menyertakan quiet zone 4 modul; trimModules memangkas ke ukuran yang
    // diinginkan (pola sama dengan TsplBuilder.ToModuleArray).
    private static bool[,] ToModuleArray(List<System.Collections.BitArray> rawMatrix, int quietModules)
    {
        const int qrCoderQuietModules = 4;
        var trim = qrCoderQuietModules - quietModules;
        var size = rawMatrix.Count - trim * 2;
        var modules = new bool[size, size];
        for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
                modules[y, x] = rawMatrix[y + trim][x + trim];
        return modules;
    }

    // Raster bit image GS v 0: data biner mentah, 1 bit = 1 dot, MSB dulu, tiap baris
    // dibulatkan ke kelipatan byte (widthBytes). Bit 1 = dot dicetak (hitam) -- pola bit-
    // packing sama dengan TsplBuilder.BuildQrBitmap.
    private static byte[] BuildRasterBitmap(bool[,] modules, int cellDots, out int widthBytes, out int heightDots)
    {
        var moduleCount = modules.GetLength(0);
        var widthDots = moduleCount * cellDots;
        heightDots = moduleCount * cellDots;
        widthBytes = (widthDots + 7) / 8;
        var bytes = new byte[widthBytes * heightDots];

        for (var my = 0; my < moduleCount; my++)
        {
            for (var mx = 0; mx < moduleCount; mx++)
            {
                if (!modules[my, mx]) continue;
                for (var dy = 0; dy < cellDots; dy++)
                {
                    var py = my * cellDots + dy;
                    var rowOffset = py * widthBytes;
                    for (var dx = 0; dx < cellDots; dx++)
                    {
                        var px = mx * cellDots + dx;
                        var byteIndex = rowOffset + px / 8;
                        var bitIndex = 7 - px % 8;
                        bytes[byteIndex] |= (byte)(1 << bitIndex);
                    }
                }
            }
        }

        return bytes;
    }

    private static string EmitPlainText(List<Unit> units)
    {
        var lines = new List<string>();
        foreach (var unit in units)
        {
            switch (unit)
            {
                case TextUnit t:
                    lines.Add(t.DisplayText);
                    break;
                case FeedUnit f:
                    for (var i = 0; i < f.Lines; i++) lines.Add(string.Empty);
                    break;
                case CutUnit:
                    lines.Add("----- CUT -----");
                    break;
                case DrawerUnit:
                    lines.Add("[DRAWER]");
                    break;
                case QrUnit q:
                    lines.Add($"[QR: {q.Content}]");
                    break;
                case BarcodeUnit b:
                    lines.Add($"[BARCODE: {b.Content}]");
                    break;
            }
        }
        return string.Join('\n', lines);
    }
}

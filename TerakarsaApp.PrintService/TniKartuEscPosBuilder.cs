using System.Globalization;
using System.Text;
using QRCoder;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

// Prompt 65: kartu personel PDH TNI AD (job_type TNI_KARTU), printer thermal 80mm
// Font A 48 kolom. Susunan mengikuti claude prompt/tni/mockup_kartu_80mm.html.
//
// Dirakit di C# dari payload (TniKartuPayload), BUKAN lewat token SP seperti
// job_type kupon -- karena itu Worker menangkap TNI_KARTU berdasarkan job_type
// sebelum switch RenderMode.
//
// QR: digenerate sendiri lewat QRCoder lalu dicetak sebagai RASTER BIT IMAGE
// (GS v 0), MENGIKUTI EscPosRenderer.EmitQr yang sudah terbukti di printer ini --
// BUKAN command QR native (GS ( k). Prompt 65 menyebut QR native, tapi codebase
// ini memang sudah sengaja pindah dari QR native ke raster karena printer
// thermal-nya salah render QR native (lihat komentar di EscPosRenderer.EmitQr).
// Kartu ini WAJIB bisa discan -- seluruh alur packing bergantung padanya -- jadi
// jalur yang sudah terbukti yang dipakai.
public static class TniKartuEscPosBuilder
{
    private const byte ESC = 0x1B;
    private const byte GS = 0x1D;
    private const int Width = 48;   // Font A, 80mm

    public static TniKartuPayload ParsePayload(string payloadJson)
    {
        var payload = System.Text.Json.JsonSerializer.Deserialize<TniKartuPayload>(
            payloadJson,
            new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        return payload ?? throw new InvalidOperationException("Payload TNI_KARTU kosong.");
    }

    public static byte[] Build(TniKartuPayload p)
    {
        using var ms = new MemoryStream();
        void W(params byte[] b) => ms.Write(b, 0, b.Length);
        void Text(string s) => W(Encoding.ASCII.GetBytes(Ascii(s)));
        void Line(string s = "") { Text(s); W(0x0A); }

        void Center() => W(ESC, 0x61, 0x01);
        void Left() => W(ESC, 0x61, 0x00);
        void Bold(bool on) => W(ESC, 0x45, (byte)(on ? 1 : 0));
        // GS ! n : bit4 = lebar ganda, bit0 = tinggi ganda
        void Big(bool on) => W(GS, 0x21, (byte)(on ? 0x11 : 0x00));

        W(ESC, 0x40);   // ESC @ : initialize
        Left();

        // ---------- 1. kepala ----------
        Center();
        Line(Cut(p.JudulOrder, Width));

        Big(true); Bold(true);
        // lebar ganda -> hanya 24 kolom efektif
        Line(Cut(p.KodeRef, Width / 2));
        Bold(false); Big(false);

        Line(Cut(Join(" - ", p.SatuanName, p.AreaName), Width));
        Left();

        // ---------- 2. identitas ----------
        Line(new string('=', Width));

        foreach (var l in LabelValue("Pangkat", p.Pangkat)) Line(l);
        foreach (var l in LabelValue("Nama", p.Nama)) Line(l);
        foreach (var l in LabelValue("NRP", p.Nrp)) Line(l);
        foreach (var l in LabelValue("No HP", p.NoHp)) Line(l);
        foreach (var l in LabelValue("TB / BB", TbBb(p))) Line(l);

        // ---------- 3. pola: info utama buat staff mengambil barang ----------
        Line(new string('=', Width));

        var half = Width / 2;
        Center();
        Left();
        Line(Pad("KEMEJA", half) + Pad("CELANA", half));

        Big(true); Bold(true);
        // lebar ganda -> 24 kolom efektif, jadi tiap kolom 12
        Line(Pad(Cut(p.PolaKemeja, half / 2 - 1), half / 2) +
             Pad(Cut(p.PolaCelana, half / 2 - 1), half / 2));
        Bold(false); Big(false);

        // ---------- 4. ukuran badan ----------
        Line(new string('-', Width));

        if (p.TidakHadirUkur)
        {
            Center();
            Bold(true);
            Line("TIDAK HADIR PENGUKURAN");
            Bold(false);
            Line("Memakai pola standar sesuai size di atas");
            Left();
        }
        else
        {
            Bold(true);
            Line("UKURAN BADAN - KEMEJA");
            Bold(false);
            foreach (var u in p.UkuranKemeja) Line(LabelRight(u.Label, Num(u.Nilai)));

            Line();
            Bold(true);
            Line("UKURAN BADAN - CELANA");
            Bold(false);
            foreach (var u in p.UkuranCelana) Line(LabelRight(u.Label, Num(u.Nilai)));
        }

        // ---------- 5. QR ----------
        Line(new string('=', Width));
        EmitQr(ms, p.QrContent);

        Center();
        Line(Cut(StripScheme(p.QrContent), Width));
        Line("Scan QR untuk cek status & komplain ukuran");
        Left();

        // ---------- 6. feed + potong ----------
        W(ESC, 0x64, 0x04);   // ESC d 4 : feed 4 baris
        W(GS, 0x56, 66, 0x00); // GS V 66 0 : partial cut

        return ms.ToArray();
    }

    // Pratinjau teks untuk DryRun -- baris demi baris, supaya layout bisa diperiksa
    // tanpa printer fisik.
    public static string BuildPlainText(TniKartuPayload p)
    {
        var sb = new StringBuilder();
        void L(string s = "") => sb.AppendLine(s);

        L(CenterText(Cut(p.JudulOrder, Width), Width));
        L(CenterText(Cut(p.KodeRef, Width / 2), Width) + "   [lebar+tinggi ganda, tebal]");
        L(CenterText(Cut(Join(" - ", p.SatuanName, p.AreaName), Width), Width));
        L(new string('=', Width));

        foreach (var l in LabelValue("Pangkat", p.Pangkat)) L(l);
        foreach (var l in LabelValue("Nama", p.Nama)) L(l);
        foreach (var l in LabelValue("NRP", p.Nrp)) L(l);
        foreach (var l in LabelValue("No HP", p.NoHp)) L(l);
        foreach (var l in LabelValue("TB / BB", TbBb(p))) L(l);

        L(new string('=', Width));
        var half = Width / 2;
        L(Pad("KEMEJA", half) + Pad("CELANA", half));
        L(Pad(Cut(p.PolaKemeja, half / 2 - 1), half / 2) +
          Pad(Cut(p.PolaCelana, half / 2 - 1), half / 2) + "   [lebar+tinggi ganda, tebal]");

        L(new string('-', Width));

        if (p.TidakHadirUkur)
        {
            L(CenterText("TIDAK HADIR PENGUKURAN", Width));
            L(CenterText("Memakai pola standar sesuai size di atas", Width));
        }
        else
        {
            L("UKURAN BADAN - KEMEJA");
            foreach (var u in p.UkuranKemeja) L(LabelRight(u.Label, Num(u.Nilai)));
            L();
            L("UKURAN BADAN - CELANA");
            foreach (var u in p.UkuranCelana) L(LabelRight(u.Label, Num(u.Nilai)));
        }

        L(new string('=', Width));
        L(CenterText($"[QR: {p.QrContent}]", Width));
        L(CenterText(Cut(StripScheme(p.QrContent), Width), Width));
        L(CenterText("Scan QR untuk cek status & komplain ukuran", Width));
        L();
        L("----- CUT -----");

        return sb.ToString();
    }

    // ---------------- format ----------------

    // 'Pangkat : Sertu'. Nama panjang dibungkus ke baris berikutnya dengan
    // indentasi 10 (selebar 'Nama    : ').
    private static IEnumerable<string> LabelValue(string label, string? value)
    {
        const int labelWidth = 8;   // 'Pangkat ' / 'TB / BB '
        var prefix = Pad(label, labelWidth) + ": ";
        var indent = new string(' ', prefix.Length);
        var text = Ascii(value ?? "-");
        if (text.Length == 0) text = "-";

        var first = true;
        foreach (var chunk in Wrap(text, Width - prefix.Length))
        {
            yield return (first ? prefix : indent) + chunk;
            first = false;
        }
    }

    // 'Lingkar Dada                                  96' -- angka rata kanan kolom 48.
    private static string LabelRight(string label, string value)
    {
        var l = Ascii(label);
        var v = Ascii(value);
        if (l.Length + v.Length + 1 > Width) l = Cut(l, Width - v.Length - 1);
        return l + new string(' ', Math.Max(1, Width - l.Length - v.Length)) + v;
    }

    // Angka tanpa '.0' -- 38.5 tetap 38.5, 42.0 jadi 42, NULL jadi '-'.
    private static string Num(decimal? v) =>
        v is null ? "-" : v.Value.ToString("0.#", CultureInfo.InvariantCulture);

    private static string TbBb(TniKartuPayload p)
    {
        var tb = p.TinggiBadan.HasValue ? $"{p.TinggiBadan} cm" : "-";
        var bb = p.BeratBadan.HasValue ? $"{p.BeratBadan} kg" : "-";
        return $"{tb} / {bb}";
    }

    private static string StripScheme(string? url) =>
        (url ?? string.Empty).Replace("https://", string.Empty).Replace("http://", string.Empty);

    private static string Join(string sep, params string?[] parts) =>
        string.Join(sep, parts.Where(x => !string.IsNullOrWhiteSpace(x)));

    private static string Pad(string? s, int width)
    {
        var t = Cut(s, width);
        return t + new string(' ', Math.Max(0, width - t.Length));
    }

    private static string Cut(string? s, int width)
    {
        var t = Ascii(s);
        return t.Length <= width ? t : t.Substring(0, width);
    }

    private static string CenterText(string s, int width)
    {
        if (s.Length >= width) return s;
        return new string(' ', (width - s.Length) / 2) + s;
    }

    private static IEnumerable<string> Wrap(string text, int width)
    {
        if (width < 1) width = 1;
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

    // Teks ASCII murni: karakter di luar ASCII diganti padanan terdekat
    // ('.' tengah -> '-'), sisanya '?'. Pola sama dengan EscPosRenderer.SanitizeAscii.
    private static string Ascii(string? value)
    {
        if (string.IsNullOrEmpty(value)) return string.Empty;

        // Pakai kode karakter (bukan literal glyph) supaya file source ini tetap ASCII murni.
        var s = value
            .Replace((char)0x00B7, '-')                              // middle dot
            .Replace((char)0x2022, '-')                              // bullet
            .Replace((char)0x2018, '\'').Replace((char)0x2019, '\'')
            .Replace((char)0x201C, '"').Replace((char)0x201D, '"')
            .Replace((char)0x2013, '-').Replace((char)0x2014, '-')
            .Replace(((char)0x2026).ToString(), "...")
            .Replace("\r", " ").Replace("\n", " ");

        s = s.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(s.Length);
        foreach (var ch in s)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            sb.Append(ch is >= (char)0x20 and <= (char)0x7E ? ch : '?');
        }
        return sb.ToString();
    }

    // ---------------- QR (raster, bukan native) ----------------
    // Sengaja menyalin pendekatan EscPosRenderer.EmitQr daripada memanggilnya:
    // helper di sana private dan jalur kupon TIDAK boleh ikut berubah.

    private static void EmitQr(MemoryStream ms, string content)
    {
        void W(params byte[] b) => ms.Write(b, 0, b.Length);

        var sanitized = Ascii(content);
        if (sanitized.Length == 0) return;

        const int quietModules = 2;
        const int cellDots = 5;   // kartu 80mm: QR ~26mm seperti mockup
        var generator = new QRCodeGenerator();
        var data = generator.CreateQrCode(sanitized, QRCodeGenerator.ECCLevel.M);
        var modules = ToModuleArray(data.ModuleMatrix, quietModules);
        var bitmap = BuildRasterBitmap(modules, cellDots, out var widthBytes, out var heightDots);

        W(ESC, 0x61, 0x01);   // rata tengah
        W(GS, 0x76, 0x30, 0x00,
          (byte)(widthBytes & 0xFF), (byte)((widthBytes >> 8) & 0xFF),
          (byte)(heightDots & 0xFF), (byte)((heightDots >> 8) & 0xFF));
        ms.Write(bitmap, 0, bitmap.Length);
        W(ESC, 0x64, 0x01);
        W(ESC, 0x61, 0x00);   // kembali rata kiri
    }

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
                        bytes[rowOffset + px / 8] |= (byte)(1 << (7 - px % 8));
                    }
                }
            }
        }

        return bytes;
    }
}

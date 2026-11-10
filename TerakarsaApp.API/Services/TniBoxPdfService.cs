using SkiaSharp;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 67: PDF A4 "Daftar Isi Box" PDH TNI AD.
//
// Memakai SkiaSharp (SKDocument.CreatePdf) yang SUDAH terpasang di API --
// TIDAK menambah library PDF baru. PDF dibuat SAAT DIMINTA, TIDAK disimpan ke
// disk, dan TIDAK pernah dikirim ke print job (hanya diunduh lalu dicetak di
// printer mana saja).
//
// Susunan mengikuti mockup A4 yang sudah disetujui owner. CATATAN: nama kedua
// file mockup di claude prompt/tni/ TERTUKAR -- desain A4 ini ada di file
// bernama mockup_kartu_80mm.html.
//
// Satuan ukuran Skia di sini = POINT (1/72 inci), sama dengan satuan PDF, jadi
// nilai pt dari mockup dipakai apa adanya.
//
// CATATAN API: sejak SkiaSharp 3.x, teks TIDAK lagi lewat SKPaint.TextSize /
// SKPaint.MeasureText -- ukuran & typeface pindah ke SKFont, dan DrawText butuh
// (SKFont, SKPaint). Helper Txt di bawah membungkus keduanya.
public class TniBoxPdfService
{
    // A4 dalam point
    private const float PageW = 595.28f;
    private const float PageH = 841.89f;

    // margin mockup: 9mm atas/bawah, 11mm kiri/kanan
    private const float MarginX = 11f * 72f / 25.4f;   // ~31.2pt
    private const float MarginY = 9f * 72f / 25.4f;    // ~25.5pt

    private const float RowH = 3.85f * 72f / 25.4f;    // tinggi baris tabel ~10.9pt
    private const float HeadRowH = 13f;

    public byte[] Build(TniBoxDetailDto detail)
    {
        var h = detail.Header
                ?? throw new InvalidOperationException("Header box tidak ditemukan.");

        using var ms = new MemoryStream();
        using (var doc = SKDocument.CreatePdf(ms, new SKDocumentPdfMetadata
        {
            Title = $"Daftar Isi Box No. {h.BoxNo} {h.BoxCode}",
            Creator = "Terakarsa",
            Producer = "TerakarsaApp"
        })!)
        {
            // Box gabungan menyisipkan kolom Satuan setelah Kode.
            var kolom = BuildKolom(h.Gabungan);
            // 2026-10-07: dikelompokkan per rawatan & satuan (baris judul grup), di
            // dalamnya urut NAMA personel. Baris judul grup ikut dihitung paginasi.
            var rows = SusunBaris(h, detail.Isi);
            var pages = Paginate(rows.Count);

            for (var p = 0; p < pages.Count; p++)
            {
                var canvas = doc.BeginPage(PageW, PageH);
                canvas.Clear(SKColors.White);

                var y = MarginY;

                if (p == 0)
                {
                    y = DrawKepala(canvas, h, y);
                    y = DrawMeta(canvas, h, y);
                }
                else
                {
                    y = DrawKepalaLanjutan(canvas, h, y);
                }

                var (from, count) = pages[p];
                DrawTabel(canvas, kolom, rows.GetRange(from, count), y);

                DrawKaki(canvas, h, p + 1, pages.Count);
                doc.EndPage();
            }

            doc.Close();
        }

        return ms.ToArray();
    }

    // ---------------- helper teks (SKFont + SKPaint) ----------------

    private sealed class Txt : IDisposable
    {
        public SKFont Font { get; }
        public SKPaint Paint { get; }

        public Txt(float size, bool bold = false, SKColor? color = null)
        {
            // Arial sesuai mockup; fallback ke sans-serif bawaan OS kalau tidak ada.
            var typeface =
                SKTypeface.FromFamilyName("Arial",
                    bold ? SKFontStyleWeight.Bold : SKFontStyleWeight.Normal,
                    SKFontStyleWidth.Normal, SKFontStyleSlant.Upright)
                ?? SKTypeface.FromFamilyName(null,
                    bold ? SKFontStyleWeight.Bold : SKFontStyleWeight.Normal,
                    SKFontStyleWidth.Normal, SKFontStyleSlant.Upright);

            Font = new SKFont(typeface, size) { Edging = SKFontEdging.SubpixelAntialias };
            Paint = new SKPaint
            {
                Color = color ?? SKColors.Black,
                IsAntialias = true,
                Style = SKPaintStyle.Fill
            };
        }

        public float Measure(string? s) => string.IsNullOrEmpty(s) ? 0f : Font.MeasureText(s);

        public void Dispose()
        {
            Font.Dispose();
            Paint.Dispose();
        }
    }

    // Overload tanpa SKTextAlign sudah obsolete di SkiaSharp 4.x -- selalu kirim
    // SKTextAlign.Left; perataan tengah/kanan dihitung sendiri lewat Measure().
    private static void Draw(SKCanvas canvas, string? text, float x, float y, Txt t)
    {
        if (string.IsNullOrEmpty(text)) return;
        canvas.DrawText(text, x, y, SKTextAlign.Left, t.Font, t.Paint);
    }

    private static SKPaint Line(SKColor color, float width) =>
        new() { Color = color, StrokeWidth = width, Style = SKPaintStyle.Stroke, IsAntialias = false };

    private static SKPaint Fill(SKColor color) =>
        new() { Color = color, Style = SKPaintStyle.Fill };

    // ---------------- kolom tabel ----------------

    private sealed record Kolom(string Judul, float Width, bool Center = false, bool Bold = false);

    private static List<Kolom> BuildKolom(bool gabungan)
    {
        var usable = PageW - MarginX * 2;

        // lebar tetap untuk kolom sempit, sisanya untuk Nama
        const float no = 20f;
        const float kode = 52f;
        var satuan = gabungan ? 70f : 0f;
        const float pangkat = 48f;
        const float nrp = 92f;
        const float kemeja = 62f;
        const float celana = 48f;
        const float diterima = 13f * 72f / 25.4f;   // ~36.9pt, kolom kosong untuk dicentang

        var nama = usable - (no + kode + satuan + pangkat + nrp + kemeja + celana + diterima);

        var list = new List<Kolom>
        {
            new("No", no, Center: true),
            new("Kode", kode)
        };

        if (gabungan) list.Add(new("Satuan", satuan));

        list.Add(new("Pangkat", pangkat));
        list.Add(new("Nama", nama));
        list.Add(new("NRP", nrp, Center: true));
        list.Add(new("Kemeja", kemeja, Center: true, Bold: true));
        list.Add(new("Celana", celana, Center: true, Bold: true));
        list.Add(new("Diterima", diterima));

        return list;
    }

    // ---------------- paginasi ----------------

    // 2026-11-09: kotak "Diterima oleh" dihapus -- tidak ada lagi ruang yang disisakan
    // di halaman terakhir.
    private static List<(int From, int Count)> Paginate(int total)
    {
        var pages = new List<(int, int)>();
        if (total == 0) { pages.Add((0, 0)); return pages; }

        const float kepalaH = 50f;   // judul + garis tebal
        const float metaH = 28f;     // baris info 4 kolom
        const float kakiH = 18f;

        var tinggiHal1 = PageH - MarginY * 2 - kepalaH - metaH - HeadRowH - kakiH;
        var tinggiHalN = PageH - MarginY * 2 - 26f - HeadRowH - kakiH;

        var sisa = total;
        var mulai = 0;
        var hal = 0;

        while (sisa > 0)
        {
            var tinggi = hal == 0 ? tinggiHal1 : tinggiHalN;
            var muat = Math.Max(1, (int)Math.Floor(tinggi / RowH));

            var ambil = Math.Min(muat, sisa);
            pages.Add((mulai, ambil));
            mulai += ambil;
            sisa -= ambil;
            hal++;
        }

        return pages;
    }

    // ---------------- bagian halaman ----------------

    private static float DrawKepala(SKCanvas canvas, TniBoxHeaderDto h, float y)
    {
        using var judul = new Txt(15f, bold: true);
        using var sub = new Txt(8.5f);
        using var kode = new Txt(26f, bold: true);
        using var kodeLabel = new Txt(8f);
        using var tebal = Line(SKColors.Black, 2f);

        // No box (alter_72) = urut box dalam order -- ikut judul supaya mudah dicari.
        Draw(canvas, $"DAFTAR ISI BOX NO. {h.BoxNo}", MarginX, y + 15f, judul);
        Draw(canvas,
            string.Join(" · ", new[] { h.OrderName, h.Instansi }.Where(x => !string.IsNullOrWhiteSpace(x))),
            MarginX, y + 28f, sub);

        // kode box besar di kanan
        var right = PageW - MarginX;
        Draw(canvas, h.BoxCode, right - kode.Measure(h.BoxCode), y + 24f, kode);
        Draw(canvas, "kode box", right - kodeLabel.Measure("kode box"), y + 34f, kodeLabel);

        var lineY = y + 40f;
        canvas.DrawLine(MarginX, lineY, right, lineY, tebal);

        return lineY + 10f;
    }

    // Halaman 2+: satu baris identitas, header tabel diulang.
    private static float DrawKepalaLanjutan(SKCanvas canvas, TniBoxHeaderDto h, float y)
    {
        using var f = new Txt(9f, bold: true);
        using var tipis = Line(SKColors.Black, 1f);

        Draw(canvas, $"DAFTAR ISI BOX NO. {h.BoxNo} · {h.BoxCode} (lanjutan)", MarginX, y + 10f, f);
        canvas.DrawLine(MarginX, y + 16f, PageW - MarginX, y + 16f, tipis);

        return y + 26f;
    }

    private static float DrawMeta(SKCanvas canvas, TniBoxHeaderDto h, float y)
    {
        using var label = new Txt(8.5f);
        using var nilai = new Txt(10f, bold: true);

        // 2026-11-09: kolom "Ditutup" dihapus atas permintaan owner.
        var colW = (PageW - MarginX * 2) / 3f;

        var items = new (string Label, string Nilai)[]
        {
            ("Rawatan", h.AreaName),
            ("Satuan", h.Gabungan ? "Gabungan" : h.SatuanName),
            ("Isi", $"{h.Isi} set")
        };

        for (var i = 0; i < items.Length; i++)
        {
            var x = MarginX + colW * i;
            Draw(canvas, items[i].Label, x, y + 8f, label);
            Draw(canvas, Clip(items[i].Nilai, nilai, colW - 4f), x, y + 20f, nilai);
        }

        return y + 28f;
    }

    // Satu baris tabel: judul grup (Grup terisi) ATAU data personel (Row terisi).
    private sealed record Baris(string? Grup, TniBoxIsiDto? Row, int No);

    // 2026-10-07: grup per rawatan & satuan, isi grup urut NAMA personel.
    // Rawatan diambil PER PERSONEL (box bisa berisi satuan/rawatan lain setelah
    // konfirmasi "beda satuan"). Nomor urut No bersambung 1..N melewati grup.
    // Baris judul grup TIDAK ditampilkan bila isinya hanya satu grup yang
    // rawatan & satuannya sama dengan box itu sendiri (kasus normal box satuan).
    private static List<Baris> SusunBaris(TniBoxHeaderDto h, List<TniBoxIsiDto> isi)
    {
        var hasil = new List<Baris>();
        var no = 0;
        var cmp = StringComparer.Create(new System.Globalization.CultureInfo("id-ID"), ignoreCase: true);

        var grup = isi.GroupBy(r => new { r.AreaCode, r.AreaName, r.SatuanCode, r.SatuanName })
                      .OrderBy(g => g.Key.AreaName, cmp)
                      .ThenBy(g => g.Key.SatuanName, cmp)
                      .ToList();

        var tanpaJudul = grup.Count == 1
                         && !h.Gabungan
                         && grup[0].Key.AreaCode == h.AreaCode
                         && grup[0].Key.SatuanCode == h.SatuanCode;

        foreach (var g in grup)
        {
            if (!tanpaJudul)
                hasil.Add(new Baris($"{g.Key.AreaName} · {g.Key.SatuanName} ({g.Count()})", null, 0));

            foreach (var r in g.OrderBy(r => r.Nama, cmp).ThenBy(r => r.KodeRef, cmp))
                hasil.Add(new Baris(null, r, ++no));
        }

        return hasil;
    }

    private static float DrawTabel(
        SKCanvas canvas, List<Kolom> kolom, List<Baris> rows, float y)
    {
        using var th = new Txt(8f, bold: true);
        using var td = new Txt(8.2f);
        using var tdBold = new Txt(8.2f, bold: true);
        using var border = Line(new SKColor(0x55, 0x55, 0x55), 0.6f);
        using var borderTipis = Line(new SKColor(0x99, 0x99, 0x99), 0.6f);
        using var headBg = Fill(new SKColor(0xE8, 0xE8, 0xE8));
        using var grupBg = Fill(new SKColor(0xF3, 0xF3, 0xF3));

        var x0 = MarginX;
        var totalW = kolom.Sum(k => k.Width);
        var tabelTop = y;

        // ---- header tabel
        canvas.DrawRect(new SKRect(x0, y, x0 + totalW, y + HeadRowH), headBg);
        canvas.DrawRect(new SKRect(x0, y, x0 + totalW, y + HeadRowH), border);

        var x = x0;
        foreach (var k in kolom)
        {
            canvas.DrawLine(x, y, x, y + HeadRowH, border);
            var tx = k.Center ? x + (k.Width - th.Measure(k.Judul)) / 2f : x + 3f;
            Draw(canvas, k.Judul, tx, y + 9.5f, th);
            x += k.Width;
        }

        y += HeadRowH;

        // ---- baris data
        for (var i = 0; i < rows.Count; i++)
        {
            // baris judul grup: selebar tabel, latar abu muda, teks tebal
            if (rows[i].Grup is { } grup)
            {
                var rect = new SKRect(x0, y, x0 + totalW, y + RowH);
                canvas.DrawRect(rect, grupBg);
                canvas.DrawRect(rect, borderTipis);
                Draw(canvas, Clip(grup, tdBold, totalW - 6f), x0 + 3f, y + RowH - 2.6f, tdBold);
                y += RowH;
                continue;
            }

            var nilai = BuildNilai(rows[i].Row!, rows[i].No, kolom.Count);

            canvas.DrawRect(new SKRect(x0, y, x0 + totalW, y + RowH), borderTipis);

            x = x0;
            for (var c = 0; c < kolom.Count; c++)
            {
                var k = kolom[c];
                canvas.DrawLine(x, y, x, y + RowH, borderTipis);

                var teks = nilai[c];
                if (!string.IsNullOrEmpty(teks))
                {
                    var t = k.Bold ? tdBold : td;
                    var tx = k.Center ? x + (k.Width - t.Measure(teks)) / 2f : x + 3f;
                    Draw(canvas, Clip(teks, t, k.Width - 5f), tx, y + RowH - 2.6f, t);
                }

                x += k.Width;
            }

            y += RowH;
        }

        // garis kanan penutup seluruh tabel
        canvas.DrawLine(x0 + totalW, tabelTop, x0 + totalW, y, border);

        return y + 7f;
    }

    private static string[] BuildNilai(TniBoxIsiDto r, int no, int kolomCount)
    {
        // 9 kolom = box gabungan (ada kolom Satuan); 8 kolom = box satuan
        if (kolomCount == 9)
            return new[]
            {
                no.ToString(), r.KodeRef, r.SatuanCode, r.Pangkat ?? string.Empty,
                r.Nama, r.Nrp, r.PolaKemejaKode, r.PolaCelanaKode, string.Empty
            };

        return new[]
        {
            no.ToString(), r.KodeRef, r.Pangkat ?? string.Empty,
            r.Nama, r.Nrp, r.PolaKemejaKode, r.PolaCelanaKode, string.Empty
        };
    }

    // 2026-11-09: rekap kemeja/celana, "Dipacking oleh", "Ditutup oleh", kotak
    // "Diterima oleh", dan teks "dicetak dari Terakarsa" dihapus atas permintaan owner --
    // kaki halaman tinggal nomor box + halaman di kanan.
    private static void DrawKaki(SKCanvas canvas, TniBoxHeaderDto h, int hal, int totalHal)
    {
        using var f = new Txt(7f, color: new SKColor(0x44, 0x44, 0x44));

        var y = PageH - MarginY + 4f;

        var kanan = $"No. {h.BoxNo} · {h.BoxCode} · hal {hal}/{totalHal}";
        Draw(canvas, kanan, PageW - MarginX - f.Measure(kanan), y, f);
    }

    // Potong teks supaya tidak melimpah keluar kolom.
    private static string Clip(string? text, Txt t, float maxWidth)
    {
        if (string.IsNullOrEmpty(text) || t.Measure(text) <= maxWidth) return text ?? string.Empty;

        var s = text;
        while (s.Length > 1 && t.Measure(s + "…") > maxWidth)
            s = s.Substring(0, s.Length - 1);

        return s + "…";
    }
}

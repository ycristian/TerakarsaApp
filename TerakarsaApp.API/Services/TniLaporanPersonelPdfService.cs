using System.Globalization;
using SkiaSharp;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 89: PDF A4 LANDSCAPE "Laporan Personel & Box" PDH TNI AD.
//
// Pola sama dengan TniBoxPdfService: SkiaSharp (SKDocument.CreatePdf), dibuat
// SAAT DIMINTA, TIDAK disimpan ke disk, TIDAK lewat print job -- hanya diunduh.
// Susunan mengikuti claude prompt/mockup_laporan_personel_a4.html.
//
// Satuan ukuran = POINT (1/72 inci). Landscape karena tabelnya 11-12 kolom.
//
// Tata letak dihitung DULU (RencanakanHalaman) baru digambar, karena kaki
// halaman butuh jumlah halaman total ("hal x/y") sejak halaman pertama.
public class TniLaporanPersonelPdfService
{
    // A4 landscape dalam point
    private const float PageW = 841.89f;
    private const float PageH = 595.28f;
    private const float Margin = 10f * 72f / 25.4f;          // ~28.3pt

    private const float KakiH = 14f;                          // ruang kaki halaman
    private const float ContentBottom = PageH - Margin - KakiH;

    private const float KepalaH = 58f;                        // kepala halaman 1
    private const float HeadRowH = 16f;
    private const float RowH = 17f;                           // -> 26 baris hal 1, 30 baris hal penuh

    // blok bawah (rekap box)
    private const float GapTabel = 9f;
    private const float RekapJudulH = 18f;
    private const float RekapHeadH = 14f;
    private const float RekapRowH = 13f;
    private const float RekapPadBawah = 8f;
    private const float CatatanH = 24f;

    private static readonly CultureInfo Id = new("id-ID");

    private static readonly SKColor Navy = new(0x1F, 0x3A, 0x5F);
    private static readonly SKColor Mut = new(0x6B, 0x72, 0x80);
    private static readonly SKColor LineC = new(0xD1, 0xD5, 0xDB);
    private static readonly SKColor Soft = new(0xF3, 0xF4, 0xF6);
    // Baris belum masuk box. Mockup memakai abu-abu #9CA3AF, tapi tidak terbaca --
    // owner minta HITAM (2026-11-09). Pembedanya kini: kode tidak tebal + box "—".
    private static readonly SKColor Dim = SKColors.Black;
    private static readonly SKColor HeadText = new(0x37, 0x41, 0x51);

    public byte[] Build(TniLaporanPersonelDto data)
    {
        var h = data.Header ?? throw new InvalidOperationException("Header laporan tidak ditemukan.");

        // Kolom Satuan hanya bila lingkup mencakup lebih dari satu satuan.
        var kolom = BuildKolom(h.JumlahSatuan > 1);
        var rencana = RencanakanHalaman(data.Baris.Count, data.Box.Count);
        var labelKaki = h.SatuanCode ?? h.AreaCode ?? h.OrderName;

        using var ms = new MemoryStream();
        using (var doc = SKDocument.CreatePdf(ms, new SKDocumentPdfMetadata
        {
            Title = $"Laporan Personel & Box {labelKaki}",
            Creator = "Terakarsa",
            Producer = "TerakarsaApp"
        })!)
        {
            for (var p = 0; p < rencana.Count; p++)
            {
                var r = rencana[p];
                var canvas = doc.BeginPage(PageW, PageH);
                canvas.Clear(SKColors.White);

                var y = Margin;

                if (r.Kepala) y = DrawKepala(canvas, data, y);

                if (r.RowCount > 0)
                    y = DrawTabel(canvas, kolom, data.Baris, r.RowFrom, r.RowCount, y) + GapTabel;

                if (r.Bawah)
                {
                    y = DrawBawah(canvas, data.Box, r, y);
                    if (r.Catatan) DrawCatatan(canvas, y);
                }

                DrawKaki(canvas, data.DicetakPada, labelKaki, p + 1, rencana.Count);
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

        public Txt(float size, bool bold = false, SKColor? color = null, bool mono = false)
        {
            var weight = bold ? SKFontStyleWeight.Bold : SKFontStyleWeight.Normal;

            // Arial / Consolas sesuai mockup; fallback sans-serif / Courier New / bawaan OS.
            var typeface = mono
                ? (SKTypeface.FromFamilyName("Consolas", weight, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright)
                   ?? SKTypeface.FromFamilyName("Courier New", weight, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright))
                : SKTypeface.FromFamilyName("Arial", weight, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright);

            typeface ??= SKTypeface.FromFamilyName(null, weight, SKFontStyleWidth.Normal, SKFontStyleSlant.Upright);

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

    // Overload tanpa SKTextAlign obsolete di SkiaSharp 4.x -- selalu Left,
    // perataan tengah/kanan dihitung sendiri lewat Measure().
    private static void Draw(SKCanvas canvas, string? text, float x, float y, Txt t)
    {
        if (string.IsNullOrEmpty(text)) return;
        canvas.DrawText(text, x, y, SKTextAlign.Left, t.Font, t.Paint);
    }

    private static SKPaint Line(SKColor color, float width) =>
        new() { Color = color, StrokeWidth = width, Style = SKPaintStyle.Stroke, IsAntialias = false };

    private static SKPaint Fill(SKColor color) =>
        new() { Color = color, Style = SKPaintStyle.Fill };

    // Potong teks supaya tidak melimpah keluar kolom.
    private static string Clip(string? text, Txt t, float maxWidth)
    {
        if (string.IsNullOrEmpty(text) || t.Measure(text) <= maxWidth) return text ?? string.Empty;

        var s = text;
        while (s.Length > 1 && t.Measure(s + "…") > maxWidth)
            s = s.Substring(0, s.Length - 1);

        return s + "…";
    }

    // ---------------- kolom tabel ----------------

    private enum Isi { No, Kode, Satuan, Pangkat, Nama, Nrp, NoHp, Gender, Kemeja, Celana, BoxNo, BoxCode }

    private sealed record Kolom(string Judul, float Width, Isi Isi, bool Center = false, bool Right = false);

    private static List<Kolom> BuildKolom(bool denganSatuan)
    {
        var usable = PageW - Margin * 2;

        // lebar tetap untuk kolom sempit, sisanya untuk Nama
        const float no = 24f;
        const float kode = 52f;
        var satuan = denganSatuan ? 96f : 0f;
        const float pangkat = 62f;
        const float nrp = 88f;
        const float noHp = 74f;
        const float gender = 44f;
        const float kemeja = 58f;
        const float celana = 48f;
        const float boxNo = 42f;
        const float boxCode = 66f;

        var nama = usable - (no + kode + satuan + pangkat + nrp + noHp + gender + kemeja + celana + boxNo + boxCode);

        var list = new List<Kolom>
        {
            new("No", no, Isi.No, Right: true),
            new("Kode", kode, Isi.Kode)
        };

        if (denganSatuan) list.Add(new("Satuan", satuan, Isi.Satuan));

        list.Add(new("Pangkat", pangkat, Isi.Pangkat));
        list.Add(new("Nama", nama, Isi.Nama));
        list.Add(new("NRP", nrp, Isi.Nrp));
        list.Add(new("No HP", noHp, Isi.NoHp));
        list.Add(new("Gender", gender, Isi.Gender));
        list.Add(new("Kemeja", kemeja, Isi.Kemeja));
        list.Add(new("Celana", celana, Isi.Celana));
        list.Add(new("No. Box", boxNo, Isi.BoxNo, Center: true));
        list.Add(new("Kode Box", boxCode, Isi.BoxCode));

        return list;
    }

    // ---------------- rencana halaman ----------------

    private sealed record Halaman(
        bool Kepala, int RowFrom, int RowCount,
        bool Bawah, int RekapFrom, int RekapCount, bool Catatan);

    private static float TinggiRekap(int rekapCount) =>
        RekapJudulH + RekapHeadH + Math.Max(1, rekapCount) * RekapRowH + RekapPadBawah;

    private static List<Halaman> RencanakanHalaman(int totalBaris, int totalBox)
    {
        var hasil = new List<Halaman>();

        // ---- 1. baris tabel
        var mulai = 0;
        var sisaTinggi = 0f;    // ruang tersisa di bawah tabel halaman terakhir

        do
        {
            var kepala = hasil.Count == 0;
            var top = Margin + (kepala ? KepalaH : 0f);
            var tinggi = ContentBottom - top;
            var muat = Math.Max(1, (int)Math.Floor((tinggi - HeadRowH) / RowH));
            var ambil = Math.Min(muat, totalBaris - mulai);

            hasil.Add(new Halaman(kepala, mulai, ambil, false, 0, 0, false));
            mulai += ambil;
            sisaTinggi = tinggi - HeadRowH - ambil * RowH - GapTabel;
        }
        while (mulai < totalBaris);

        // ---- 2. blok bawah: rekap box, lalu catatan. (Kotak tanda tangan
        // dihapus atas permintaan owner, 2026-11-09.)
        // Coba di sisa halaman terakhir; kalau tidak muat, pindah ke halaman baru.
        // Rekap yang lebih tinggi dari satu halaman penuh dipecah (lanjutan).
        var tinggiPenuh = ContentBottom - Margin;

        if (TinggiRekap(totalBox) + CatatanH <= sisaTinggi)
        {
            hasil[^1] = hasil[^1] with { Bawah = true, RekapFrom = 0, RekapCount = totalBox, Catatan = true };
            return hasil;
        }

        var rekapMulai = 0;

        while (true)
        {
            var sisaRekap = totalBox - rekapMulai;

            if (TinggiRekap(sisaRekap) + CatatanH <= tinggiPenuh)
            {
                hasil.Add(new Halaman(false, 0, 0, true, rekapMulai, sisaRekap, true));
                return hasil;
            }

            var muat = Math.Max(1, (int)Math.Floor(
                (tinggiPenuh - RekapJudulH - RekapHeadH - RekapPadBawah) / RekapRowH));
            var ambil = Math.Min(muat, sisaRekap);

            hasil.Add(new Halaman(false, 0, 0, true, rekapMulai, ambil, false));
            rekapMulai += ambil;
        }
    }

    // ---------------- kepala (hanya halaman 1) ----------------

    private static float DrawKepala(SKCanvas canvas, TniLaporanPersonelDto data, float y)
    {
        var h = data.Header!;

        using var t1 = new Txt(8f, bold: true, color: Mut);
        using var t2 = new Txt(14f, bold: true, color: Navy);
        using var t3 = new Txt(9f, color: new SKColor(0x33, 0x33, 0x33));
        using var t3b = new Txt(9f, bold: true, color: SKColors.Black);
        using var rt = new Txt(8.5f, color: Mut);
        using var rtb = new Txt(8.5f, bold: true, color: SKColors.Black);
        using var tebal = Line(Navy, 2.2f);

        var right = PageW - Margin;

        Draw(canvas, "LAPORAN PERSONEL & BOX", Margin, y + 9f, t1);

        var judul = string.Join(" — ",
            new[] { h.OrderName, h.Instansi }.Where(x => !string.IsNullOrWhiteSpace(x)))
            .ToUpper(Id);
        Draw(canvas, Clip(judul, t2, PageW - Margin * 2 - 190f), Margin, y + 27f, t2);

        // baris keterangan filter: potongan biasa / tebal disambung berurutan
        var x = Margin;
        foreach (var (teks, bold) in BarisFilter(data))
        {
            var t = bold ? t3b : t3;
            Draw(canvas, teks, x, y + 41f, t);
            x += t.Measure(teks);
        }

        // kanan: waktu cetak (lokal), TANPA nama pencetak
        var waktu = data.DicetakPada.ToString("dddd, d MMM yyyy · HH':'mm", Id);
        var lebarWaktu = rt.Measure("Dicetak ") + rtb.Measure(waktu);
        Draw(canvas, "Dicetak ", right - lebarWaktu, y + 30f, rt);
        Draw(canvas, waktu, right - rtb.Measure(waktu), y + 30f, rtb);

        const string dataPer = "Data per saat cetak";
        Draw(canvas, dataPer, right - rt.Measure(dataPer), y + 41f, rt);

        var lineY = y + 48f;
        canvas.DrawLine(Margin, lineY, right, lineY, tebal);

        return y + KepalaH;
    }

    private static List<(string Teks, bool Bold)> BarisFilter(TniLaporanPersonelDto data)
    {
        var h = data.Header!;
        var n = h.TotalBaris.ToString("N0", Id);
        var seg = new List<(string, bool)>();

        if (!string.IsNullOrEmpty(h.SatuanName))
        {
            if (!string.IsNullOrEmpty(h.AreaName))
            {
                seg.Add(("Rawatan ", false));
                seg.Add((h.AreaName!, true));
                seg.Add((" · ", false));
            }
            seg.Add(("Satuan ", false));
            seg.Add((h.SatuanName!, true));
        }
        else if (!string.IsNullOrEmpty(h.AreaName))
        {
            seg.Add(("Rawatan ", false));
            seg.Add((h.AreaName!, true));
            seg.Add((" · ", false));
            seg.Add(("Semua satuan", true));
            seg.Add(($" ({n} orang)", false));
        }
        else
        {
            seg.Add(("Seluruh Kodam", true));
            seg.Add(($" · {n} orang", false));
        }

        if (!string.IsNullOrEmpty(data.Status))
        {
            seg.Add((" · Status ", false));
            seg.Add((LabelStatusPersonel(data.Status!), true));
        }

        if (!string.IsNullOrEmpty(h.PolaKemejaKode))
        {
            seg.Add((" · Kemeja ", false));
            seg.Add((h.PolaKemejaKode!, true));
        }

        if (!string.IsNullOrEmpty(h.PolaCelanaKode))
        {
            seg.Add((" · Celana ", false));
            seg.Add((h.PolaCelanaKode!, true));
        }

        if (data.PerluReview)
        {
            seg.Add((" · ", false));
            seg.Add(("Perlu review", true));
        }

        if (!string.IsNullOrWhiteSpace(data.Search))
            seg.Add(($" · Pencarian \"{data.Search!.Trim()}\"", false));

        return seg;
    }

    // label sama dengan pilihan filter di /tni/personel
    private static string LabelStatusPersonel(string status) => status switch
    {
        "BELUM_CETAK" => "Belum cetak",
        "DICETAK" => "Kartu dicetak",
        "SET_JADI" => "Set jadi",
        "MASUK_BOX" => "Masuk box",
        "TERKIRIM" => "Terkirim",
        _ => status
    };

    // ---------------- tabel ----------------

    private static float DrawTabel(
        SKCanvas canvas, List<Kolom> kolom, List<TniLaporanPersonelBarisDto> baris,
        int from, int count, float y)
    {
        using var th = new Txt(7.5f, bold: true, color: HeadText);
        using var td = new Txt(8.2f);
        using var tdMono = new Txt(8.2f, mono: true);
        using var tdMonoBold = new Txt(8.2f, bold: true, mono: true);
        using var tdNo = new Txt(8.2f, color: Mut);
        using var dim = new Txt(8.2f, color: Dim);
        using var dimMono = new Txt(8.2f, mono: true, color: Dim);
        using var border = Line(LineC, 0.6f);
        using var headBg = Fill(Soft);

        var x0 = Margin;
        var totalW = kolom.Sum(k => k.Width);

        // ---- header tabel (diulang tiap halaman)
        var headRect = new SKRect(x0, y, x0 + totalW, y + HeadRowH);
        canvas.DrawRect(headRect, headBg);
        canvas.DrawRect(headRect, border);

        var x = x0;
        foreach (var k in kolom)
        {
            canvas.DrawLine(x, y, x, y + HeadRowH, border);
            var judul = k.Judul.ToUpper(Id);
            var tx = k.Center ? x + (k.Width - th.Measure(judul)) / 2f
                   : k.Right ? x + k.Width - 4f - th.Measure(judul)
                   : x + 4f;
            Draw(canvas, judul, tx, y + 10.6f, th);
            x += k.Width;
        }

        y += HeadRowH;

        // ---- baris data
        for (var i = 0; i < count; i++)
        {
            var r = baris[from + i];
            var belumBox = r.BoxNo is null;

            canvas.DrawRect(new SKRect(x0, y, x0 + totalW, y + RowH), border);

            x = x0;
            foreach (var k in kolom)
            {
                canvas.DrawLine(x, y, x, y + RowH, border);

                var (teks, t) = Nilai(k.Isi, r, from + i + 1, belumBox,
                                      td, tdMono, tdMonoBold, tdNo, dim, dimMono);

                if (!string.IsNullOrEmpty(teks))
                {
                    var c = Clip(teks, t, k.Width - 7f);
                    var tx = k.Center ? x + (k.Width - t.Measure(c)) / 2f
                           : k.Right ? x + k.Width - 4f - t.Measure(c)
                           : x + 4f;
                    Draw(canvas, c, tx, y + RowH - 5.6f, t);
                }

                x += k.Width;
            }

            y += RowH;
        }

        return y;
    }

    // Kode, No. Box & Kode Box monospace tebal; kode pola monospace.
    // Baris belum masuk box: abu-abu, monospace tidak tebal, box "—".
    private static (string Teks, Txt Font) Nilai(
        Isi isi, TniLaporanPersonelBarisDto r, int no, bool belumBox,
        Txt td, Txt tdMono, Txt tdMonoBold, Txt tdNo, Txt dim, Txt dimMono)
    {
        var biasa = belumBox ? dim : td;
        var mono = belumBox ? dimMono : tdMono;
        var monoBold = belumBox ? dimMono : tdMonoBold;

        return isi switch
        {
            Isi.No => (no.ToString(Id), belumBox ? dim : tdNo),
            Isi.Kode => (r.KodeRef, monoBold),
            Isi.Satuan => (r.SatuanName, biasa),
            Isi.Pangkat => (r.Pangkat ?? string.Empty, biasa),
            Isi.Nama => (r.Nama, biasa),
            Isi.Nrp => (r.Nrp, biasa),
            Isi.NoHp => (r.NoHp ?? string.Empty, biasa),
            Isi.Gender => (r.Gender == "PRIA" ? "Pria" : "Wanita", biasa),
            Isi.Kemeja => (r.PolaKemejaKode, mono),
            Isi.Celana => (r.PolaCelanaKode, mono),
            Isi.BoxNo => (belumBox ? "—" : $"#{r.BoxNo}", monoBold),
            Isi.BoxCode => (belumBox ? "—" : r.BoxCode ?? "—", monoBold),
            _ => (string.Empty, biasa)
        };
    }

    // ---------------- blok bawah: rekap box ----------------
    // Kotak tanda tangan (Diserahkan / Diterima oleh) dihapus atas permintaan
    // owner (2026-11-09); rekap tetap selebar separuh halaman seperti mockup.

    private static float DrawBawah(SKCanvas canvas, List<TniLaporanPersonelBoxDto> box, Halaman r, float y)
    {
        using var label = new Txt(7.5f, bold: true, color: Mut);
        using var th = new Txt(7.5f, bold: true, color: HeadText);
        using var td = new Txt(8f);
        using var tdMono = new Txt(8f, bold: true, mono: true);
        using var kecil = new Txt(8f, color: Mut);
        using var border = Line(LineC, 0.7f);
        using var headBg = Fill(Soft);

        const float gap = 16f;
        var w = (PageW - Margin * 2 - gap) / 2f;
        var tinggi = TinggiRekap(r.RekapCount);

        var x1 = Margin;
        canvas.DrawRect(new SKRect(x1, y, x1 + w, y + tinggi), border);

        var judul = r.RekapFrom == 0 ? "REKAP BOX" : "REKAP BOX (LANJUTAN)";
        Draw(canvas, judul, x1 + 8f, y + 12f, label);

        var ix = x1 + 8f;
        var iw = w - 16f;
        var cols = new[]
        {
            ("Box", iw * 0.30f, false),
            ("Status", iw * 0.26f, false),
            ("Isi", iw * 0.24f, true),
            ("Ditutup / dikirim", iw * 0.20f, false)
        };

        var ty = y + RekapJudulH;
        var tw = cols.Sum(c => c.Item2);
        canvas.DrawRect(new SKRect(ix, ty, ix + tw, ty + RekapHeadH), headBg);
        canvas.DrawRect(new SKRect(ix, ty, ix + tw, ty + RekapHeadH), border);

        var cx = ix;
        foreach (var (j, cw, kanan) in cols)
        {
            var jj = j.ToUpper(Id);
            Draw(canvas, jj, kanan ? cx + cw - 4f - th.Measure(jj) : cx + 4f, ty + 9.6f, th);
            cx += cw;
        }

        ty += RekapHeadH;

        if (r.RekapCount == 0)
        {
            canvas.DrawRect(new SKRect(ix, ty, ix + tw, ty + RekapRowH), border);
            Draw(canvas, "Belum ada personel lingkup ini di dalam box.", ix + 4f, ty + RekapRowH - 3.8f, kecil);
        }

        for (var i = 0; i < r.RekapCount; i++)
        {
            var b = box[r.RekapFrom + i];
            canvas.DrawRect(new SKRect(ix, ty, ix + tw, ty + RekapRowH), border);

            var status = LabelStatusBox(b.Status);
            var nilai = new (string Teks, Txt Font)[]
            {
                ($"#{b.BoxNo} {b.BoxCode}", tdMono),
                (b.Gabungan ? $"Gabungan · {status}" : status, td),
                (b.Gabungan || b.IsiDariLingkup != b.Isi
                    ? $"{b.IsiDariLingkup.ToString("N0", Id)} dari lingkup ini"
                    : b.Isi.ToString("N0", Id), td),
                ((b.ShippedAt ?? b.PackedAt)?.ToString("d MMM yyyy", Id) ?? "—", td)
            };

            cx = ix;
            for (var c = 0; c < cols.Length; c++)
            {
                var (_, cw, kanan) = cols[c];
                var teks = Clip(nilai[c].Teks, nilai[c].Font, cw - 7f);
                Draw(canvas, teks,
                     kanan ? cx + cw - 4f - nilai[c].Font.Measure(teks) : cx + 4f,
                     ty + RekapRowH - 3.8f, nilai[c].Font);
                cx += cw;
            }

            ty += RekapRowH;
        }

        return y + tinggi;
    }

    private static string LabelStatusBox(string status) => status switch
    {
        "TERKIRIM" => "Terkirim",
        "TERTUTUP" => "Tertutup",
        "TERBUKA" => "Terbuka",
        _ => status
    };

    private static void DrawCatatan(SKCanvas canvas, float y)
    {
        using var f = new Txt(7.5f, color: Mut);

        // No. Box = tni.box.box_no (alter_72): nomor urut box dalam order, sama
        // dengan "No." yang tampil di halaman Box & Scan.
        const string catatan =
            "Data mengikuti kondisi sistem saat laporan dicetak. Personel yang belum masuk box ditandai " +
            "No. Box —. No. Box = nomor urut box di aplikasi (urut dalam order), " +
            "Kode Box = kode di kardus.";

        var baris = Bungkus(catatan, f, PageW - Margin * 2);
        for (var i = 0; i < baris.Count; i++)
            Draw(canvas, baris[i], Margin, y + 11f + i * 10f, f);
    }

    private static List<string> Bungkus(string teks, Txt t, float maxW)
    {
        var hasil = new List<string>();
        var baris = string.Empty;

        foreach (var kata in teks.Split(' '))
        {
            var coba = baris.Length == 0 ? kata : baris + " " + kata;
            if (t.Measure(coba) > maxW && baris.Length > 0)
            {
                hasil.Add(baris);
                baris = kata;
            }
            else baris = coba;
        }

        if (baris.Length > 0) hasil.Add(baris);
        return hasil;
    }

    // ---------------- kaki tiap halaman ----------------

    private static void DrawKaki(SKCanvas canvas, DateTime dicetak, string label, int hal, int totalHal)
    {
        using var f = new Txt(7.5f, color: Mut);
        using var garis = Line(LineC, 0.6f);

        var lineY = PageH - Margin - 7f;
        canvas.DrawLine(Margin, lineY, PageW - Margin, lineY, garis);

        var y = lineY + 10f;
        Draw(canvas, $"Dicetak dari Terakarsa · data per {dicetak.ToString("d MMM yyyy HH':'mm", Id)}",
             Margin, y, f);

        var kanan = $"{label} · hal {hal}/{totalHal}";
        Draw(canvas, kanan, PageW - Margin - f.Measure(kanan), y, f);
    }
}

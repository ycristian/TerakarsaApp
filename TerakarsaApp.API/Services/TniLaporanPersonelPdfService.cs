using System.Globalization;
using SkiaSharp;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 89: PDF A4 "Laporan Personel & Box" PDH TNI AD.
//
// Pola sama dengan TniBoxPdfService: SkiaSharp (SKDocument.CreatePdf), dibuat
// SAAT DIMINTA, TIDAK disimpan ke disk, TIDAK lewat print job -- hanya diunduh.
// Susunan mengikuti claude prompt/mockup_laporan_personel_a4.html.
//
// Satuan ukuran = POINT (1/72 inci). Awalnya landscape; owner minta PORTRAIT
// dipaksakan (2026-11-18) -- kolom & font dipadatkan, Nama/Satuan yang
// kepanjangan dipotong "…" (diterima owner).
//
// Tata letak dihitung DULU (RencanakanHalaman) baru digambar, karena kaki
// halaman butuh jumlah halaman total ("hal x/y") sejak halaman pertama.
public class TniLaporanPersonelPdfService
{
    // A4 portrait dalam point
    private const float PageW = 595.28f;
    private const float PageH = 841.89f;
    private const float Margin = 10f * 72f / 25.4f;          // ~28.3pt

    private const float KakiH = 14f;                          // ruang kaki halaman
    private const float ContentBottom = PageH - Margin - KakiH;

    private const float KepalaH = 58f;                        // kepala halaman 1
    private const float HeadRowH = 20f;                       // muat judul 2 baris ("HADIR / UKUR")
    private const float RowH = 15f;                           // baris biasa -> ±46 baris hal 1, ±50 hal penuh
    private const float RowH2 = 24f;                          // baris dengan nama 2 baris
    private const float NamaLineH = 9f;                       // jarak antarbaris nama
    private const float HeadLineH = 7.5f;                     // jarak antarbaris judul kolom

    // ukuran font tabel personel (dipadatkan untuk portrait)
    private const float FontHead = 6.4f;
    private const float FontIsi = 7.5f;

    // blok bawah (rekap box)
    private const float GapTabel = 9f;
    private const float RekapJudulH = 18f;
    private const float RekapHeadH = 14f;
    private const float RekapRowH = 13f;
    private const float RekapPadBawah = 8f;
    private const float CatatanH = 0f;                        // catatan kaki dihapus (2026-11-18)

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

        // Nama panjang dibungkus jadi 2 baris -> tinggi baris tidak seragam,
        // jadi dihitung dulu sebelum merencanakan halaman.
        var namaW = kolom.First(k => k.Isi == Isi.Nama).Width - 7f;
        List<List<string>> namaBaris;
        using (var tNama = new Txt(FontIsi))
            namaBaris = data.Baris.Select(b => BagiNama(b.Nama, tNama, namaW)).ToList();
        var tinggiBaris = namaBaris.Select(l => l.Count > 1 ? RowH2 : RowH).ToList();

        var rencana = RencanakanHalaman(tinggiBaris, data.Box.Count);
        var hadirUkur = data.Baris.Count(b => b.HadirUkur);
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
                    y = DrawTabel(canvas, kolom, data.Baris, namaBaris, tinggiBaris,
                                  r.RowFrom, r.RowCount, y) + GapTabel;

                if (r.Bawah)
                    DrawBawah(canvas, data.Box, r, y, hadirUkur, data.Baris.Count - hadirUkur);

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

    // Kolom Kode (kode_ref) & Kode Box dihapus atas permintaan owner (2026-11-18):
    // No sudah mencerminkan urutan, cukup No. Box. Ditambah kolom "Hadir Ukur".
    private enum Isi { No, Satuan, Pangkat, Nama, Nrp, NoHp, Gender, Kemeja, Celana, HadirUkur, BoxNo }

    // Judul boleh berisi '\n' -> digambar 2 baris (hemat lebar).
    private sealed record Kolom(string Judul, float Width, Isi Isi, bool Center = false, bool Right = false);

    private static List<Kolom> BuildKolom(bool denganSatuan)
    {
        var usable = PageW - Margin * 2;

        // Portrait: lebar tetap untuk kolom sempit (cukup untuk NRP 16 digit &
        // No HP 13 digit pada font 7.5pt), sisanya untuk Nama (dibungkus 2 baris).
        const float no = 22f;
        var satuan = denganSatuan ? 60f : 0f;
        const float pangkat = 46f;
        const float nrp = 76f;
        const float noHp = 62f;
        const float gender = 34f;
        const float kemeja = 50f;
        const float celana = 42f;
        const float hadir = 30f;
        const float boxNo = 34f;

        var nama = usable - (no + satuan + pangkat + nrp + noHp + gender + kemeja + celana + hadir + boxNo);

        var list = new List<Kolom> { new("No", no, Isi.No, Right: true) };

        if (denganSatuan) list.Add(new("Satuan", satuan, Isi.Satuan));

        list.Add(new("Pangkat", pangkat, Isi.Pangkat));
        list.Add(new("Nama", nama, Isi.Nama));
        list.Add(new("NRP", nrp, Isi.Nrp, Center: true));
        list.Add(new("No HP", noHp, Isi.NoHp, Center: true));
        list.Add(new("Gender", gender, Isi.Gender, Center: true));
        list.Add(new("Kemeja", kemeja, Isi.Kemeja, Center: true));
        list.Add(new("Celana", celana, Isi.Celana, Center: true));
        list.Add(new("Hadir\nUkur", hadir, Isi.HadirUkur, Center: true));
        list.Add(new("No. Box", boxNo, Isi.BoxNo, Center: true));

        return list;
    }

    // Nama dibungkus maksimal 2 baris; sisa yang tetap tidak muat dipotong "…".
    private static List<string> BagiNama(string? nama, Txt t, float maxW)
    {
        var teks = (nama ?? string.Empty).Trim();
        if (t.Measure(teks) <= maxW) return [teks];

        var baris = Bungkus(teks, t, maxW);
        var b1 = Clip(baris[0], t, maxW);          // satu kata yang lebih lebar dari kolom
        if (baris.Count == 1) return [b1];

        var b2 = Clip(string.Join(" ", baris.Skip(1)), t, maxW);
        return [b1, b2];
    }

    // ---------------- rencana halaman ----------------

    private sealed record Halaman(
        bool Kepala, int RowFrom, int RowCount,
        bool Bawah, int RekapFrom, int RekapCount, bool Catatan);

    private static float TinggiRekap(int rekapCount) =>
        RekapJudulH + RekapHeadH + Math.Max(1, rekapCount) * RekapRowH + RekapPadBawah;

    // Rekap pengukuran (2026-11-18): Hadir / Tidak hadir / Total, di kanan rekap box.
    private const float TinggiUkur = RekapJudulH + RekapHeadH + 3 * RekapRowH + RekapPadBawah;

    // Rekap pengukuran hanya ikut di potongan rekap box yang pertama.
    private static float TinggiBawah(int rekapFrom, int rekapCount) =>
        rekapFrom == 0 ? Math.Max(TinggiRekap(rekapCount), TinggiUkur) : TinggiRekap(rekapCount);

    private static List<Halaman> RencanakanHalaman(List<float> tinggiBaris, int totalBox)
    {
        var hasil = new List<Halaman>();
        var totalBaris = tinggiBaris.Count;

        // ---- 1. baris tabel (tinggi per baris bisa beda: nama 2 baris)
        var mulai = 0;
        var sisaTinggi = 0f;    // ruang tersisa di bawah tabel halaman terakhir

        do
        {
            var kepala = hasil.Count == 0;
            var top = Margin + (kepala ? KepalaH : 0f);
            var sisa = ContentBottom - top - HeadRowH;
            var ambil = 0;

            while (mulai + ambil < totalBaris && tinggiBaris[mulai + ambil] <= sisa)
            {
                sisa -= tinggiBaris[mulai + ambil];
                ambil++;
            }

            if (ambil == 0 && mulai < totalBaris)   // jaga-jaga: minimal 1 baris per halaman
            {
                sisa -= tinggiBaris[mulai];
                ambil = 1;
            }

            hasil.Add(new Halaman(kepala, mulai, ambil, false, 0, 0, false));
            mulai += ambil;
            sisaTinggi = sisa - GapTabel;
        }
        while (mulai < totalBaris);

        // ---- 2. blok bawah: rekap box, lalu catatan. (Kotak tanda tangan
        // dihapus atas permintaan owner, 2026-11-09.)
        // Coba di sisa halaman terakhir; kalau tidak muat, pindah ke halaman baru.
        // Rekap yang lebih tinggi dari satu halaman penuh dipecah (lanjutan).
        var tinggiPenuh = ContentBottom - Margin;

        if (TinggiBawah(0, totalBox) + CatatanH <= sisaTinggi)
        {
            hasil[^1] = hasil[^1] with { Bawah = true, RekapFrom = 0, RekapCount = totalBox, Catatan = true };
            return hasil;
        }

        var rekapMulai = 0;

        while (true)
        {
            var sisaRekap = totalBox - rekapMulai;

            if (TinggiBawah(rekapMulai, sisaRekap) + CatatanH <= tinggiPenuh)
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
        // kanan: waktu cetak (lokal), TANPA nama pencetak
        var waktu = data.DicetakPada.ToString("dddd, d MMM yyyy · HH':'mm", Id);
        var lebarWaktu = rt.Measure("Dicetak ") + rtb.Measure(waktu);
        Draw(canvas, "Dicetak ", right - lebarWaktu, y + 30f, rt);
        Draw(canvas, waktu, right - rtb.Measure(waktu), y + 30f, rtb);

        const string dataPer = "Data per saat cetak";
        Draw(canvas, dataPer, right - rt.Measure(dataPer), y + 41f, rt);

        // Portrait sempit: keterangan filter dipotong "…" sebelum menabrak
        // "Data per saat cetak" di kanan.
        var batasFilter = right - rt.Measure(dataPer) - 10f;
        var x = Margin;
        foreach (var (teks, bold) in BarisFilter(data))
        {
            var t = bold ? t3b : t3;
            var sisa = batasFilter - x;
            if (sisa <= 0f) break;

            if (t.Measure(teks) > sisa)
            {
                Draw(canvas, Clip(teks, t, sisa), x, y + 41f, t);
                break;
            }

            Draw(canvas, teks, x, y + 41f, t);
            x += t.Measure(teks);
        }

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

    // Baseline teks satu baris yang ditengahkan vertikal dalam sel setinggi h.
    private static float BaselineTengah(float top, float h, float fontSize) =>
        top + h / 2f + fontSize * 0.36f;

    private static float DrawTabel(
        SKCanvas canvas, List<Kolom> kolom, List<TniLaporanPersonelBarisDto> baris,
        List<List<string>> namaBaris, List<float> tinggiBaris,
        int from, int count, float y)
    {
        using var th = new Txt(FontHead, bold: true, color: HeadText);
        using var td = new Txt(FontIsi);
        using var tdMono = new Txt(FontIsi, mono: true);
        using var tdMonoBold = new Txt(FontIsi, bold: true, mono: true);
        using var tdNo = new Txt(FontIsi, color: Mut);
        using var dim = new Txt(FontIsi, color: Dim);
        using var dimMono = new Txt(FontIsi, mono: true, color: Dim);
        using var border = Line(LineC, 0.6f);
        using var headBg = Fill(Soft);
        using var centang = new SKPaint
        {
            Color = SKColors.Black, StrokeWidth = 1.1f, Style = SKPaintStyle.Stroke,
            IsAntialias = true, StrokeCap = SKStrokeCap.Round, StrokeJoin = SKStrokeJoin.Round
        };

        var x0 = Margin;
        var totalW = kolom.Sum(k => k.Width);

        // ---- header tabel (diulang tiap halaman); judul berisi '\n' -> 2 baris
        var headRect = new SKRect(x0, y, x0 + totalW, y + HeadRowH);
        canvas.DrawRect(headRect, headBg);
        canvas.DrawRect(headRect, border);

        var x = x0;
        foreach (var k in kolom)
        {
            canvas.DrawLine(x, y, x, y + HeadRowH, border);

            var lines = k.Judul.ToUpper(Id).Split('\n');
            var by = BaselineTengah(y, HeadRowH, FontHead) - (lines.Length - 1) * HeadLineH / 2f;
            foreach (var judul in lines)
            {
                var tx = k.Center ? x + (k.Width - th.Measure(judul)) / 2f
                       : k.Right ? x + k.Width - 4f - th.Measure(judul)
                       : x + 4f;
                Draw(canvas, judul, tx, by, th);
                by += HeadLineH;
            }

            x += k.Width;
        }

        y += HeadRowH;

        // ---- baris data
        for (var i = 0; i < count; i++)
        {
            var idx = from + i;
            var r = baris[idx];
            var h = tinggiBaris[idx];
            var belumBox = r.BoxNo is null;
            var baseline = BaselineTengah(y, h, FontIsi);

            canvas.DrawRect(new SKRect(x0, y, x0 + totalW, y + h), border);

            x = x0;
            foreach (var k in kolom)
            {
                canvas.DrawLine(x, y, x, y + h, border);

                if (k.Isi == Isi.Nama)
                {
                    // nama sudah dibungkus (maks. 2 baris) saat perencanaan halaman
                    var t = belumBox ? dim : td;
                    var nama = namaBaris[idx];
                    var ny = baseline - (nama.Count - 1) * NamaLineH / 2f;
                    foreach (var n in nama)
                    {
                        Draw(canvas, n, x + 4f, ny, t);
                        ny += NamaLineH;
                    }
                }
                else if (k.Isi == Isi.HadirUkur)
                {
                    if (r.HadirUkur) DrawCentang(canvas, x + k.Width / 2f, y + h / 2f, centang);
                }
                else
                {
                    var (teks, t) = Nilai(k.Isi, r, idx + 1, belumBox,
                                          td, tdMono, tdMonoBold, tdNo, dim, dimMono);

                    if (!string.IsNullOrEmpty(teks))
                    {
                        var c = Clip(teks, t, k.Width - 7f);
                        var tx = k.Center ? x + (k.Width - t.Measure(c)) / 2f
                               : k.Right ? x + k.Width - 4f - t.Measure(c)
                               : x + 4f;
                        Draw(canvas, c, tx, baseline, t);
                    }
                }

                x += k.Width;
            }

            y += h;
        }

        return y;
    }

    // Tanda centang digambar sebagai garis (font Arial tidak punya glyph ✓).
    private static void DrawCentang(SKCanvas canvas, float cx, float cy, SKPaint paint)
    {
        using var path = new SKPath();
        path.MoveTo(cx - 3.2f, cy + 0.2f);
        path.LineTo(cx - 1f, cy + 2.6f);
        path.LineTo(cx + 3.4f, cy - 2.8f);
        canvas.DrawPath(path, paint);
    }

    // No. Box monospace tebal; kode pola monospace.
    // Baris belum masuk box: monospace tidak tebal, box "—".
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
            Isi.Satuan => (r.SatuanName, biasa),
            Isi.Pangkat => (r.Pangkat ?? string.Empty, biasa),
            Isi.Nrp => (r.Nrp, biasa),
            Isi.NoHp => (r.NoHp ?? string.Empty, biasa),
            Isi.Gender => (r.Gender == "PRIA" ? "Pria" : "Wanita", biasa),
            Isi.Kemeja => (r.PolaKemejaKode, mono),
            Isi.Celana => (r.PolaCelanaKode, mono),
            Isi.BoxNo => (belumBox ? "—" : $"#{r.BoxNo}", monoBold),
            _ => (string.Empty, biasa)
        };
    }

    // ---------------- blok bawah: rekap box ----------------
    // Kotak tanda tangan (Diserahkan / Diterima oleh) dihapus atas permintaan
    // owner (2026-11-09). Kolom Status & Ditutup/dikirim dihapus (2026-11-18):
    // rekap cukup Box + Isi, selebar separuh halaman.

    private static float DrawBawah(
        SKCanvas canvas, List<TniLaporanPersonelBoxDto> box, Halaman r, float y,
        int hadirUkur, int tidakHadirUkur)
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

        // kanan: rekap pengukuran (hanya bersama potongan rekap box pertama)
        if (r.RekapFrom == 0)
            DrawRekapUkur(canvas, Margin + w + gap, y, w, hadirUkur, tidakHadirUkur,
                          label, th, td, border, headBg);

        var x1 = Margin;
        canvas.DrawRect(new SKRect(x1, y, x1 + w, y + tinggi), border);

        var judul = r.RekapFrom == 0 ? "REKAP BOX" : "REKAP BOX (LANJUTAN)";
        Draw(canvas, judul, x1 + 8f, y + 12f, label);

        var ix = x1 + 8f;
        var iw = w - 16f;
        // No. Box & Kode Box dipisah (2026-11-18); box gabungan diberi keterangan.
        var cols = new[]
        {
            ("No. Box", iw * 0.20f, false),
            ("Kode Box", iw * 0.46f, false),
            ("Isi", iw * 0.34f, true)
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

            var nilai = new (string Teks, Txt Font)[]
            {
                ($"#{b.BoxNo}", tdMono),
                (b.BoxCode, tdMono),
                (b.Gabungan || b.IsiDariLingkup != b.Isi
                    ? $"{b.IsiDariLingkup.ToString("N0", Id)} dari lingkup ini"
                    : b.Isi.ToString("N0", Id), td)
            };

            var baseY = ty + RekapRowH - 3.8f;
            cx = ix;
            for (var c = 0; c < cols.Length; c++)
            {
                var (_, cw, kanan) = cols[c];
                var teks = Clip(nilai[c].Teks, nilai[c].Font, cw - 7f);
                Draw(canvas, teks,
                     kanan ? cx + cw - 4f - nilai[c].Font.Measure(teks) : cx + 4f,
                     baseY, nilai[c].Font);

                // keterangan "(gabungan)" di belakang kode box, huruf biasa abu-abu
                if (c == 1 && b.Gabungan)
                {
                    var kx = cx + 4f + nilai[c].Font.Measure(teks) + 3f;
                    Draw(canvas, Clip("(gabungan)", kecil, cx + cw - 3f - kx), kx, baseY, kecil);
                }

                cx += cw;
            }

            ty += RekapRowH;
        }

        return y + TinggiBawah(r.RekapFrom, r.RekapCount);
    }

    // Rekap pengukuran (2026-11-18): jumlah personel lingkup laporan yang hadir
    // pengukuran badan (kategori UKUR) vs tidak (TU_SIZING).
    private static void DrawRekapUkur(
        SKCanvas canvas, float x1, float y, float w, int hadir, int tidak,
        Txt label, Txt th, Txt td, SKPaint border, SKPaint headBg)
    {
        using var tdBold = new Txt(8f, bold: true);

        canvas.DrawRect(new SKRect(x1, y, x1 + w, y + TinggiUkur), border);
        Draw(canvas, "REKAP PENGUKURAN", x1 + 8f, y + 12f, label);

        var ix = x1 + 8f;
        var iw = w - 16f;
        var ty = y + RekapJudulH;

        canvas.DrawRect(new SKRect(ix, ty, ix + iw, ty + RekapHeadH), headBg);
        canvas.DrawRect(new SKRect(ix, ty, ix + iw, ty + RekapHeadH), border);
        Draw(canvas, "KETERANGAN", ix + 4f, ty + 9.6f, th);
        const string jml = "JUMLAH";
        Draw(canvas, jml, ix + iw - 4f - th.Measure(jml), ty + 9.6f, th);
        ty += RekapHeadH;

        var baris = new (string Ket, int N, bool Tebal)[]
        {
            ("Hadir pengukuran", hadir, false),
            ("Tidak hadir pengukuran", tidak, false),
            ("Total", hadir + tidak, true)
        };

        foreach (var (ket, n, tebal) in baris)
        {
            canvas.DrawRect(new SKRect(ix, ty, ix + iw, ty + RekapRowH), border);
            var t = tebal ? tdBold : td;
            var baseY = ty + RekapRowH - 3.8f;
            Draw(canvas, ket, ix + 4f, baseY, t);
            var s = $"{n.ToString("N0", Id)} orang";
            Draw(canvas, s, ix + iw - 4f - t.Measure(s), baseY, t);
            ty += RekapRowH;
        }
    }

    // Catatan kaki di bawah rekap dihapus atas permintaan owner (2026-11-18).

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

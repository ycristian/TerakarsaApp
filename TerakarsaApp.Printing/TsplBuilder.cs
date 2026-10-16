using System.Text;
using System.Text.Json;
using QRCoder;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.Printing;

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

    private const int RightColX = 190;
    private const int RightEdge = 445;

    public static BundleLabelPayload ParseBundleLabelPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<BundleLabelPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload BUNDLE_LABEL kosong atau tidak valid.");
    }

    public static PackLabelPayload ParsePackLabelPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<PackLabelPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload PACK_LABEL kosong atau tidak valid.");
    }

    public static RejectNotePayload ParseRejectNotePayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<RejectNotePayload>(payloadJson)
            ?? throw new InvalidDataException("Payload REJECT_NOTE kosong atau tidak valid.");
    }

    public static ThreadLabelPayload ParseThreadLabelPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<ThreadLabelPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload label benang kosong atau tidak valid.");
    }

    // Prompt 73: label benang 30 x 20 mm (kanvas 240 x 160 dot @ 8 dot/mm) untuk
    // paper tube bawah kones. Dipakai dua job type:
    //   THREAD_SKU_LABEL   -> QR `TB:<sku_code>`, baris 4 = KECIL/BESAR
    //   THREAD_SPLIT_LABEL -> QR `TS:<cone_code>`, baris 4 = cone_code, baris 5 = berat
    //
    // PENYIMPANGAN SENGAJA dari teks prompt: prompt menyebut command QRCODE bawaan
    // printer, tapi label lain di file ini sudah meninggalkan command itu karena
    // firmware TSC TTP-244 Pro di lapangan salah merendernya (lihat komentar panjang
    // di BuildBundleLabel). QR di sini dirender sendiri lewat QRCoder jadi BITMAP,
    // sama seperti BUNDLE_LABEL/PACK_LABEL -- label benang WAJIB bisa discan karena
    // seluruh alur ambil/kembali bergantung padanya.
    //
    // BuildBundleLabel / BuildPackLabel / BuildRejectNote TIDAK disentuh.
    public static byte[] BuildThreadLabel(ThreadLabelPayload data)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }

        Write("SIZE 30 mm, 20 mm\r\n");
        Write("GAP 2 mm, 0\r\n");
        Write("DIRECTION 1\r\n");
        Write("CLS\r\n");

        const int qrX = 8;
        const int qrY = 26;
        const int qrMaxHeightDots = 112;        // 14 mm, batas dari prompt
        const int qrQuietModules = 1;

        var qrGenerator = new QRCodeGenerator();
        var qrCodeData = qrGenerator.CreateQrCode(Sanitize(data.Qr), QRCodeGenerator.ECCLevel.M);
        var modules = ToModuleArray(qrCodeData.ModuleMatrix, qrQuietModules);

        // Cell 4 untuk isi pendek; turun ke 3 kalau QR-nya jadi lebih tinggi dari 14 mm
        // (sku_code panjang / bersuffix -2 menaikkan versi QR).
        var moduleCount = modules.GetLength(0);
        var qrCell = moduleCount * 4 <= qrMaxHeightDots ? 4 : 3;

        var qrBitmap = BuildQrBitmap(modules, qrCell, out var qrWidthDots, out var qrHeightDots, out var qrWidthBytes);

        Write($"BITMAP {qrX},{qrY},{qrWidthBytes},{qrHeightDots},0,");
        stream.Write(qrBitmap, 0, qrBitmap.Length);
        Write("\r\n");

        // Kolom teks mulai tepat setelah QR. Prompt menyebut x = 125, tapi QR isi
        // `TB:...`/`TS:...` ternyata hanya 92 dot (23 modul x cell 4) sehingga x = 108
        // memberi satu karakter font "2" lebih banyak untuk nama warna -- 30 mm sempit.
        var textX = qrX + qrWidthDots + 8;
        const int rightEdge = 234;
        var textWidth = rightEdge - textX;

        // Baris 1: kode warna, elemen terbesar -- yang dicari mata saat memilih kones.
        var colorCode = TruncateToFit(Sanitize(data.ColorCode).ToUpperInvariant(), 12, "3", 1, textWidth);
        Write(Text(textX, 14, "3", 1, 1, colorCode));

        // Baris 2: nama warna. Turun ke font "1" kalau tidak muat di font "2" --
        // lebih baik kecil tapi lengkap daripada "MERAH ..." (nama warna dipakai
        // admin gudang untuk mencocokkan kones di rak).
        var colorNameRaw = Sanitize(data.ColorName).ToUpperInvariant();
        var colorNameFont = colorNameRaw.Length * CharWidth("2", 1) <= textWidth ? "2" : "1";
        var colorName = TruncateToFit(colorNameRaw, 24, colorNameFont, 1, textWidth);
        Write(Text(textX, 44, colorNameFont, 1, 1, colorName));

        // Baris 3: merk + jenis benang (font kecil supaya muat di 30 mm).
        var brandType = TruncateToFit(Join(" ", data.Brand, data.ThreadType).ToUpperInvariant(), 24, "1", 1, textWidth);
        Write(Text(textX, 70, "1", 1, 1, brandType));

        if (data.IsSplit)
        {
            // Baris 4: kode kones split (yang dipakai scan ulang).
            var coneCode = TruncateToFit(Sanitize(data.ConeCode).ToUpperInvariant(), 20, "1", 1, textWidth);
            Write(Text(textX, 88, "1", 1, 1, coneCode));

            // Baris 5: berat netto, tebal (double-strike -- TSPL tidak punya bold).
            var weightText = $"{data.WeightGram ?? 0} g";
            Write(Text(textX, 106, "2", 1, 1, weightText));
            Write(Text(textX + 1, 106, "2", 1, 1, weightText));
        }
        else
        {
            // Baris 4 label SKU: jenis kones, supaya kones kecil & besar tidak tertukar.
            var coneSize = Sanitize(data.ConeSize).ToUpperInvariant();
            Write(Text(textX, 88, "1", 1, 1, TruncateToFit(coneSize, 10, "1", 1, textWidth)));
        }

        var copies = data.Copies < 1 ? 1 : data.Copies > 50 ? 50 : data.Copies;
        Write($"PRINT 1,{copies}\r\n");
        return stream.ToArray();
    }

    public static byte[] BuildBundleLabel(BundleLabelPayload data)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }

        Write("SIZE 60 mm, 40 mm\r\n");
        Write("GAP 3 mm, 0\r\n");
        Write("DIRECTION 1\r\n");
        Write("CLS\r\n");

        // QR digenerate sendiri lewat QRCoder (Model 2 standar, sama seperti qrcodejs yang
        // dipakai untuk preview QR di halaman Bundles) lalu dicetak sebagai BITMAP mentah --
        // BUKAN command QRCODE bawaan printer. Firmware TSC TTP-244 Pro di lapangan menolak/
        // skip seluruh baris QRCODE begitu parameter Model eksplisit ditambahkan (riwayat git),
        // dan tanpa parameter itu printer selalu jatuh ke Model 1 (pola modul beda dari
        // preview layar). Generate sendiri = kontrol penuh atas Model + quiet zone, dan
        // hasilnya identik dengan yang dilihat user di layar sebelum label dicetak.
        // Quiet zone bawaan QRCoder SENGAJA dipertahankan sebagian (tidak dilepas total) dan
        // ikut digambar ke bitmap -- supaya marginnya jadi bagian dari data gambar itu
        // sendiri, bukan cuma jarak kosong lewat penempatan X/Y. Percobaan sebelumnya (margin
        // lewat X/Y saja, quiet zone dilepas total) hasilnya border atas & kiri hilang di
        // cetakan fisik -- indikasi command BITMAP printer ini tidak selalu menghormati
        // offset X/Y persis seperti command QRCODE/TEXT, jadi margin dipaksa masuk ke bitmap
        // supaya tidak tergantung itu. QRCoder selalu kasih 4 modul quiet zone; qrQuietModules
        // di bawah memangkas itu ke 2 modul (~10 dot/1,25mm per sisi) -- lebih tipis dari 4
        // modul standar ISO tapi masih dalam toleransi mayoritas scanner (feedback: border 4
        // modul kelihatan ketebalan di label fisik).
        const int qrX = 10, qrY = 108, qrCell = 5, qrQuietModules = 1;
        var qrGenerator = new QRCodeGenerator();
        var qrCodeData = qrGenerator.CreateQrCode(Sanitize(data.QrContent), QRCodeGenerator.ECCLevel.M);
        var modules = ToModuleArray(qrCodeData.ModuleMatrix, qrQuietModules);
        var qrBitmap = BuildQrBitmap(modules, qrCell, out var qrWidthDots, out var qrHeightDots, out var qrWidthBytes);

        Write($"BITMAP {qrX},{qrY},{qrWidthBytes},{qrHeightDots},0,");
        stream.Write(qrBitmap, 0, qrBitmap.Length);
        Write("\r\n");

        var qrCenterX = qrX + qrWidthDots / 2;
        var serial = Sanitize(data.Serial);
        Write(Text(CenterAlignX(qrCenterX, "1", 1, serial), qrY + qrHeightDots + 4, "1", 1, 1, serial));

        Write(Text(qrX, 20, "2", 1, 1, data.ProjectName?.ToUpperInvariant() ?? string.Empty));
        Write(Text(qrX, 50, "1", 1, 1, "#"+data.NoPo?.ToUpperInvariant() ?? string.Empty));
        Write(Text(qrX, 70, "2", 1, 1, data.ArticleName?.ToUpperInvariant() ?? string.Empty));

        if (!string.IsNullOrWhiteSpace(data.BundleRemarks))
        {
            var bundleRemarksText = TruncateToFit(Sanitize(data.BundleRemarks).ToUpperInvariant(), 30, "1", 1, RightColX - qrX);
            Write(Text(qrX, 92, "1", 1, 1, bundleRemarksText));
        }

        // Prompt 27: kode huruf bundle per project (A-Z berputar) -- "B-27" bila project
        // ybs sudah punya bundle_letter, atau cuma nomor "27" utk project lama (NULL).
        var bundleNoText = string.IsNullOrEmpty(data.BundleLetter) ? $"{data.BundleNo}" : $"{data.BundleLetter}-{data.BundleNo}";
        Write(Text(RightAlignX(RightEdge, "2", 1, bundleNoText), 26, "2", 1 , 1, bundleNoText));

        Write($"BAR {RightColX},114,{RightEdge - RightColX},3\r\n");

        var sizeName = Sanitize(data.SizeName);
        Write(Text(RightColX, 128, "3", 1, 1, sizeName));
        // size_name rata kiri, qty rata kanan (kolom kanan).
        var qtyText = $"{data.Qty} pcs";
        Write(Text(RightAlignX(RightEdge, "2", 1, qtyText + "  "), 132, "2", 1, 1, qtyText));

        Write($"BAR {RightColX},162,{RightEdge - RightColX},3\r\n");
        
        Write(Text(RightColX, 174, "2", 1, 1, data.ResourceName?.ToUpperInvariant() ?? string.Empty +" - " + data.EmployeeName?.ToUpperInvariant() ?? string.Empty));
        Write(Text(RightColX, 200, "2", 1, 1, "> " + data.EmployeeName?.ToUpperInvariant() ?? string.Empty));
        Write(Text(RightColX, 225, "1", 1, 1, data.MaterialName?.ToUpperInvariant() ?? string.Empty));
        Write(Text(RightColX, 240, "1", 1, 1, data.SizePackName?.ToUpperInvariant() ?? string.Empty));

        if (!string.IsNullOrWhiteSpace(data.Remark))
        {
            var remarkText = TruncateToFit(Sanitize(data.Remark).ToUpperInvariant(), 40, "1", 1, RightEdge - RightColX);
            // TSPL tidak punya bold bawaan -- disimulasikan dengan cetak ganda digeser 1 dot
            // horizontal (double-strike), sama ukuran font dengan baris Size Pack di atasnya.
            Write(Text(RightColX, 255, "1", 1, 1, remarkText));
            Write(Text(RightColX + 1, 255, "1", 1, 1, remarkText));
        }

        var mulaiText = data.StartedAt.ToString("dd/MM HH:mm");
        Write(Text(RightAlignX(RightEdge, "2", 1, mulaiText + "   "), 290, "2", 1, 1, mulaiText));

        Write("PRINT 1,1\r\n");
        return stream.ToArray();
    }

    public static CuttingBundleLabelPayload ParseCuttingBundleLabelPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<CuttingBundleLabelPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload CUTTING_BUNDLE_LABEL kosong atau tidak valid.");
    }

    // Prompt 79: stiker bundle CUTTING (job_type CUTTING_BUNDLE_LABEL), mockup
    // claude prompt/mockup/Stiker.dc.html. Kanvas & printer SAMA dengan BUNDLE_LABEL
    // (60 x 40 mm, 480 x 320 dot @ 8 dot/mm) -- ini VARIAN BARU, BuildBundleLabel
    // (stiker penyerahan bundle) tidak disentuh sama sekali.
    //
    // Kiri: kode bundle besar (H06-M-03), PO + artikel, Size/Qty/Set, rentang nomor pcs,
    // baris kaki "Hamparan H06 . <tanggal> . Cutting". Kanan: QR + serial kecil.
    //
    // PENYIMPANGAN SENGAJA dari mockup: teks kecil di bawah QR adalah SERIAL
    // (B26-005692), bukan kode bundle -- yang discan/diketik ulang operator saat QR
    // tidak terbaca harus sama dengan isi QR itu sendiri ({PublicBaseUrl}/b/<serial>),
    // sedangkan kode bundle sengaja tidak unik lintas artikel. Kode bundle sudah jadi
    // elemen terbesar di kolom kiri, jadi tidak ada informasi yang hilang.
    public static byte[] BuildCuttingBundleLabel(CuttingBundleLabelPayload data)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }

        Write("SIZE 60 mm, 40 mm\r\n");
        Write("GAP 3 mm, 0\r\n");
        Write("DIRECTION 1\r\n");
        Write("CLS\r\n");

        // QR dirender sendiri jadi BITMAP lewat QRCoder, alasannya persis sama dengan
        // BuildBundleLabel -- lihat komentar panjang di sana (firmware TSC TTP-244 Pro
        // salah merender command QRCODE bawaan, dan margin harus masuk ke bitmap).
        const int qrX = 312, qrY = 40, qrCell = 5, qrQuietModules = 1;
        var qrGenerator = new QRCodeGenerator();
        var qrCodeData = qrGenerator.CreateQrCode(Sanitize(data.QrContent), QRCodeGenerator.ECCLevel.M);
        var modules = ToModuleArray(qrCodeData.ModuleMatrix, qrQuietModules);
        var qrBitmap = BuildQrBitmap(modules, qrCell, out var qrWidthDots, out var qrHeightDots, out var qrWidthBytes);

        Write($"BITMAP {qrX},{qrY},{qrWidthBytes},{qrHeightDots},0,");
        stream.Write(qrBitmap, 0, qrBitmap.Length);
        Write("\r\n");

        var serial = Sanitize(data.Serial);
        var qrCenterX = qrX + qrWidthDots / 2;
        Write(Text(CenterAlignX(qrCenterX, "1", 1, serial), qrY + qrHeightDots + 6, "1", 1, 1, serial));

        // ---- kolom kiri ----
        const int leftX = 12;
        const int leftWidth = 290;   // sampai sebelum kolom QR

        // Kode bundle = elemen terbesar di label. Fontnya ADAPTIF, bukan selalu "5":
        // sejak kode hamparan membawa huruf bundle project (A-H01-M-03 = 10 karakter),
        // font 5 (32 dot/karakter) hanya memuat 9 karakter di kolom kiri dan sisanya
        // kepotong -- justru informasi yang paling dibutuhkan di lapangan. Turun ke
        // font 4 (24 dot) lalu 3 (16 dot) hanya kalau perlu, jadi kode pendek
        // (H01-M-03) tetap tercetak sebesar sebelumnya.
        var code = Sanitize(data.CuttingCode).ToUpperInvariant();
        var codeFont = new[] { "5", "4", "3" }.FirstOrDefault(f => CharWidth(f, 1) * code.Length <= leftWidth) ?? "3";
        Write(Text(leftX, 18, codeFont, 1, 1, TruncateToFit(code, 30, codeFont, 1, leftWidth)));

        // PO . artikel, dipecah maks 2 baris di batas spasi.
        var judul = Join(" . ", data.NoPo, data.ArticleName).ToUpperInvariant();
        var (judul1, judul2) = WrapTwoLines(judul, leftWidth / CharWidth("1", 1));
        Write(Text(leftX, 78, "1", 1, 1, judul1));
        if (judul2.Length > 0) Write(Text(leftX, 94, "1", 1, 1, judul2));

        Write($"BAR {leftX},114,{leftWidth},3\r\n");

        // No / Size / Qty / Set -- label kecil di atas, angkanya besar.
        // "No" = nomor bundle pendek per project (bundle_no) dengan huruf project di
        // depannya, format SAMA dengan stiker penyerahan bundle manual ("J-27") supaya
        // operator membaca nomor yang sama di kedua stiker. Project lama tanpa huruf
        // mencetak nomornya saja.
        //
        // Empat kolom memakai font 3 (16 x 24), bukan font 4 (24 x 32) seperti saat
        // hanya ada tiga kolom: "J-27" + size + qty 3 digit + set tidak muat di 290 dot
        // dengan font 4, dan kolom yang saling tumpang-tindih lebih buruk daripada
        // angka yang sedikit lebih kecil.
        var bundleNoText = string.IsNullOrWhiteSpace(data.BundleLetter)
            ? data.BundleNo.ToString()
            : $"{data.BundleLetter}-{data.BundleNo}";

        Write(Text(leftX, 122, "1", 1, 1, "NO"));
        Write(Text(leftX, 138, "3", 1, 1, TruncateToFit(bundleNoText.ToUpperInvariant(), 5, "3", 1, 80)));

        Write(Text(leftX + 84, 122, "1", 1, 1, "SIZE"));
        Write(Text(leftX + 84, 138, "3", 1, 1, TruncateToFit(Sanitize(data.SizeName).ToUpperInvariant(), 4, "3", 1, 64)));

        Write(Text(leftX + 152, 122, "1", 1, 1, "QTY"));
        Write(Text(leftX + 152, 138, "3", 1, 1, data.Qty.ToString()));

        Write(Text(leftX + 220, 122, "1", 1, 1, "SET"));
        Write(Text(leftX + 220, 138, "3", 1, 1, data.SetNo.ToString()));

        Write($"BAR {leftX},180,{leftWidth},3\r\n");

        // Rentang nomor pcs -- diisi manual dengan mesin numbering sesuai ini.
        Write(Text(leftX, 188, "1", 1, 1, "NOMOR"));
        var nomor = $"{Sanitize(data.NumberFromText)} s/d {Sanitize(data.NumberToText)}".ToUpperInvariant();
        Write(Text(leftX, 204, "2", 1, 1, TruncateToFit(nomor, 30, "2", 1, leftWidth)));

        // Baris kaki: asal bundle ini. Tanggal SENGAJA numerik (dd-MM-yyyy), bukan
        // "dd MMM yyyy": nama bulan ikut culture mesin yang menjalankan print service
        // (en-US di lapangan -> "16 Oct 2026" di label yang seluruhnya Bahasa Indonesia).
        // Label lain di file ini juga memakai format numerik.
        var kaki = $"HAMPARAN {Sanitize(data.SpreadCode).ToUpperInvariant()} . {data.SpreadDate:dd-MM-yyyy} . CUTTING";
        Write(Text(leftX, 292, "1", 1, 1, TruncateToFit(kaki, 60, "1", 1, 460)));

        Write("PRINT 1,1\r\n");
        return stream.ToArray();
    }

    // Label karung (pack) 6 x 4 cm, kanvas sama dengan BUNDLE_LABEL. Kiri: QR + serial.
    // Kanan: project_name, "KARUNG NO." + nomor besar (elemen terbesar di label), total
    // qty/jumlah artikel, tanggal cetak + badge PLAN/AKTUAL.
    public static byte[] BuildPackLabel(PackLabelPayload data)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }

        Write("SIZE 60 mm, 40 mm\r\n");
        Write("GAP 3 mm, 0\r\n");
        Write("DIRECTION 1\r\n");
        Write("CLS\r\n");

        // QR ± 23 mm (qrCell dipilih supaya moduleCount khas link /pack/{serial} mendekati
        // ukuran itu) -- lihat komentar BuildBundleLabel soal kenapa QR digenerate sendiri
        // (bitmap mentah) alih-alih command QRCODE bawaan printer.
        const int qrX = 24, qrY = 90, qrCell = 6, qrQuietModules = 2;
        var qrGenerator = new QRCodeGenerator();
        var qrCodeData = qrGenerator.CreateQrCode(Sanitize(data.QrContent), QRCodeGenerator.ECCLevel.M);
        var modules = ToModuleArray(qrCodeData.ModuleMatrix, qrQuietModules);
        var qrBitmap = BuildQrBitmap(modules, qrCell, out var qrWidthDots, out var qrHeightDots, out var qrWidthBytes);

        Write($"BITMAP {qrX},{qrY},{qrWidthBytes},{qrHeightDots},0,");
        stream.Write(qrBitmap, 0, qrBitmap.Length);
        Write("\r\n");

        var qrCenterX = qrX + qrWidthDots / 2;
        var serial = Sanitize(data.Serial);
        Write(Text(CenterAlignX(qrCenterX, "1", 1, serial), qrY + qrHeightDots + 6, "1", 1, 1, serial));

        var projectName = TruncateToFit(Sanitize(data.ProjectName)?.ToUpperInvariant() ?? string.Empty, 22, "1", 1, RightEdge - RightColX);
        Write(Text(RightAlignX(RightEdge, "1", 1, projectName), 16, "1", 1, 1, projectName));

        const string karungNoLabel = "KARUNG NO.";
        Write(Text(RightAlignX(RightEdge, "1", 1, karungNoLabel), 34, "1", 1, 1, karungNoLabel));

        var packNoText = $"{data.PackNo}";
        Write(Text(RightAlignX(RightEdge, "3", 3, packNoText), 50, "3", 3, 3, packNoText));

        Write($"BAR {RightColX},134,{RightEdge - RightColX},3\r\n");

        var qtyText = $"{data.TotalQty} pcs";
        Write(Text(RightColX, 146, "2", 2, 2, qtyText));

        var itemCountText = $"{data.ItemCount} artikel";
        Write(Text(RightColX, 182, "1", 1, 1, itemCountText));

        Write($"BAR {RightColX},204,{RightEdge - RightColX},3\r\n");

        var dateText = DateTime.Now.ToString("dd/MM");
        Write(Text(RightColX, 218, "1", 1, 1, dateText));

        var badgeText = data.IsConfirmed ? "AKTUAL" : "PLAN";
        Write(Text(RightAlignX(RightEdge, "2", 1, badgeText), 216, "2", 1, 1, badgeText));

        Write("PRINT 1,1\r\n");
        return stream.ToArray();
    }

    // Nota reject 6x4cm, kanvas sama dengan BUNDLE_LABEL/PACK_LABEL -- dicetak untuk SATU
    // baris article_workflow_logs (bukan seluruh bundle), tombol "Cetak Reject" di
    // BundleScanCard/ReportBundle Riwayat, hanya tampil di client kalau baris itu punya
    // reject > 0. Tanpa QR -- nota internal, bukan sesuatu yang perlu discan ulang.
    public static byte[] BuildRejectNote(RejectNotePayload data)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }

        Write("SIZE 60 mm, 40 mm\r\n");
        Write("GAP 3 mm, 0\r\n");
        Write("DIRECTION 1\r\n");
        Write("CLS\r\n");

        const int leftX = 14;
        const int rightEdge = 466;

        const string title = "CATATAN REJECT";
        Write(Text(CenterAlignX((leftX + rightEdge) / 2, "3", 1, title), 10, "3", 1, 1, title));
        Write($"BAR {leftX},44,{rightEdge - leftX},2\r\n");

        var bundleLine = string.IsNullOrEmpty(data.BundleSerial)
            ? Sanitize(data.ProjectName).ToUpperInvariant()
            : (string.IsNullOrEmpty(data.BundleLetter) ? $"No. {data.BundleNo}" : $"No. {data.BundleLetter}-{data.BundleNo}") + " - " + Sanitize(data.BundleSerial);
        Write(Text(leftX, 52, "2", 1, 1, TruncateToFit(bundleLine, 30, "2", 1, rightEdge - leftX)));

        var articleLine = Sanitize(data.ArticleName).ToUpperInvariant() + (string.IsNullOrEmpty(data.SizeName) ? "" : $" - {data.SizeName}");
        Write(Text(leftX, 76, "1", 1, 1, TruncateToFit(articleLine, 40, "1", 1, rightEdge - leftX)));

        var stepText = Sanitize(data.StepName).ToUpperInvariant() + (string.IsNullOrEmpty(data.DivisionName) ? "" : $" ({data.DivisionName})");
        var stepLine = TruncateToFit(stepText, 32, "2", 1, rightEdge - leftX);
        // TSPL tidak punya bold bawaan -- disimulasikan dengan cetak ganda digeser 1 dot
        // horizontal (double-strike), pola sama dengan remark di BuildBundleLabel.
        Write(Text(leftX, 96, "2", 1, 1, stepLine));
        Write(Text(leftX + 1, 96, "2", 1, 1, stepLine));

        Write($"BAR {leftX},128,{rightEdge - leftX},2\r\n");

        var y = 136;
        void RejectLine(string label, int qty)
        {
            if (qty == 0) return;
            Write(Text(leftX, y, "2", 1, 1, $"{label}: {qty}"));
            y += 22;
        }
        RejectLine("Print", data.QtyRejectPrint);
        RejectLine("Bahan", data.QtyRejectFabric);
        RejectLine("Jahit", data.QtyRejectSewing);
        RejectLine("Rework", data.QtyRejectRework);
        RejectLine("Hilang", data.QtyLost);

        var total = data.QtyRejectPrint + data.QtyRejectFabric + data.QtyRejectSewing + data.QtyRejectRework + data.QtyLost;
        var totalText = $"TOTAL: {total}";
        Write(Text(leftX, y + 2, "2", 1, 1, totalText));
        Write(Text(leftX + 1, y + 2, "2", 1, 1, totalText));
        y += 26;

        if (!string.IsNullOrWhiteSpace(data.Remark))
        {
            var remarkCap = Math.Min(40, (rightEdge - leftX) / CharWidth("1", 1));
            var (remarkLine1, remarkLine2) = WrapTwoLines(Sanitize(data.Remark), remarkCap);
            Write(Text(leftX, y, "1", 1, 1, remarkLine1));
            if (!string.IsNullOrEmpty(remarkLine2))
                Write(Text(leftX, y + 14, "1", 1, 1, remarkLine2));
        }

        Write($"BAR {leftX},290,{rightEdge - leftX},2\r\n");

        var resourceText = Sanitize(data.ResourceName ?? "-").ToUpperInvariant();
        Write(Text(leftX, 298, "1", 1, 1, resourceText));

        var dateText = data.CreatedAt.ToString("dd/MM/yyyy HH:mm");
        Write(Text(RightAlignX(rightEdge, "1", 1, dateText), 298, "1", 1, 1, dateText));

        Write("PRINT 1,1\r\n");
        return stream.ToArray();
    }

    // QRCoder selalu menyertakan quiet zone 4 modul; trimModules memangkas dari 4 itu turun
    // ke ukuran yang diinginkan (mis. 2 => 2 modul terluar dari quiet zone bawaan dibuang).
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

    // TSPL BITMAP: data biner mentah (bukan teks), 1 bit = 1 dot, MSB dulu, tiap baris
    // dibulatkan ke kelipatan byte (widthBytes). Bit 1 = dot dicetak (hitam).
    private static byte[] BuildQrBitmap(bool[,] modules, int cellDots, out int widthDots, out int heightDots, out int widthBytes)
    {
        var moduleCount = modules.GetLength(0);
        widthDots = moduleCount * cellDots;
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

    // Pecah teks jadi maks 2 baris di batas spasi terdekat (bukan potong di tengah kata);
    // baris kedua tetap dipotong dgn "..." kalau masih kepanjangan setelah dibagi 2.
    private static (string Line1, string Line2) WrapTwoLines(string value, int maxCharsPerLine)
    {
        if (value.Length <= maxCharsPerLine) return (value, "");

        var breakAt = value.LastIndexOf(' ', Math.Min(maxCharsPerLine, value.Length - 1));
        if (breakAt <= 0) breakAt = maxCharsPerLine;

        var line1 = value.Substring(0, breakAt).TrimEnd();
        var line2 = Truncate(value.Substring(breakAt).TrimStart(), maxCharsPerLine);
        return (line1, line2);
    }

    private static string Join(string separator, params string?[] parts) =>
        string.Join(separator, parts.Where(p => !string.IsNullOrWhiteSpace(p)).Select(Sanitize));

    // TSPL tidak punya mekanisme escape untuk tanda kutip di dalam argumen string;
    // data (article_name/style/color, dst.) berasal dari input pengguna di aplikasi utama,
    // jadi diamankan di sini supaya tidak merusak perintah TSPL yang dikirim ke printer.
    private static string Sanitize(string? value) =>
        (value ?? string.Empty).Replace("\"", "'").Replace("\r", " ").Replace("\n", " ");
}

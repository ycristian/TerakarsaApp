using System.Text;
using System.Text.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

// Prompt 41/42: struk thermal (ESC/POS) -- printer struk biasa, BUKAN printer label TSC
// (lihat TsplBuilder). Lebar kertas dalam karakter dari PrintWorkerOptions.KuponPaperWidthChars
// -- dipakai utk separator garis + rata kanan.
//
// STATUS Prompt 48: TIDAK LAGI DIPANGGIL dari Worker.cs. Perakitan cetakan thermal pindah ke
// SQL (token + SIS_Print_Dispatch, lihat sql/sp_Print_Render.sql + TerakarsaApp.PrintService/
// EscPosRenderer.cs) -- KUPON_BORONGAN sudah dipindah (SIS_Print_KuponBorongan), REKAP_PRODUKSI/
// REKAP_KARYAWAN BELUM (route THERMAL sudah ada tapi SIS_Print_Dispatch belum punya cabang utk
// job_type itu -- job akan gagal jelas "belum punya SP render", bukan diam-diam salah cetak).
// File ini SENGAJA dipertahankan (bukan dihapus) sebagai referensi layout PERSIS saat SP render
// utk REKAP_PRODUKSI/REKAP_KARYAWAN ditulis nanti -- pola sama seperti SIS_Print_KuponBorongan
// diterjemahkan elemen-per-elemen dari BuildKuponBorongan di bawah.
public static class EscPosBuilder
{
    private const byte ESC = 0x1B;
    private const byte GS = 0x1D;

    public static KuponBoronganPayload ParseKuponBoronganPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<KuponBoronganPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload KUPON_BORONGAN kosong atau tidak valid.");
    }

    public static RekapProduksiPayload ParseRekapProduksiPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<RekapProduksiPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload REKAP_PRODUKSI kosong atau tidak valid.");
    }

    public static byte[] BuildKuponBorongan(KuponBoronganPayload data, int paperWidthChars)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }
        void WriteBytes(params byte[] b) => stream.Write(b, 0, b.Length);
        void Line(string s = "") => Write(s + "\n");
        void Sep() => Line(new string('-', paperWidthChars));
        void Bold(string s)
        {
            WriteBytes(ESC, 0x45, 1); // ESC E 1 : bold on
            Line(Sanitize(s));
            WriteBytes(ESC, 0x45, 0); // ESC E 0 : bold off
        }
        void BoldLeftRight(string left, string right)
        {
            left = Sanitize(left);
            right = Sanitize(right);
            var pad = paperWidthChars - left.Length - right.Length;
            if (pad < 1) pad = 1;
            WriteBytes(ESC, 0x45, 1); // ESC E 1 : bold on
            Write(left);
            Write(new string(' ', pad));
            Write(right);
            WriteBytes(ESC, 0x45, 0); // ESC E 0 : bold off
            Write("\n");
        }

        WriteBytes(ESC, 0x40); // ESC @ : initialize
        WriteBytes(ESC, 0x61, 0); // ESC a 0 : left align (semua baris)

        Bold($"Coupon {data.WorkflowLogId} - {data.DivisionName ?? "-"}");
        Sep();

        var bundleNo = string.IsNullOrEmpty(data.BundleLetter) ? $"{data.BundleNo}" : $"{data.BundleLetter}-{data.BundleNo}";
        BoldLeftRight($"{data.Serial} ({bundleNo})", data.SizeName ?? "");
        Line(Sanitize(data.ProjectName));
        Line(Sanitize(data.ArticleName).Trim());
        var styleColor = string.Join(" ", new[] { data.Style, data.Color }.Where(v => !string.IsNullOrWhiteSpace(v)));
        Line(Sanitize(styleColor));
        Sep();

        var lineTailor = string.IsNullOrWhiteSpace(data.LineResourceName)
            ? Sanitize(data.TailorName ?? "-")
            : $"{Sanitize(data.LineResourceName)} - {Sanitize(data.TailorName ?? "-")}";
        Bold(lineTailor);

        Bold($"Qty OK : {data.QtyOk} pcs");
        if (data.QtyRejectPrint > 0) Line($"Reject Print : {data.QtyRejectPrint} pcs");
        if (data.QtyRejectFabric > 0) Line($"Reject Bahan : {data.QtyRejectFabric} pcs");
        if (data.QtyRejectSewing > 0) Line($"Reject Jahit : {data.QtyRejectSewing} pcs");
        if (data.QtyRejectRework > 0) Line($"Rework : {data.QtyRejectRework} pcs");
        if (data.QtyLost > 0) Line($"Hilang : {data.QtyLost} pcs");
        if (!string.IsNullOrWhiteSpace(data.BundleRemarks))
        {
            foreach (var noteLine in WrapLines($"Note : {Sanitize(data.BundleRemarks)}", paperWidthChars))
                Line(noteLine);
        }
        Sep();

        var footerAt = data.UpdatedAt ?? data.CreatedAt;
        Line(footerAt.ToString("dd/MM/yyyy HH:mm"));

        WriteBytes(ESC, 0x64, 3); // ESC d 3 : feed 3 lines sebelum potong
        WriteBytes(GS, 0x56, 1);  // GS V 1 : partial cut (printer tanpa cutter mengabaikan)

        return stream.ToArray();
    }

    // Prompt 42: layout mengikuti mockup di claude prompt/prompt_42_rekap_produksi.md -- baris
    // hari (Sabtu, 01/08) > artikel > baris item (bundle/penjahit/resource sesuai data.Level,
    // Label sudah diformat SP). Kode reject/lost (rp/rf/rs/rw/ls) hanya ditulis kalau > 0,
    // dipisah spasi per baris item, dipisah "/" di subtotal harian & TOTAL.
    public static byte[] BuildRekapProduksi(RekapProduksiPayload data, int paperWidthChars)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }
        void WriteBytes(params byte[] b) => stream.Write(b, 0, b.Length);
        void Line(string s = "") => Write(s + "\n");
        void Sep() => Line(new string('-', paperWidthChars));
        string RightAlign(string s) => s.Length >= paperWidthChars ? s : new string(' ', paperWidthChars - s.Length) + s;
        void BoldRight(string s)
        {
            WriteBytes(ESC, 0x45, 1); // ESC E 1 : bold on
            Line(RightAlign(s));
            WriteBytes(ESC, 0x45, 0); // ESC E 0 : bold off
        }
        string RejectCodes(int rp, int rf, int rs, int rw, int ls, string sep)
        {
            var parts = new List<string>();
            if (rp > 0) parts.Add($"rp:{rp}");
            if (rf > 0) parts.Add($"rf:{rf}");
            if (rs > 0) parts.Add($"rs:{rs}");
            if (rw > 0) parts.Add($"rw:{rw}");
            if (ls > 0) parts.Add($"ls:{ls}");
            return string.Join(sep, parts);
        }
        string ItemLine(string label, string? sizeName, int qty, string? suffix, int rp, int rf, int rs, int rw, int ls)
        {
            var sizeSeg = string.IsNullOrWhiteSpace(sizeName) ? "" : $"{sizeName}  ";
            var text = $"  {label}  {sizeSeg}{qty}{suffix}";
            var codes = RejectCodes(rp, rf, rs, rw, ls, " ");
            return codes.Length == 0 ? text : $"{text} {codes}";
        }

        WriteBytes(ESC, 0x40); // ESC @ : initialize
        WriteBytes(ESC, 0x61, 0); // ESC a 0 : left align (semua baris)

        Line(Sanitize($"Rekap {data.DivisionName}"));
        var subtitle = data.Level switch
        {
            "EMPLOYEE" => string.IsNullOrWhiteSpace(data.ResourceName) ? data.EmployeeName : $"{data.EmployeeName} - {data.ResourceName}",
            "RESOURCE" => data.ResourceName,
            _ => null
        };
        if (!string.IsNullOrWhiteSpace(subtitle)) Line(Sanitize(subtitle!));
        Sep();

        var days = data.Lines
            .Where(l => l.EventDate.HasValue)
            .Select(l => l.EventDate!.Value.Date)
            .Distinct()
            .OrderBy(d => d)
            .ToList();

        var totalQty = 0;
        int totalRp = 0, totalRf = 0, totalRs = 0, totalRw = 0, totalLs = 0;

        foreach (var day in days)
        {
            Line(Sanitize(FormatHari(day)));

            var dayLines = data.Lines.Where(l => l.EventDate!.Value.Date == day).ToList();
            var articles = dayLines.Select(l => l.ArticleName).Distinct();
            int dayQty = 0;
            int dRp = 0, dRf = 0, dRs = 0, dRw = 0, dLs = 0;

            foreach (var article in articles)
            {
                Line(Sanitize(article));
                foreach (var l in dayLines.Where(x => x.ArticleName == article))
                {
                    Line(ItemLine(l.Label, l.SizeName, l.Qty, "", l.QtyRejectPrint, l.QtyRejectFabric, l.QtyRejectSewing, l.QtyRejectRework, l.QtyLost));
                    dayQty += l.Qty;
                    dRp += l.QtyRejectPrint; dRf += l.QtyRejectFabric; dRs += l.QtyRejectSewing; dRw += l.QtyRejectRework; dLs += l.QtyLost;
                }
            }

            Line(RightAlign($"{dayQty} pcs"));
            var dayCodes = RejectCodes(dRp, dRf, dRs, dRw, dLs, "/");
            if (dayCodes.Length > 0) Line(RightAlign(dayCodes));

            totalQty += dayQty;
            totalRp += dRp; totalRf += dRf; totalRs += dRs; totalRw += dRw; totalLs += dLs;
        }

        Sep();
        Line(RightAlign($"TOTAL  {totalQty} pcs"));
        var totalCodes = RejectCodes(totalRp, totalRf, totalRs, totalRw, totalLs, "/");
        if (totalCodes.Length > 0) Line(RightAlign(totalCodes));
        Sep();

        Line("> WORK IN PROGRESS (WIP) <");
        var wipArticles = data.WipLines.Select(l => l.ArticleName).Distinct();
        var wipQty = 0;
        foreach (var article in wipArticles)
        {
            Line(Sanitize(article));
            foreach (var l in data.WipLines.Where(x => x.ArticleName == article))
            {
                Line(ItemLine(l.Label, l.SizeName, l.Qty, " pcs", 0, 0, 0, 0, 0));
                wipQty += l.Qty;
            }
        }
        Sep();
        BoldRight($"WIP  {wipQty} pcs");
        Line();

        Line($"Dicetak {DateTime.Now:dd/MM/yyyy HH:mm}");

        WriteBytes(ESC, 0x64, 3);
        WriteBytes(GS, 0x56, 1);

        return stream.ToArray();
    }

    public static RekapKaryawanPayload ParseRekapKaryawanPayload(string payloadJson)
    {
        return JsonSerializer.Deserialize<RekapKaryawanPayload>(payloadJson)
            ?? throw new InvalidDataException("Payload REKAP_KARYAWAN kosong atau tidak valid.");
    }

    // Fix: "Cetak Karyawan" -- checkbox "Print Karyawan" pada kartu Rekap Produksi
    // /activity-log, tombol terpisah dari "Cetak Struk" (BuildRekapProduksi di atas, tidak
    // diubah). Baris Selesai (done_rows) dan WIP (wip_rows) sudah flat dari SP (SIS_Report_
    // RekapKaryawanPrint), dikelompokkan Line > Karyawan > PO (> Bundle utk Selesai) di sini
    // pakai LINQ GroupBy berurutan, sama pola dengan BuildRekapProduksi (grouping hari > artikel
    // dilakukan di builder, bukan SP).
    public static byte[] BuildRekapKaryawan(RekapKaryawanPayload data, int paperWidthChars)
    {
        using var stream = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            stream.Write(bytes, 0, bytes.Length);
        }
        void WriteBytes(params byte[] b) => stream.Write(b, 0, b.Length);
        void Line(string s = "") => Write(s + "\n");
        void Sep() => Line(new string('-', paperWidthChars));
        string RightAlign(string s) => s.Length >= paperWidthChars ? s : new string(' ', paperWidthChars - s.Length) + s;
        void BoldRight(string s)
        {
            WriteBytes(ESC, 0x45, 1); // ESC E 1 : bold on
            Line(RightAlign(s));
            WriteBytes(ESC, 0x45, 0); // ESC E 0 : bold off
        }
        string RejectCodes(int rp, int rf, int rs, int rw, int ls)
        {
            var parts = new List<string>();
            if (rp > 0) parts.Add($"rp:{rp}");
            if (rf > 0) parts.Add($"rf:{rf}");
            if (rs > 0) parts.Add($"rs:{rs}");
            if (rw > 0) parts.Add($"rw:{rw}");
            if (ls > 0) parts.Add($"ls:{ls}");
            return string.Join(" ", parts);
        }
        // "Book" N karakter -- minimal N, pad spasi kalau lebih pendek, TIDAK dipotong kalau
        // lebih panjang (lihat prompt: NoBundle minimal 6, Size minimal 5).
        string PadMin(string s, int minWidth) => s.Length >= minWidth ? s : s + new string(' ', minWidth - s.Length);
        // Qty OK dicetak BOLD, reject (kalau ada) NORMAL di baris yang sama -- toggle ESC E
        // di tengah baris, bukan seluruh baris.
        void BundleLine(string bundleLabel, string? sizeName, int qtyOk, int rp, int rf, int rs, int rw, int ls)
        {
            var left = $"  {PadMin(bundleLabel, 6)} {PadMin(sizeName ?? "-", 5)} ";
            var codes = RejectCodes(rp, rf, rs, rw, ls);
            Write(left);
            WriteBytes(ESC, 0x45, 1); // ESC E 1 : bold on
            Write(qtyOk.ToString());
            WriteBytes(ESC, 0x45, 0); // ESC E 0 : bold off
            Line(codes.Length == 0 ? "" : $" {codes}");
        }

        WriteBytes(ESC, 0x40); // ESC @ : initialize
        WriteBytes(ESC, 0x61, 0); // ESC a 0 : left align (semua baris)

        Line(Sanitize($"Rekap Karyawan {data.DivisionName}"));
        var subtitle = string.Join(" - ", new[] { data.ResourceName, data.EmployeeName }.Where(v => !string.IsNullOrWhiteSpace(v)));
        if (subtitle.Length > 0) Line(Sanitize(subtitle));
        Line(Sanitize($"Tanggal {data.Date:dd/MM/yyyy}"));
        Sep();

        var totalQty = 0;
        int totalRp = 0, totalRf = 0, totalRs = 0, totalRw = 0, totalLs = 0;

        foreach (var lineGroup in data.DoneRows.GroupBy(r => r.LineResourceName).OrderBy(g => g.Key))
        {
            Line(Sanitize(lineGroup.Key));
            foreach (var empGroup in lineGroup.GroupBy(r => r.EmployeeName).OrderBy(g => g.Key))
            {
                Line(Sanitize($" - {empGroup.Key}"));
                foreach (var poGroup in empGroup.GroupBy(r => r.ProjectName).OrderBy(g => g.Key))
                {
                    Line(Sanitize($"   {poGroup.Key}"));
                    foreach (var row in poGroup)
                    {
                        BundleLine(row.BundleLabel, row.SizeName, row.QtyOk, row.QtyRejectPrint, row.QtyRejectFabric, row.QtyRejectSewing, row.QtyRejectRework, row.QtyLost);
                        totalQty += row.QtyOk;
                        totalRp += row.QtyRejectPrint; totalRf += row.QtyRejectFabric; totalRs += row.QtyRejectSewing;
                        totalRw += row.QtyRejectRework; totalLs += row.QtyLost;
                    }
                }
            }
        }

        Sep();
        BoldRight($"TOTAL  {totalQty} pcs");
        var totalCodes = RejectCodes(totalRp, totalRf, totalRs, totalRw, totalLs);
        if (totalCodes.Length > 0) Line(RightAlign(totalCodes));
        Sep();

        Line("> WORK IN PROGRESS (WIP) <");
        var wipQty = 0;
        foreach (var lineGroup in data.WipRows.GroupBy(r => r.LineResourceName).OrderBy(g => g.Key))
        {
            Line(Sanitize(lineGroup.Key));
            foreach (var empGroup in lineGroup.GroupBy(r => r.EmployeeName).OrderBy(g => g.Key))
            {
                Line(Sanitize($" - {empGroup.Key}"));
                foreach (var row in empGroup.OrderBy(r => r.ProjectName))
                {
                    Line(Sanitize($"   {row.ProjectName}  {row.QtyWip} pcs"));
                    wipQty += row.QtyWip;
                }
            }
        }
        Sep();
        BoldRight($"WIP  {wipQty} pcs");
        Line();

        Line($"Dicetak {DateTime.Now:dd/MM/yyyy HH:mm}");

        WriteBytes(ESC, 0x64, 3);
        WriteBytes(GS, 0x56, 1);

        return stream.ToArray();
    }

    private static string FormatHari(DateTime date)
    {
        var hari = new[] { "Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu" };
        return $"{hari[(int)date.DayOfWeek]}, {date:dd/MM}";
    }

    // ESC/POS memakai encoding ASCII (lihat Write di atas) -- pola sama dengan TsplBuilder.
    private static string Sanitize(string? value) =>
        (value ?? string.Empty).Replace("\r", " ").Replace("\n", " ");

    // Word-wrap ke banyak baris (bukan cuma 2 seperti TsplBuilder.WrapTwoLines) -- dipakai utk
    // Note bundle_remarks yang panjangnya bebas (varchar 500). Pecah di spasi terakhir sebelum
    // width; kata tunggal yang lebih panjang dari width dipotong paksa.
    private static IEnumerable<string> WrapLines(string text, int width)
    {
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
}

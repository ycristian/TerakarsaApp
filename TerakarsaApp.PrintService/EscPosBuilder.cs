using System.Text;
using System.Text.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

// Prompt 41/42: struk thermal 58 mm (ESC/POS) -- printer struk biasa, BUKAN printer label TSC
// (lihat TsplBuilder). Dua job_type: KUPON_BORONGAN (per bundle, Prompt 41, TIDAK diubah) dan
// REKAP_PRODUKSI (ringkasan mingguan per periode gajian, Prompt 42 -- menggantikan REKAP_PENJAHIT
// harian Prompt 41). Lebar kertas dalam karakter (default 32, 58 mm) dari
// PrintWorkerOptions.KuponPaperWidthChars -- dipakai utk separator garis + rata kanan.
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

        WriteBytes(ESC, 0x40); // ESC @ : initialize
        WriteBytes(ESC, 0x61, 0); // ESC a 0 : left align (semua baris)

        Bold($"Coupon {data.WorkflowLogId} - {data.DivisionName ?? "-"}");
        Sep();

        var bundleNo = string.IsNullOrEmpty(data.BundleLetter) ? $"{data.BundleNo}" : $"{data.BundleLetter}-{data.BundleNo}";
        Bold($"{data.Serial} ({bundleNo})");
        Line(Sanitize(data.ProjectName));
        var articleLine = string.Join(" ", new[] { data.ArticleName, data.Style, data.Color }.Where(v => !string.IsNullOrWhiteSpace(v)));
        Line(Sanitize(articleLine));
        Line($"Size : {Sanitize(data.SizeName)}");
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
        void Bold(string s)
        {
            WriteBytes(ESC, 0x45, 1);
            Line(Sanitize(s));
            WriteBytes(ESC, 0x45, 0);
        }
        void BoldRight(string s)
        {
            WriteBytes(ESC, 0x45, 1);
            Line(RightAlign(Sanitize(s)));
            WriteBytes(ESC, 0x45, 0);
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

        Bold($"Rekap {data.DivisionName}");
        var subtitle = data.Level switch
        {
            "EMPLOYEE" => string.IsNullOrWhiteSpace(data.ResourceName) ? data.EmployeeName : $"{data.EmployeeName} - {data.ResourceName}",
            "RESOURCE" => data.ResourceName,
            _ => null
        };
        if (!string.IsNullOrWhiteSpace(subtitle)) Bold(subtitle!);
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
            Bold(FormatHari(day));

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

            BoldRight($"{dayQty} pcs");
            var dayCodes = RejectCodes(dRp, dRf, dRs, dRw, dLs, "/");
            if (dayCodes.Length > 0) BoldRight(dayCodes);

            totalQty += dayQty;
            totalRp += dRp; totalRf += dRf; totalRs += dRs; totalRw += dRw; totalLs += dLs;
        }

        Sep();
        WriteBytes(GS, 0x21, 0x11); // double height + width
        Line(RightAlign($"TOTAL  {totalQty} pcs"));
        WriteBytes(GS, 0x21, 0x00);
        var totalCodes = RejectCodes(totalRp, totalRf, totalRs, totalRw, totalLs, "/");
        if (totalCodes.Length > 0) BoldRight(totalCodes);
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

    private static string FormatHari(DateTime date)
    {
        var hari = new[] { "Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu" };
        return $"{hari[(int)date.DayOfWeek]}, {date:dd/MM}";
    }

    // ESC/POS memakai encoding ASCII (lihat Write di atas) -- pola sama dengan TsplBuilder.
    private static string Sanitize(string? value) =>
        (value ?? string.Empty).Replace("\r", " ").Replace("\n", " ");
}

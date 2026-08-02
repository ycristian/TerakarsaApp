namespace TerakarsaApp.PrintService;

public class PrintWorkerOptions
{
    public string ApiBaseUrl { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
    public string PrinterName { get; set; } = string.Empty;
    public int PollSeconds { get; set; } = 5;
    public int BatchSize { get; set; } = 5;
    public bool DryRun { get; set; } = false;

    // Saklar on/off per printer fisik -- independen dari DryRun (global) dan dari satu sama
    // lain, supaya mis. printer struk bisa dites hidup sementara printer label TSC belum
    // terpasang. false = job job_type printer itu diperlakukan seperti DryRun (ditulis ke
    // ./dryrun, tidak dikirim ke printer, job tetap dilaporkan sukses) -- BUKAN dibiarkan
    // menumpuk PENDING.
    public bool PrinterLabelOn { get; set; } = true;   // BUNDLE_LABEL/PACK_LABEL/REJECT_NOTE (TSC, TSPL)
    public bool PrinterThermalOn { get; set; } = true; // KUPON_BORONGAN/REKAP_PRODUKSI (struk, ESC/POS)

    // Prompt 41: printer struk thermal 58 mm (ESC/POS) terpisah dari PrinterName (TSPL label) --
    // dipakai job_type KUPON_BORONGAN/REKAP_PRODUKSI (Prompt 42). Kosong -> job report error, tidak dicoba cetak.
    public string KuponPrinterName { get; set; } = string.Empty;
    public int KuponPaperWidthChars { get; set; } = 32;
}

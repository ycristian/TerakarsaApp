namespace TerakarsaApp.PrintService;

public class PrintWorkerOptions
{
    public string ApiBaseUrl { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
    public int PollSeconds { get; set; } = 5;
    public int BatchSize { get; set; } = 5;
    public bool DryRun { get; set; } = false;

    // Saklar on/off per printer fisik -- independen dari DryRun (global) dan dari satu sama
    // lain, supaya mis. printer struk bisa dites hidup sementara printer label TSC belum
    // terpasang. false = job_type printer itu TIDAK PERNAH diklaim dari API/DB (lihat
    // SIS_PrintJob_Claim @JobTypesCsv) -- job tetap PENDING murni sampai saklar dinyalakan,
    // tidak ditulis dryrun maupun dilaporkan sukses/gagal.
    public bool PrinterLabelOn { get; set; } = true;   // BUNDLE_LABEL/PACK_LABEL/REJECT_NOTE (TSC, TSPL)
    public bool PrinterThermalOn { get; set; } = true; // KUPON_BORONGAN/REKAP_PRODUKSI/REKAP_KARYAWAN (struk, ESC/POS)

    // Prompt 48: nama printer & lebar kertas TIDAK LAGI di sini -- diresolusi lewat tabel
    // print_devices SAAT job diklaim (job.PrinterName/CharsPerLine/CharsPerLineSmall di
    // PrintJobClaimedDto). Ganti printer/lebar kertas cukup lewat SQL (print_devices),
    // tidak perlu ubah appsettings + restart service.

    // Kupon borongan dicetak rangkap (mis. 1 utk penjahit, 1 utk arsip) tiap kali job
    // KUPON_BORONGAN diproses. Job TOKEN lain TIDAK ikut rangkap -- itu ringkasan/laporan,
    // bukan struk per-transaksi.
    public int KuponBoronganCopies { get; set; } = 2;
}

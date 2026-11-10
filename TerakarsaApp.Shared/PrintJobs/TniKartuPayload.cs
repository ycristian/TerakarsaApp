namespace TerakarsaApp.Shared.PrintJobs;

// Prompt 65: payload job cetak kartu personel PDH TNI AD (job_type TNI_KARTU).
// Dirakit di SQL oleh tni.SIS_Personel_Cetak dengan FOR JSON PATH, dibaca
// TerakarsaApp.PrintService (TniKartuEscPosBuilder). Nama properti harus sama
// dengan alias kolom di SP itu.
public class TniKartuPayload
{
    public string KodeRef { get; set; } = string.Empty;        // 'DTJ-118'
    public string JudulOrder { get; set; } = string.Empty;     // 'PDH OPMAT 2026 - KODAM III/SILIWANGI'
    public string? SatuanName { get; set; }
    public string? AreaName { get; set; }

    public string? Pangkat { get; set; }
    public string? Nama { get; set; }
    public string? Nrp { get; set; }
    public string? NoHp { get; set; }
    public int? TinggiBadan { get; set; }
    public int? BeratBadan { get; set; }

    public string? PolaKemeja { get; set; }                    // 'LD_96_P'
    public string? PolaCelana { get; set; }                    // '34_P'

    // UKUR = hadir pengukuran; TU_SIZING = tidak hadir, blok ukuran badan
    // diganti dua baris "TIDAK HADIR PENGUKURAN".
    public string? Kategori { get; set; }

    public List<TniKartuUkuran> UkuranKemeja { get; set; } = new();   // 8 baris
    public List<TniKartuUkuran> UkuranCelana { get; set; } = new();   // 7 baris

    // Isi QR: '<Tni:QrBaseUrl>/t/<qr_token>' -- BUKAN kode_ref (kode_ref berurutan
    // sehingga mudah ditebak, padahal halaman QR bisa dibuka dari internet).
    public string QrContent { get; set; } = string.Empty;

    public bool TidakHadirUkur =>
        string.Equals(Kategori, "TU_SIZING", StringComparison.OrdinalIgnoreCase);
}

public class TniKartuUkuran
{
    public string Label { get; set; } = string.Empty;
    public decimal? Nilai { get; set; }
}

// 2026-11-09: struk REKAP SIZE yang tercetak sebelum kartu-kartu satu kali cetak.
// job_type tetap TNI_KARTU (printer sama); dibedakan dari kartu lewat Jenis = "REKAP".
// Kartu biasa tidak punya properti jenis sama sekali.
public class TniKartuRekapPayload
{
    public const string JenisRekap = "REKAP";

    public string Jenis { get; set; } = JenisRekap;
    public string JudulOrder { get; set; } = string.Empty;
    public string? Waktu { get; set; }                         // 'dd/MM/yyyy HH:mm'
    public string? Petugas { get; set; }
    public int TotalKartu { get; set; }
    public List<TniKartuRekapItem> Celana { get; set; } = new();
    public List<TniKartuRekapItem> Kemeja { get; set; } = new();
}

public class TniKartuRekapItem
{
    public string Kode { get; set; } = string.Empty;           // kode pola, mis. '34_P'
    public int Jumlah { get; set; }
}

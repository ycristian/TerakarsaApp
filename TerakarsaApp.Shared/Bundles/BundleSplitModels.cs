namespace TerakarsaApp.Shared.Bundles;

// Prompt 82 -- bundle anak, pemecahan, dan selisih.
// Kontrak DTO untuk modal "Kirim Hasil" (model pemecahan), modal "Barang ketemu",
// dan angka Hilang/Lebih di kartu artikel stasiun.
// SP terkait: sql/sp_BundleSplit_Manage.sql, sql/sp_BundleSplit_Select.sql.

// Kategori masalah -- hardcode enum, tidak ada tabel master (lihat @Categories di
// SIS_BundleSplit_Manage). TidakLengkap HANYA ditawarkan di station Loading/Bundling.
public static class BundleRejectCategory
{
    public const string RejectBahan = "RejectBahan";
    public const string RejectJahit = "RejectJahit";
    public const string RejectPrint = "RejectPrint";
    public const string Perbaikan = "Perbaikan";
    public const string TidakLengkap = "TidakLengkap";

    public static readonly string[] All =
        { RejectBahan, RejectJahit, RejectPrint, Perbaikan, TidakLengkap };

    // Kategori yang boleh dipilih di modal Kirim Hasil. TidakLengkap hanya kalau
    // station-nya memang Loading/Bundling (part kurang dari sana).
    public static string[] ForStation(bool allowTidakLengkap) =>
        allowTidakLengkap ? All : new[] { RejectBahan, RejectJahit, RejectPrint, Perbaikan };

    // Kondisi barang ketemu: sama, minus TidakLengkap, plus OK.
    public static readonly string[] FoundConditions =
        { "OK", Perbaikan, RejectBahan, RejectJahit, RejectPrint };

    public static string Label(string? category) => category switch
    {
        RejectBahan => "Reject Bahan",
        RejectJahit => "Reject Jahit",
        RejectPrint => "Reject Print",
        Perbaikan => "Perbaikan",
        TidakLengkap => "Tidak Lengkap",
        "OK" => "OK",
        _ => category ?? "-"
    };

    // Status bundle yang lahir dari kategori ini (satu bundle satu status).
    public static string ToBundleStatus(string category) => category switch
    {
        Perbaikan => "Perbaikan",
        TidakLengkap => "TidakLengkap",
        _ => "Reject"
    };
}

// Header modal Kirim Hasil (result set 1 SIS_BundleSplit_Info).
public class BundleSplitInfoDto
{
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int SequenceNo { get; set; }
    public string BundleStatus { get; set; } = "OK";
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public int RootBundleNo { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string StepName { get; set; } = string.Empty;
    // "Masuk N pcs" -- qty bundle sebelum pemecahan pertama di step ini (bukan angka stiker).
    public int QtyMasuk { get; set; }
    public int QtyNow { get; set; }
    public int ExistingChildQty { get; set; }
    public int ExistingMissing { get; set; }
    public int MissingQty { get; set; }
    // Nomor urut anak berikutnya di root ini -- dipakai menampilkan kode anak SEBELUM Kirim.
    public int NextSequenceNo { get; set; }
    public bool IsEdit { get; set; }
    public bool IsLocked { get; set; }
    public bool NextStationDone { get; set; }
    // Nama step yang sudah menyentuh bundle ini sesudah step ini -- isi tooltip
    // "Sudah diproses {nama step}" waktu tombol Edit disabled.
    public string? BlockedByStepName { get; set; }
    // Kategori TidakLengkap hanya ditawarkan kalau step ini is_bundling = 1.
    public bool IsBundlingStep { get; set; }
    public bool CanSubmit { get; set; }
    public int? NextDivisionId { get; set; }
    public string? NextDivisionName { get; set; }
    public bool IsLastStep { get; set; }
}

// Anak yang SUDAH lahir dari pemecahan di step ini -- read-only di modal (aditif).
public class BundleSplitChildDto
{
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int SequenceNo { get; set; }
    public string DisplayCode { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? RejectCategory { get; set; }
    public string? RejectReason { get; set; }
}

public class BundleSplitInfoResult
{
    public BundleSplitInfoDto? Header { get; set; }
    public List<BundleSplitChildDto> Children { get; set; } = new();
}

// Satu baris "Masalah" di modal Kirim Hasil.
public class BundleSplitRowRequest
{
    public string Category { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public int Qty { get; set; }
}

public class BundleSplitRequest
{
    public int BundleId { get; set; }
    public int ArticleWorkflowId { get; set; }
    public int ResourceId { get; set; }
    public int QtyOk { get; set; }
    public List<BundleSplitRowRequest> Rows { get; set; } = new();
    // Prompt 40: penerima manual kalau step tujuan auto_receive = 1 dan counterpart tidak valid.
    public int? AutoReceiveResourceId { get; set; }
}

// Anak yang lahir dari submit -- dipakai client menampilkan konfirmasi "barcode yang lahir".
public class BundleSplitResultDto
{
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int SequenceNo { get; set; }
    public int Qty { get; set; }
    public string? Status { get; set; }
    public string? Category { get; set; }
    public string DisplayCode { get; set; } = string.Empty;
}

// Angka Hilang / Lebih kartu artikel stasiun.
public class BundleMissingSummaryDto
{
    public int ArticleId { get; set; }
    public int MissingQty { get; set; }
    public int OverQty { get; set; }
    // Sigma qty bundle ber-status TidakLengkap artikel ini. Tampil hanya kalau > 0.
    public int IncompleteQty { get; set; }
    // Ad hoc (2026-10-31): hilang GAYA LAMA (qty_lost sebelum tanggal migrasi) -- riwayat
    // beku yang tidak bisa ditutup lewat "Barang ketemu", jadi ditampilkan sebagai angka
    // kecil terpisah di bawah Hilang, bukan dijumlahkan ke MissingQty.
    public int LegacyMissingQty { get; set; }
}

// Dropdown Size modal "Barang ketemu" -- hanya size yang punya selisih terbuka.
public class BundleMissingSizeDto
{
    public int ArticleSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int MissingQty { get; set; }
}

// Blok "Akan dicatat ke" -- alokasi LIFO otomatis (atau kandidat untuk alokasi manual).
public class BundleMissingBundleDto
{
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string DisplayCode { get; set; } = string.Empty;
    // Ad hoc (2026-10-31): wajib untuk daftar lintas size di bawah form Barang ketemu.
    public string? SizeName { get; set; }
    public int MissingQty { get; set; }
    public DateTime LastMissingAt { get; set; }
    public string NextChildCode { get; set; } = string.Empty;
    public int AllocQty { get; set; }
    // true = baris ini menerima kelebihan di atas selisihnya sendiri (dicatat Lebih).
    public bool IsOverflow { get; set; }
    public int SortOrder { get; set; }
}

public class BundleFoundAllocationRequest
{
    public int BundleId { get; set; }
    public int Qty { get; set; }
}

public class BundleFoundRequest
{
    public int ArticleSizeId { get; set; }
    public int ResourceId { get; set; }
    public int QtyFound { get; set; }
    // OK | Perbaikan | RejectBahan | RejectJahit | RejectPrint
    public string Condition { get; set; } = "OK";
    public string? Reason { get; set; }
    // Kosong = pakai alokasi LIFO otomatis di server (is_system_choice = 1).
    public List<BundleFoundAllocationRequest> Allocations { get; set; } = new();
}

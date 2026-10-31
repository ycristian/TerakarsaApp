namespace TerakarsaApp.Shared.Payroll;

// Prompt 83: Rekap Gajian admin (module PAYROLL_REKAP, halaman /payroll-rekap).
//
// Harga di sini adalah SNAPSHOT yang dibekukan saat lock (workflow_lock_items.unit_price),
// BUKAN article_workflows.unit_price yang berlaku sekarang. Mengubah master tarif tidak
// mengubah angka di halaman ini.
//
// UnitPrice NULLABLE dan NULL itu BERARTI: "tarif belum diketahui" -- barisnya disorot dan
// memblokir finalisasi periode. 0 adalah harga yang SAH (step Bundling), jadi jangan pernah
// menukar null dengan 0 di sisi client.
//
// Lihat sql/sp_PayrollRekap_Select.sql, sql/sp_LockItem_Manage.sql,
// sql/sp_PayrollPeriod_Manage.sql (FINALIZE/UNFINALIZE).

// ---- Pemilih periode (SIS_PayrollRekap_Periods) ----
public class PayrollRekapPeriodDto
{
    public int PayrollPeriodId { get; set; }
    public string PeriodCode { get; set; } = string.Empty;
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public DateTime? FinalizedAt { get; set; }
    public bool IsFinalized { get; set; }
    public int ItemCount { get; set; }
    // Yang mengunci tombol "Finalisasi Periode".
    public int MissingPriceCount { get; set; }
}

// ---- Header periode ----
public class PayrollRekapHeaderDto
{
    public int PayrollPeriodId { get; set; }
    public string PeriodCode { get; set; } = string.Empty;
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public DateTime? FinalizedAt { get; set; }
    // true -> kolom harga jadi read-only di client (ditegakkan juga di SP).
    public bool IsFinalized { get; set; }
    public string? FinalizedByName { get; set; }
}

// ---- Satu baris rekap: bisa dari log, bisa dari output manual ----
public class PayrollRekapRowDto
{
    public int LockItemId { get; set; }
    public string Source { get; set; } = "LOG";   // 'LOG' | 'MANUAL'
    public bool IsManual { get; set; }            // badge "Manual"
    public int? DivisionId { get; set; }
    public string? DivisionName { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int? ArticleId { get; set; }
    public string? ArticleName { get; set; }
    public string? NoPo { get; set; }
    public string? StepName { get; set; }
    // Baris MANUAL: teks bebas PIC. Baris LOG: nama step.
    public string? WorkDescription { get; set; }
    public string? SizeName { get; set; }
    // Baris LOG: qty_ok + qty_reject_fabric (sama dengan rekap stasiun).
    // Baris MANUAL: qty apa adanya, BOLEH MINUS.
    public int Qty { get; set; }
    public int RejectQty { get; set; }
    public decimal? UnitPrice { get; set; }       // null = belum diisi (disorot)
    public decimal? Total { get; set; }           // null kalau UnitPrice null
    public bool IsMissingPrice { get; set; }
    public bool IsPotongan { get; set; }          // badge "Potongan" -- baris manual qty < 0
    public string? Note { get; set; }
    public int? ManualOutputId { get; set; }
    public int? WorkflowLogId { get; set; }
}

// ---- Ringkasan per resource ----
public class PayrollRekapResourceDto
{
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public string? DivisionName { get; set; }
    public int ItemCount { get; set; }
    public int MissingPriceCount { get; set; }
    public int TotalQty { get; set; }
    public decimal TotalNilai { get; set; }
}

public class PayrollRekapResultDto
{
    public PayrollRekapHeaderDto? Header { get; set; }
    public List<PayrollRekapRowDto> Rows { get; set; } = new();
    public List<PayrollRekapResourceDto> Resources { get; set; } = new();
}

// ---- Request ----

// Nilai MINUS DIPERBOLEHKAN (itu yang dipakai baris potongan). UnitPrice null =
// mengosongkan harga lagi.
public class LockItemPriceRequest
{
    public decimal? UnitPrice { get; set; }
}

// Baris yang menghalangi finalisasi -- hasil result set SIS_PayrollPeriod_Manage FINALIZE
// saat ditolak (pesan error berprefix 'HARGA_KOSONG|').
public class PayrollMissingPriceRowDto
{
    public int LockItemId { get; set; }
    public string Source { get; set; } = "LOG";
    public string? ResourceName { get; set; }
    public string? Description { get; set; }
    public int Qty { get; set; }
}

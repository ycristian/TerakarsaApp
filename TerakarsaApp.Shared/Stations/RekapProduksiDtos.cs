namespace TerakarsaApp.Shared.Stations;

// Prompt 59: tab "Rekap Produksi" di perangkat stasiun (BUKAN rekap struk Prompt 42 -- itu
// RekapStruk* di StationModels.cs, dulu tab "Settlement", kini satu blok di dasar tab ini).
// Matriks output satu resource/line untuk satu periode gajian, plus output non-PO.
// Sumber data: SIS_Station_RekapProduksi, SIS_NonPoOutput_List, SIS_NonPoOutput_Manage
// (sql/sp_Station_RekapProduksi.sql, sql/sp_NonPoOutput_*.sql).

// Satu baris FORMAT PANJANG: (step artikel x tanggal). Pivot jadi matriks dilakukan di client
// -- kolom tanggal berbeda per periode dan bisa bertambah oleh tanggal "luar periode".
public class RekapProduksiRowDto
{
    public int ArticleWorkflowId { get; set; }
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    // Mode Output = tanggal log dibuat; mode Terima = tanggal diterima.
    public DateTime Tanggal { get; set; }
    // qty_ok + qty_reject_fabric (reject bahan). Kategori reject lain tidak dihitung.
    public int Qty { get; set; }
    // article_workflows.unit_price yang BERLAKU SEKARANG -- tidak di-snapshot ke log.
    public decimal UnitPrice { get; set; }
}

// Agregat non-PO per tanggal untuk baris "Di luar PO" di matriks (mode Output saja).
public class RekapProduksiNonPoDayDto
{
    public DateTime Tanggal { get; set; }
    public int Qty { get; set; }
    public decimal Nilai { get; set; }
}

// Header kolom tanggal + identitas untuk layar dan header sheet Excel.
public class RekapProduksiPeriodDto
{
    public int PayrollPeriodId { get; set; }
    public string PeriodCode { get; set; } = string.Empty;
    public DateTime PeriodStart { get; set; }   // inklusif, Sabtu 10:00
    public DateTime PeriodEnd { get; set; }     // eksklusif, Sabtu 10:00
    public bool IsFinalized { get; set; }
    public int ResourceId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public string DivisionName { get; set; } = string.Empty;
    public string Mode { get; set; } = "OUTPUT";
}

public class RekapProduksiResultDto
{
    public List<RekapProduksiRowDto> Rows { get; set; } = new();
    // Baris log resource ini yang belum di-lock sama sekali (tanpa batas periode) -- chip
    // merah "n baris belum lock, tidak dihitung". Selalu 0 di mode Terima.
    public int UnlockedCount { get; set; }
    public List<RekapProduksiNonPoDayDto> NonPoDays { get; set; } = new();
    public RekapProduksiPeriodDto? Period { get; set; }
}

// Satu catatan non-PO (modal detail "Di luar PO").
public class NonPoOutputDto
{
    public int NonPoOutputId { get; set; }
    public DateTime OutputAt { get; set; }
    public int Qty { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal Nilai { get; set; }
    public string Remark { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}

// resourceId = operator sesi stasiun; server tetap yang memutuskan (EffectiveResourceId)
// kalau stasiun terkunci ke satu resource. Periode TIDAK dikirim -- SP menghitungnya dari
// OutputAt supaya aturan cut-off Sabtu 10:00 cuma punya satu definisi.
public class NonPoOutputSaveRequest
{
    public int ResourceId { get; set; }
    public DateTime OutputAt { get; set; }
    public int Qty { get; set; }
    public decimal UnitPrice { get; set; }
    public string Remark { get; set; } = string.Empty;
}

public class NonPoOutputDeleteRequest
{
    public int ResourceId { get; set; }
}

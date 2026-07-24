namespace TerakarsaApp.Shared.Reports;

// Prompt 13: Modul Laporan Arus Bundle -- read-only, dipakai oleh ReportBundleController
// (halaman /report-bundle, module REPORT_BUNDLE). Status: BELUM_MULAI/TRANSIT/DIKERJAKAN/
// SELESAI (lihat sp_Report_Bundle.sql untuk definisi posisi).

public class BundleWipDto
{
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? PosisiDivisionName { get; set; }
    public string? StepName { get; set; }
    public string? TailorName { get; set; }
    public DateTime? UpdatedInfo { get; set; }
}

public class ArticleProgressBundleStepDto
{
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public string DivisionName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int TotalBundle { get; set; }
    public int BundleSelesai { get; set; }
    public int BundleDiterima { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
}

public class ArticleProgressNonBundleStepDto
{
    public int ArticleId { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public string DivisionName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int QtyTarget { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
}

// Prompt 14: kelebihan (surplus) hasil step non-bundle per ukuran -- progres di
// ArticleProgressNonBundleStepDto dibatasi 100%, kelebihan ditampilkan terpisah di sini.
public class ArticleProgressSizeSurplusDto
{
    public int ArticleId { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int QtyTarget { get; set; }
    public int QtyOk { get; set; }
    public int Surplus { get; set; }
}

public class ArticleProgressResultDto
{
    public List<ArticleProgressBundleStepDto> BundleSteps { get; set; } = new();
    public List<ArticleProgressNonBundleStepDto> NonBundleSteps { get; set; } = new();
    public List<ArticleProgressSizeSurplusDto> SizeSurplus { get; set; } = new();
}

public class BundleHistoryHeaderDto
{
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string? TailorName { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? PosisiDivisionName { get; set; }
    public string? StepName { get; set; }
}

public class BundleHistoryTimelineDto
{
    public string StepName { get; set; } = string.Empty;
    public string? DivisionName { get; set; }
    public string? TargetDivisionName { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
    public string? Remark { get; set; }
    public string? PelaksanaName { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? CreatedByName { get; set; }
    public DateTime? ReceivedAt { get; set; }
    public string? ReceivedByResourceName { get; set; }
    public string? ReceivedRemark { get; set; }
}

public class BundleHistoryResultDto
{
    public BundleHistoryHeaderDto? Header { get; set; }
    public List<BundleHistoryTimelineDto> Timeline { get; set; } = new();
}

// Prompt 14: kebocoran qty per bundle per step ber-bundle (mulai step ke-2). Selisih =
// QtyMasuk - QtyKeluar -- kelebihan tampil negatif. Lihat SIS_Report_BundleVariance.
public class BundleVarianceDto
{
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public string StepName { get; set; } = string.Empty;
    public int QtyMasuk { get; set; }
    public int QtyKeluar { get; set; }
    public int Selisih { get; set; }
}

// Kartu "Laporan Progress" di halaman Edit Project -- matriks ukuran x step untuk satu
// artikel. Lihat SIS_Report_ArticleSizeProgress: Sizes = baris (+ PO), Steps = kolom,
// Cells = isi matriks (QtyOk kumulatif per step per ukuran, hanya pasangan yang punya log).
public class ArticleSizeProgressSizeDto
{
    public int SizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int PoQty { get; set; }
}

public class ArticleSizeProgressStepDto
{
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
}

public class ArticleSizeProgressCellDto
{
    public int ArticleWorkflowId { get; set; }
    public int SizeId { get; set; }
    public int QtyOk { get; set; }
}

public class ArticleSizeProgressResultDto
{
    public List<ArticleSizeProgressSizeDto> Sizes { get; set; } = new();
    public List<ArticleSizeProgressStepDto> Steps { get; set; } = new();
    public List<ArticleSizeProgressCellDto> Cells { get; set; } = new();
}

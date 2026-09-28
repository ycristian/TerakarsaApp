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
    // Prompt 32: penjahit dari master employees, diutamakan di atas TailorName (fallback lama).
    public string? EmployeeName { get; set; }
    // Fix: hasil (qty done) dan reject TOTAL di step/divisi TERAKHIR bundle ini (posisi saat
    // ini) -- diagregasi dari SEMUA baris log step itu (bisa lebih dari satu, baris susulan
    // Prompt 14b). 0/0 kalau bundle belum mulai (BELUM_MULAI, belum ada log sama sekali).
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
}

// Fix: order-by-klik-header + pagination di tab WIP -- pola sama dengan ProjectPagedRequest/
// ProjectPagedResult (lihat TerakarsaApp.Shared/Projects/ProjectModels.cs), dikonsumsi lewat
// POST api/report-bundle/wip (bukan lagi GET query string, lihat ReportBundleController).
public class BundleWipPagedRequest
{
    public int? ProjectId { get; set; }
    public int? ArticleId { get; set; }
    public int? DivisionId { get; set; }
    public string? Status { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class BundleWipPagedResult
{
    public List<BundleWipDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
    // Fix: breakdown per status atas SELURUH baris yang cocok filter (bukan cuma halaman ini)
    // -- dipakai badge ringkasan WIP, dihitung sekali lewat query yang sama dengan TotalCount
    // (SIS_Report_BundleWip @Action = 'COUNT') supaya tidak perlu round-trip terpisah.
    public int BelumMulaiCount { get; set; }
    public int TransitCount { get; set; }
    public int DikerjakanCount { get; set; }
    public int SelesaiCount { get; set; }
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
    // Prompt 32: penjahit dari master employees, diutamakan di atas TailorName (fallback lama).
    public string? EmployeeName { get; set; }
}

public class BundleHistoryTimelineDto
{
    // Prompt 36: workflow_log_id -- dipakai tombol "Edit" per baris timeline (fitur Super
    // Admin di tab Riwayat).
    public int Id { get; set; }
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

// Fix: pencarian Riwayat lewat format "{huruf}{nomor}" (mis. "D346"). bundle_letter berputar
// A-Z per project, jadi satu kombinasi bisa cocok di lebih dari satu project -- client
// menampilkan daftar ini sebagai pilihan kalau Matches.Count > 1.
public class BundleLookupMatchDto
{
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public int ProjectId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
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

// Ad hoc (2026-09-01): tab "Pengambilan" -- rekap bundle DIBUAT (bundles.created_at), sumbernya
// tabel bundles (bukan article_workflow_logs spt tab lain di modul ini). Lihat
// SIS_Report_BundlePengambilan/SIS_Report_BundlePengambilanPrint, sql/sp_Report_Bundle.sql.
public class BundlePengambilanHeaderDto
{
    public string? ProjectName { get; set; }
    public string? ArticleName { get; set; }
    public string? ResourceName { get; set; }
    public string? EmployeeName { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public int TotalBundle { get; set; }
    public int TotalQty { get; set; }
}

public class BundlePengambilanPrintRequest
{
    public int? ProjectId { get; set; }
    public int? ArticleId { get; set; }
    public int? ResourceId { get; set; }
    public int? EmployeeId { get; set; }
    public DateTime StartDateTime { get; set; }
    public DateTime EndDateTime { get; set; }
}

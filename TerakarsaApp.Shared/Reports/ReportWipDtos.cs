namespace TerakarsaApp.Shared.Reports;

// Prompt 22: Dashboard WIP per Divisi & Resource -- read-only, dipakai oleh
// ReportWipController (halaman /wip-dashboard, module REPORT_WIP). Lihat
// sql/sp_Report_DivisionWip.sql untuk definisi kelompok Dikerjakan/Belum diterima.

public class WipArticleSummaryDto
{
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public int BundleCount { get; set; }
}

public class DivisionWipWorkingDto
{
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int BundleCount { get; set; }
    public int TotalPcs { get; set; }
    public DateTime? OldestReceivedAt { get; set; }
    public List<WipArticleSummaryDto> Articles { get; set; } = new();
}

public class DivisionWipPendingDto
{
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int BundleCount { get; set; }
    public int TotalPcs { get; set; }
    public DateTime? OldestSentAt { get; set; }
    public List<WipArticleSummaryDto> Articles { get; set; } = new();
}

public class DivisionWipSummaryDto
{
    public List<DivisionWipWorkingDto> Working { get; set; } = new();
    public List<DivisionWipPendingDto> Pending { get; set; } = new();
}

public class DivisionWipBundleDto
{
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public int QtyOk { get; set; }
    public string? TailorName { get; set; }
    // Prompt 32: penjahit dari master employees, diutamakan di atas TailorName (fallback lama).
    public string? EmployeeName { get; set; }
    public string? StepName { get; set; }
    public DateTime EventAt { get; set; }
    public string? ReceivedByResourceName { get; set; }
}

public class ProjectWipProgressDto
{
    public int ProjectId { get; set; }
    public string BuyerName { get; set; } = string.Empty;
    public string ProjectName { get; set; } = string.Empty;
    public int OrderQty { get; set; }
    public int BundleQty { get; set; }
    public double ProgressPercent { get; set; }
}

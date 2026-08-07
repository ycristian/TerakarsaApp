namespace TerakarsaApp.Shared.Reports;

// Prompt 47: Modul Log Aktivitas -- read-only, listing mentah article_workflow_logs
// (dipakai oleh ReportActivityLogController, halaman /activity-log, module
// REPORT_ACTIVITY). Satu baris = satu baris log hidup, tanpa grouping/agregasi. Lihat
// sql/sp_Report_ActivityLog.sql untuk definisi filter.
public class ActivityLogRowDto
{
    public int WorkflowLogId { get; set; }
    public string LogType { get; set; } = "NORMAL";
    public DateTime CreatedAt { get; set; }
    public DateTime? ReceivedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? ProjectId { get; set; }
    public string? ProjectName { get; set; }
    public int? ArticleId { get; set; }
    public string? ArticleName { get; set; }
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string? StepName { get; set; }
    public int? SortOrder { get; set; }
    public int? BundleId { get; set; }
    public string? BundleSerial { get; set; }
    public int? BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string? SizeName { get; set; }
    public int DivisionId { get; set; }
    public string? DivisionName { get; set; }
    public int? TargetDivisionId { get; set; }
    public string? TargetDivisionName { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int? ReceivedByResourceId { get; set; }
    public string? ReceivedByResourceName { get; set; }
    public int? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? Remark { get; set; }
    public string? ReceivedRemark { get; set; }
    public string? CreatedByName { get; set; }
    public string Status { get; set; } = string.Empty;
    public bool CanNavigate { get; set; }
    // Step ber-print_kupon = 1 -- tombol "Cetak Kupon" (SIS_WorkflowLog_PrintHasil) tampil
    // di client kalau ini true, terlepas dari Status (boleh cetak ulang berkali-kali).
    public bool PrintKupon { get; set; }
}

public class ActivityLogPagedRequest
{
    public DateTime DateFrom { get; set; }
    public DateTime DateTo { get; set; }
    public string TimeBasis { get; set; } = "ANY";
    public int? DivisionId { get; set; }
    public int? ResourceId { get; set; }
    public int? EmployeeId { get; set; }
    public int? ProjectId { get; set; }
    public string? SearchTerm { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 50;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "desc";
}

public class ActivityLogPagedResult
{
    public List<ActivityLogRowDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
    public int TotalQtyOk { get; set; }
}

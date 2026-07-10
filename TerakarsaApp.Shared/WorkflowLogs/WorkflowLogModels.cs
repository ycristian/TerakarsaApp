namespace TerakarsaApp.Shared.WorkflowLogs;

public class WorkflowLogDto
{
    public int Id { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int? BundleId { get; set; }
    public string? BundleSerial { get; set; }
    public int? ArticleSizeId { get; set; }
    public string? SizeName { get; set; }
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRework { get; set; }
    public string? Remark { get; set; }
    public int? TargetDivisionId { get; set; }
    public string? TargetDivisionName { get; set; }
    public DateTime? ReceivedAt { get; set; }
    public string? ReceivedByResourceName { get; set; }
    public string? ReceivedRemark { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
}

public class WorkflowLogDeleteRequest
{
    public string DeleteReason { get; set; } = string.Empty;
}

public class ArticleSizeOptionDto
{
    public int Id { get; set; }
    public string SizeName { get; set; } = string.Empty;
}

public class StationPendingReceiveDto
{
    public int WorkflowLogId { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int QtyOk { get; set; }
    public DateTime SentAt { get; set; }
    public string FromDivisionName { get; set; } = string.Empty;
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? Serial { get; set; }
    public string? SizeName { get; set; }
}

public class StationPendingHandoverDto
{
    public int WorkflowLogId { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? Serial { get; set; }
    public int? ArticleSizeId { get; set; }
    public string? SizeName { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRework { get; set; }
    public string? Remark { get; set; }
    public string TargetDivisionName { get; set; } = string.Empty;
    public string? ResourceName { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<ArticleSizeOptionDto> Sizes { get; set; } = new();
}

public class StationLogUpdateRequest
{
    public int? ArticleSizeId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRework { get; set; }
    public string? Remark { get; set; }
}

public class StationReceiveRequest
{
    public int WorkflowLogId { get; set; }
    public int ResourceId { get; set; }
    public string? Remark { get; set; }
}

public class StationCompleteRequest
{
    public int ArticleWorkflowId { get; set; }
    public int? BundleId { get; set; }
    public int? ArticleSizeId { get; set; }
    public int ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRework { get; set; }
    public string? Remark { get; set; }
}

// Prompt 12c: input log step non-bundle (mis. Cutting) dari halaman /workflow-input,
// dicatat oleh supervisor/admin lewat login biasa (bukan lagi lewat stasiun).
public class WorkflowInputCreateRequest
{
    public int ArticleWorkflowId { get; set; }
    public int ArticleSizeId { get; set; }
    public int? ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRework { get; set; }
    public string? Remark { get; set; }
}

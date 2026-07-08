namespace TerakarsaApp.Shared.WorkflowLogs;

public class WorkflowLogDto
{
    public int Id { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int? BundleId { get; set; }
    public string? BundleSerial { get; set; }
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
    public string Status { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
}

public class WorkflowLogDeleteRequest
{
    public string DeleteReason { get; set; } = string.Empty;
}

public class StationPendingReceiveDto
{
    public int ArticleWorkflowId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int QtyOk { get; set; }
    public DateTime SentAt { get; set; }
    public string FromDivisionName { get; set; } = string.Empty;
}

public class StationActiveWorkDto
{
    public int ArticleWorkflowId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public bool IsLastStep { get; set; }
}

public class StationReceiveRequest
{
    public int ArticleWorkflowId { get; set; }
    public int ResourceId { get; set; }
    public string? Remark { get; set; }
}

public class StationCompleteRequest
{
    public int ArticleWorkflowId { get; set; }
    public int ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRework { get; set; }
    public int? TargetDivisionId { get; set; }
    public string? Remark { get; set; }
}

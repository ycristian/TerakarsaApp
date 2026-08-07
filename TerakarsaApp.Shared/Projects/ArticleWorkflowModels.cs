namespace TerakarsaApp.Shared.Projects;

public class ArticleWorkflowStepDto
{
    public int Id { get; set; }
    public int? WorkflowTemplateId { get; set; }
    public string? WorkflowTemplateName { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public bool RequiresBundle { get; set; } = true;
    public bool AutoReceive { get; set; }
    // Prompt 41: cetak kupon borongan otomatis saat baris step ini diterima -- hanya valid
    // utk RequiresBundle = true, ditolak SP kalau tidak.
    public bool PrintKupon { get; set; }
    public bool IsBundling { get; set; }
}

public class ArticleWorkflowDto
{
    public int ArticleId { get; set; }
    public int? WorkflowTemplateId { get; set; }
    public string? WorkflowTemplateName { get; set; }
    public List<ArticleWorkflowStepDto> Steps { get; set; } = new();
}

public class ArticleWorkflowStepRequest
{
    public int? Id { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public int SortOrder { get; set; }
    public bool RequiresBundle { get; set; } = true;
    public bool AutoReceive { get; set; }
    public bool PrintKupon { get; set; }
}

public class ArticleWorkflowApplyRequest
{
    public int ArticleId { get; set; }
    public int WorkflowTemplateId { get; set; }
}

public class ArticleWorkflowSaveRequest
{
    public int ArticleId { get; set; }
    public List<ArticleWorkflowStepRequest> Steps { get; set; } = new();
}

// Prompt 50: restrukturisasi workflow artikel setelah sudah ada log (sisip step / nonaktifkan
// step) -- lihat sql/sp_ArticleWorkflow_Restructure.sql.

public class RestructureInsertPreviewRequest
{
    public int ArticleId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public bool RequiresBundle { get; set; }
    public bool AutoReceive { get; set; }
    public int? AfterWorkflowId { get; set; }
    public bool Backfill { get; set; } = true;
}

public class RestructureDeactivatePreviewRequest
{
    public int ArticleId { get; set; }
    public int ArticleWorkflowId { get; set; }
}

public class RestructureAffectedUnitDto
{
    public int? BundleId { get; set; }
    public string? Serial { get; set; }
    public int? BundleNo { get; set; }
    public int? ArticleSizeId { get; set; }
    public string? SizeName { get; set; }
    public string Category { get; set; } = string.Empty; // 'B' (pending) atau 'C' (received)
    public string LastStepName { get; set; } = string.Empty;
}

public class RestructurePreviewSummaryDto
{
    public int PendingLogsToRedirect { get; set; }
    public int ReceivedLogsToRedirect { get; set; }
    public int BackfillLogsToCreate { get; set; }
    public int ForcedBackfillCount { get; set; }
    public int StepsResequenced { get; set; }
    public string? WarningMessage { get; set; }
}

public class RestructurePreviewResultDto
{
    public RestructurePreviewSummaryDto Summary { get; set; } = new();
    public List<RestructureAffectedUnitDto> AffectedUnits { get; set; } = new();
}

public class RestructureInsertStepResultDto
{
    public int NewArticleWorkflowId { get; set; }
    public int PendingLogsToRedirect { get; set; }
    public int BackfillLogsToCreate { get; set; }
    public int StepsResequenced { get; set; }
}

public class RestructureDeactivateStepResultDto
{
    public int PendingLogsToRedirect { get; set; }
    public int ReceivedLogsToRedirect { get; set; }
    public int StepsResequenced { get; set; }
}

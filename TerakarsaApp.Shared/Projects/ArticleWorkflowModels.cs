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

// Prompt 12c: step requires_bundle = 0 milik artikel, dipakai halaman /workflow-input untuk
// pilih step + prefill divisi tujuan (divisi step hidup berikutnya, sama seperti dihitung
// server-side di SIS_WorkflowLog_Manage -- di sini hanya untuk ditampilkan, bukan dikirim).
public class ArticleNonBundleStepDto
{
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public bool IsLastStep { get; set; }
    public int? NextDivisionId { get; set; }
    public string? NextDivisionName { get; set; }
}

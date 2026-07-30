namespace TerakarsaApp.Shared.WorkflowTemplates;

public class WorkflowTemplateStepDto
{
    public int Id { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public bool RequiresBundle { get; set; } = true;
    public bool AutoReceive { get; set; }
}

public class WorkflowTemplateDto
{
    public int Id { get; set; }
    public string WorkflowCode { get; set; } = string.Empty;
    public string WorkflowName { get; set; } = string.Empty;
    public int StepCount { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
    public List<WorkflowTemplateStepDto> Steps { get; set; } = new();
}

public class WorkflowTemplateStepRequest
{
    public int? Id { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public int SortOrder { get; set; }
    public bool RequiresBundle { get; set; } = true;
    public bool AutoReceive { get; set; }
}

public class WorkflowTemplateCreateRequest
{
    public string WorkflowCode { get; set; } = string.Empty;
    public string WorkflowName { get; set; } = string.Empty;
    public List<WorkflowTemplateStepRequest> Steps { get; set; } = new();
}

public class WorkflowTemplateUpdateRequest
{
    public int Id { get; set; }
    public string WorkflowCode { get; set; } = string.Empty;
    public string WorkflowName { get; set; } = string.Empty;
    public List<WorkflowTemplateStepRequest> Steps { get; set; } = new();
}

public class WorkflowTemplateCreateResult
{
    public int Id { get; set; }
}

public class WorkflowTemplatePagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class WorkflowTemplatePagedResult
{
    public List<WorkflowTemplateDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

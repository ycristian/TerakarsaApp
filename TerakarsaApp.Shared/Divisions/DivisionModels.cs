namespace TerakarsaApp.Shared.Divisions;

public class DivisionDto
{
    public int Id { get; set; }
    public string DivisionCode { get; set; } = string.Empty;
    public string DivisionName { get; set; } = string.Empty;
    public bool ShowInDashboard { get; set; } = true;
    public string DashboardMode { get; set; } = "DIVISION";
    public int DashboardSortOrder { get; set; }
    public int DefaultTargetPerPerson { get; set; }
    // Prompt 53: divisi ini boleh dikelola lewat module PPIC_EMPLOYEE.
    public bool PpicManaged { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class DivisionCreateRequest
{
    public string DivisionCode { get; set; } = string.Empty;
    public string DivisionName { get; set; } = string.Empty;
    public bool ShowInDashboard { get; set; } = true;
    public string DashboardMode { get; set; } = "DIVISION";
    public int DashboardSortOrder { get; set; }
    public int DefaultTargetPerPerson { get; set; }
    public bool PpicManaged { get; set; }
}

public class DivisionUpdateRequest
{
    public int Id { get; set; }
    public string DivisionCode { get; set; } = string.Empty;
    public string DivisionName { get; set; } = string.Empty;
    public bool ShowInDashboard { get; set; } = true;
    public string DashboardMode { get; set; } = "DIVISION";
    public int DashboardSortOrder { get; set; }
    public int DefaultTargetPerPerson { get; set; }
    public bool PpicManaged { get; set; }
}

public class DivisionPagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class DivisionPagedResult
{
    public List<DivisionDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

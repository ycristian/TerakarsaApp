namespace TerakarsaApp.Shared.Resources;

public class ResourceDto
{
    public int Id { get; set; }
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int ResourceTypeId { get; set; }
    public string ResourceTypeName { get; set; } = string.Empty;
    public string ResourceName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class ResourceCreateRequest
{
    public int DivisionId { get; set; }
    public int ResourceTypeId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
}

public class ResourceUpdateRequest
{
    public int Id { get; set; }
    public int DivisionId { get; set; }
    public int ResourceTypeId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
}

public class ResourcePagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class ResourceLookupDto
{
    public int Id { get; set; }
    public string ResourceName { get; set; } = string.Empty;
}

public class ResourcePagedResult
{
    public List<ResourceDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

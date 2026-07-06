namespace TerakarsaApp.Shared.ResourceTypes;

public class ResourceTypeDto
{
    public int Id { get; set; }
    public string ResourceTypeCode { get; set; } = string.Empty;
    public string ResourceTypeName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class ResourceTypeCreateRequest
{
    public string ResourceTypeCode { get; set; } = string.Empty;
    public string ResourceTypeName { get; set; } = string.Empty;
}

public class ResourceTypeUpdateRequest
{
    public int Id { get; set; }
    public string ResourceTypeCode { get; set; } = string.Empty;
    public string ResourceTypeName { get; set; } = string.Empty;
}

public class ResourceTypePagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class ResourceTypePagedResult
{
    public List<ResourceTypeDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

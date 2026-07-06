namespace TerakarsaApp.Shared.Positions;

public class PositionDto
{
    public int Id { get; set; }
    public string PositionName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class PositionCreateRequest
{
    public string PositionName { get; set; } = string.Empty;
}

public class PositionUpdateRequest
{
    public int Id { get; set; }
    public string PositionName { get; set; } = string.Empty;
}

public class PositionPagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class PositionPagedResult
{
    public List<PositionDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

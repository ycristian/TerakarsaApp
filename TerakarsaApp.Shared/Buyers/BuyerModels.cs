namespace TerakarsaApp.Shared.Buyers;

public class BuyerDto
{
    public int Id { get; set; }
    public string BuyerCode { get; set; } = string.Empty;
    public string BuyerName { get; set; } = string.Empty;
    public string? Address { get; set; }
    public string? Phone { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class BuyerCreateRequest
{
    public string BuyerCode { get; set; } = string.Empty;
    public string BuyerName { get; set; } = string.Empty;
    public string? Address { get; set; }
    public string? Phone { get; set; }
}

public class BuyerUpdateRequest
{
    public int Id { get; set; }
    public string BuyerCode { get; set; } = string.Empty;
    public string BuyerName { get; set; } = string.Empty;
    public string? Address { get; set; }
    public string? Phone { get; set; }
}

public class BuyerPagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class BuyerPagedResult
{
    public List<BuyerDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

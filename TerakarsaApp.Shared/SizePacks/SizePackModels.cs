namespace TerakarsaApp.Shared.SizePacks;

public class SizePackDetailDto
{
    public int Id { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? Description { get; set; }
}

public class SizePackDto
{
    public int Id { get; set; }
    public int? BuyerId { get; set; }
    public string? BuyerName { get; set; }
    public string SizePackName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
    public List<SizePackDetailDto> Details { get; set; } = new();
}

public class SizePackDetailRequest
{
    public int? Id { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? Description { get; set; }
}

public class SizePackCreateRequest
{
    public int? BuyerId { get; set; }
    public string SizePackName { get; set; } = string.Empty;
    public List<SizePackDetailRequest> Details { get; set; } = new();
}

public class SizePackUpdateRequest
{
    public int Id { get; set; }
    public int? BuyerId { get; set; }
    public string SizePackName { get; set; } = string.Empty;
    public List<SizePackDetailRequest> Details { get; set; } = new();
}

public class SizePackCreateResult
{
    public int Id { get; set; }
}

public class SizePackPagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class SizePackPagedResult
{
    public List<SizePackDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

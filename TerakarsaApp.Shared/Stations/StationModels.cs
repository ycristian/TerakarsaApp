namespace TerakarsaApp.Shared.Stations;

public class StationDto
{
    public int Id { get; set; }
    public string StationCode { get; set; } = string.Empty;
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public string TokenPreview { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class StationCreateRequest
{
    public string StationCode { get; set; } = string.Empty;
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public bool IsActive { get; set; } = true;
}

public class StationUpdateRequest
{
    public int Id { get; set; }
    public string StationCode { get; set; } = string.Empty;
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public bool IsActive { get; set; }
}

public class StationPagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class StationPagedResult
{
    public List<StationDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

// Dikembalikan sekali saja saat CREATE/REGENERATE_TOKEN — token penuh tidak pernah
// muncul lagi setelah response ini (list hanya menampilkan TokenPreview).
public class StationTokenResult
{
    public int Id { get; set; }
    public string Token { get; set; } = string.Empty;
}

// Info stasiun untuk perangkat yang sudah membawa X-Station-Token (dipakai Prompt 9b).
public class StationMeDto
{
    public int StationId { get; set; }
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
}

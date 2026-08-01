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
    public bool IncludeInDashboard { get; set; } = true;
    // Prompt 39: resource pasangan di divisi lanjutan (mis. Line A1 -> Trim A1), opsional.
    public int? CounterpartResourceId { get; set; }
    public string? CounterpartResourceName { get; set; }
    // Prompt 40: nama divisi counterpart -- dipakai list Master Resource "{Nama} ({Divisi})".
    public string? CounterpartDivisionName { get; set; }
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
    public bool IncludeInDashboard { get; set; } = true;
    public int? CounterpartResourceId { get; set; }
}

public class ResourceUpdateRequest
{
    public int Id { get; set; }
    public int DivisionId { get; set; }
    public int ResourceTypeId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public bool IncludeInDashboard { get; set; } = true;
    public int? CounterpartResourceId { get; set; }
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

// Prompt 39: dropdown "Resource Pasangan" di form Master Resource -- resource aktif di
// luar divisi yang sedang dipilih. DivisionName ditampilkan supaya admin tidak keliru
// pilih resource bernama sama di divisi lain.
public class ResourceCounterpartOptionDto
{
    public int Id { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
}

public class ResourcePagedResult
{
    public List<ResourceDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

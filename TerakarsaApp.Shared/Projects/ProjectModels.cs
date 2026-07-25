namespace TerakarsaApp.Shared.Projects;

public class ProjectDto
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public string BuyerName { get; set; } = string.Empty;
    public int? ProjectMd { get; set; }
    public string? ProjectMdName { get; set; }
    public int? ProjectPic { get; set; }
    public string? ProjectPicName { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string? MaterialName { get; set; }
    public DateTime? OrderDate { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? Deadline { get; set; }
    public DateTime? DeliveryDate { get; set; }
    public string? Remarks { get; set; }
    public bool IsUrgent { get; set; }
    public string DerivedStatus { get; set; } = string.Empty;
    public string? StatusReason { get; set; }
    public DateTime? StatusChangedAt { get; set; }
    public string? StatusChangedByName { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
    // Fix: % progress project, dihitung per size (surplus satu size tidak menutupi kekurangan
    // size lain) -- lihat komentar SIS_Project_GetAll/GetById di sql/sp_Project_Select.sql.
    public double ProgressPercent { get; set; }
}

public class ProjectCreateRequest
{
    public int CustomerId { get; set; }
    public int? ProjectMd { get; set; }
    public int? ProjectPic { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string? MaterialName { get; set; }
    public DateTime? OrderDate { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? Deadline { get; set; }
    public DateTime? DeliveryDate { get; set; }
    public string? Remarks { get; set; }
    public bool IsUrgent { get; set; }
}

public class ProjectUpdateRequest
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public int? ProjectMd { get; set; }
    public int? ProjectPic { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string? MaterialName { get; set; }
    public DateTime? OrderDate { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? Deadline { get; set; }
    public DateTime? DeliveryDate { get; set; }
    public string? Remarks { get; set; }
    public bool IsUrgent { get; set; }
}

public class ProjectCreateResult
{
    public int Id { get; set; }
}

public class ProjectPagedRequest
{
    public string? Search { get; set; }
    public string? Status { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class ProjectSetStatusRequest
{
    public int Id { get; set; }
    public string? ManualStatus { get; set; }
    public string? StatusReason { get; set; }
}

public class ProjectPagedResult
{
    public List<ProjectDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

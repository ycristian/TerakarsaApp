namespace TerakarsaApp.Shared.Positions;

public class PositionDto
{
    public int Id { get; set; }
    public string PositionName { get; set; } = string.Empty;
    // Prompt 70: jabatan ini boleh membuka menu satpam di aplikasi gate (positions.is_gate_operator).
    public bool IsGateOperator { get; set; }
    // Prompt 58 (lanjutan): divisi yang boleh memakai jabatan ini, sudah digabung jadi satu
    // teks oleh SP -- kosong berarti belum dibatasi (berlaku di semua divisi).
    public string DivisionNames { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class PositionCreateRequest
{
    public string PositionName { get; set; } = string.Empty;
    public bool IsGateOperator { get; set; }
    // NULL = jangan sentuh pemetaan divisi; daftar kosong = jabatan tidak dibatasi divisi.
    public List<int>? DivisionIds { get; set; }
}

public class PositionUpdateRequest
{
    public int Id { get; set; }
    public string PositionName { get; set; } = string.Empty;
    public bool IsGateOperator { get; set; }
    public List<int>? DivisionIds { get; set; }
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

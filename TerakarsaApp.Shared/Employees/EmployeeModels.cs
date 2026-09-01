namespace TerakarsaApp.Shared.Employees;

public class EmployeeDto
{
    public int Id { get; set; }
    // Prompt 35: boleh kosong -- penjahit yang belum punya kode tapi sudah mulai kerja bisa
    // didaftar dulu, kode diisi menyusul lewat Edit.
    public string? EmployeeCode { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int PositionId { get; set; }
    public string PositionName { get; set; } = string.Empty;
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public DateTime? JoinDate { get; set; }
    // Prompt 53: nonaktif = hilang dari dropdown employee, data lama (log/bundle/project) tetap utuh.
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class EmployeeCreateRequest
{
    public string? EmployeeCode { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public int PositionId { get; set; }
    public int? ResourceId { get; set; }
    public DateTime? JoinDate { get; set; }
}

public class EmployeeUpdateRequest
{
    public int Id { get; set; }
    public string? EmployeeCode { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public int PositionId { get; set; }
    public int? ResourceId { get; set; }
    public DateTime? JoinDate { get; set; }
}

public class EmployeePagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class EmployeePagedResult
{
    public List<EmployeeDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

// Prompt 32: lookup employee hidup untuk dropdown "Penjahit" (cascading di bawah dropdown
// Line/resource) -- pola meniru ResourceLookupDto.
public class EmployeeLookupDto
{
    public int Id { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
}

// Prompt 53: toggle Aktifkan/Nonaktifkan (Master Karyawan & Karyawan PPIC) -- tidak menyentuh
// field lain, tidak ada pengecekan referensi (nonaktifkan selalu boleh).
public class EmployeeSetActiveRequest
{
    public int Id { get; set; }
    public bool IsActive { get; set; }
}

// Prompt 53: saran kode karyawan otomatis {division_code}-{4 digit}, hanya saran -- keunikan
// tetap divalidasi saat simpan (SIS_Employee_Manage/SIS_PpicEmployee_Manage).
public class EmployeeNextCodeDto
{
    public string? SuggestedCode { get; set; }
}

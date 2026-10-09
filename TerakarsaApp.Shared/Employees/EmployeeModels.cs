using System.ComponentModel.DataAnnotations;

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
    // Prompt 58: no. telp disimpan HANYA digit (normalisasi di SP). Di Master Karyawan & PPIC
    // Karyawan field ini OPSIONAL -- wajib hanya saat pegawai didaftar dari station.
    public string? PhoneNo { get; set; }
    // Prompt 58: diisi saat PIC menonaktifkan pegawai dari station (station yang mengisinya,
    // bukan toggle Aktif/Nonaktif di admin) -- di sini read-only.
    public DateTime? InactiveDate { get; set; }
    public string? InactiveReason { get; set; }
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
    // Prompt 58: opsional di sini. NULL/kosong = tidak mengubah apa-apa (di UPDATE memakai
    // COALESCE di SP, jadi caller yang tidak mengirimnya tidak menghapus nomor yang ada).
    public string? PhoneNo { get; set; }
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
    public string? PhoneNo { get; set; }
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

// No. telp karyawan: aturan yang SAMA dengan SP (SIS_Employee_Manage, SIS_Gate_UpdateEmployee),
// dipakai UI admin & GateApp supaya input salah ditolak dengan pesan, bukan diam-diam dibuang.
// Sebelumnya "--" lolos: SP membuang non-digit -> kosong -> di admin dianggap "tidak diubah"
// (tampil sukses padahal tidak tersimpan), di gate malah menghapus nomor.
public static class PhoneNoRules
{
    public const int MinDigits = 9;

    // null = valid (termasuk kosong). Selain itu = pesan error untuk ditampilkan.
    public static string? Validate(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;

        foreach (var c in input)
        {
            if (c is (>= '0' and <= '9') or ' ' or '+' or '-' or '.' or '(' or ')') continue;
            return "No. telp hanya boleh berisi angka (boleh spasi, +, -, titik, kurung).";
        }

        var digits = new string(input.Where(c => c is >= '0' and <= '9').ToArray());
        if (digits.StartsWith("62")) digits = "0" + digits[2..];

        if (digits.Length == 0) return "No. telp harus berisi angka.";
        if (digits.Length < MinDigits) return $"No. telp minimal {MinDigits} digit.";
        return null;
    }
}

// Validasi form (DataAnnotations) untuk properti no. telp -- memakai PhoneNoRules.
[AttributeUsage(AttributeTargets.Property)]
public sealed class PhoneNoAttribute : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext validationContext)
    {
        var error = PhoneNoRules.Validate(value as string);
        return error is null
            ? ValidationResult.Success
            : new ValidationResult(error, new[] { validationContext.MemberName ?? string.Empty });
    }
}

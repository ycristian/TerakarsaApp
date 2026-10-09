namespace TerakarsaApp.Shared.Stations;

// Prompt 58: tab "Absen" di /station (Input / Rekap 4 hari / Pegawai). Semua DTO di sini
// dipakai lewat token perangkat: divisi SELALU dari token dan line dari operator sesi, jadi
// tidak ada satu pun request yang membawa division_id.
//
// Status absen: H Hadir, I Izin, S Sakit, A Alpa, C Cuti. "Telat" BUKAN status -- dihitung
// saat dibaca (status H dengan jam masuk melewati start_time jadwal divisi).

public static class AttendanceStatus
{
    public const string Hadir = "H";
    public const string Izin = "I";
    public const string Sakit = "S";
    public const string Alpa = "A";
    public const string Cuti = "C";
}

// Satu baris pegawai di sub-tab Input. AttendanceId NULL = belum diisi (baris absen belum ada).
public class StationAttendanceRowDto
{
    public int EmployeeId { get; set; }
    public string? EmployeeCode { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string PositionName { get; set; } = string.Empty;
    // Pegawai nonaktif/pindah line bisa tetap muncul kalau sudah punya baris absen di tanggal
    // itu -- riwayatnya tidak boleh hilang dari layar PIC.
    public bool IsActive { get; set; }
    public int? AttendanceId { get; set; }
    public string? Status { get; set; }
    public TimeSpan? CheckIn { get; set; }
    public TimeSpan? CheckOut { get; set; }
    public string? Note { get; set; }
    public string? Source { get; set; }
    public bool IsLate { get; set; }
    public int LateMinutes { get; set; }
}

// Jadwal hari itu (work_schedule_defaults divisi station) + ringkasan 5 kotak.
public class StationAttendanceScheduleDto
{
    public bool IsWorkingDay { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public int HadirCount { get; set; }
    public int IzinCount { get; set; }
    public int SakitCount { get; set; }
    public int AlpaCount { get; set; }
    public int CutiCount { get; set; }
    public int BelumCount { get; set; }
    public int TelatCount { get; set; }
    public int TotalCount { get; set; }
}

public class StationAttendanceListResult
{
    public List<StationAttendanceRowDto> Rows { get; set; } = new();
    public StationAttendanceScheduleDto Schedule { get; set; } = new();
}

// Satu baris yang dikirim tombol Simpan. Jam dikirim sebagai teks "HH:mm" apa adanya dari
// <input type="time"> -- SP yang mengubahnya jadi TIME(0) (TRY_CONVERT) dan memaksa NULL
// untuk status selain Hadir.
public class StationAttendanceSaveItem
{
    public int EmployeeId { get; set; }
    public string Status { get; set; } = AttendanceStatus.Hadir;
    public string? CheckIn { get; set; }
    public string? CheckOut { get; set; }
    public string? Note { get; set; }
}

public class StationAttendanceSaveRequest
{
    public int ResourceId { get; set; }
    public DateTime AttendanceDate { get; set; }
    public List<StationAttendanceSaveItem> Items { get; set; } = new();
}

// Chip tanggal kuning + badge angka di tab "Absen" (hari kerja saja).
public class StationAttendancePendingDateDto
{
    public DateTime AttendanceDate { get; set; }
    public int PendingCount { get; set; }
}

public class StationAttendanceRecapDateDto
{
    public DateTime AttendanceDate { get; set; }
    public bool IsWorkingDay { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public bool IsToday { get; set; }
}

public class StationAttendanceRecapEmployeeDto
{
    public int EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string PositionName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public int HadirCount { get; set; }
    public int WorkingDayCount { get; set; }
}

// Code: H hadir, T hadir telat, I/S/A/C status, "?" belum diisi, "-" libur tanpa data
// (en dash digambar client -- kolomnya char(1) non-unicode).
public class StationAttendanceRecapCellDto
{
    public int EmployeeId { get; set; }
    public DateTime AttendanceDate { get; set; }
    public string Code { get; set; } = string.Empty;
}

public class StationAttendanceRecapSummaryDto
{
    // % kehadiran = (H + telat) / hari kerja yang SUDAH LEWAT, hanya untuk pegawai aktif.
    public int AttendancePercent { get; set; }
    public int TelatCount { get; set; }
    public int AlpaCount { get; set; }
    public int BelumCount { get; set; }
    public int WorkingDayCount { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    // NULL kalau periode gajian untuk rentang ini belum di-generate (SP jatuh balik ke
    // minggu absen berjalan Minggu-Sabtu).
    public int? PayrollPeriodId { get; set; }
    public string? PeriodCode { get; set; }
}

public class StationAttendanceRecapResult
{
    public List<StationAttendanceRecapDateDto> Dates { get; set; } = new();
    public List<StationAttendanceRecapEmployeeDto> Employees { get; set; } = new();
    public List<StationAttendanceRecapCellDto> Cells { get; set; } = new();
    public StationAttendanceRecapSummaryDto Summary { get; set; } = new();
}

// Pilihan dropdown periode di sub-tab Rekap. Satu periode absen = Minggu s/d Sabtu: hari
// Sabtu dihitung UTUH milik periode yang BERAKHIR di hari itu, tidak dipotong jam 10:00
// seperti periode gajian log workflow (lihat SIS_StationAttendance_Recap).
public class StationAttendancePeriodDto
{
    public int PayrollPeriodId { get; set; }
    public string PeriodCode { get; set; } = string.Empty;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool IsCurrent { get; set; }
}

// Sub-tab Pegawai. Dipakai untuk daftar aktif maupun nonaktif (bedanya isi InactiveDate/Reason).
public class StationEmployeeDto
{
    public int Id { get; set; }
    public string? EmployeeCode { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public int PositionId { get; set; }
    public string PositionName { get; set; } = string.Empty;
    public string? PhoneNo { get; set; }
    public bool IsActive { get; set; }
    public DateTime? JoinDate { get; set; }
    public DateTime? InactiveDate { get; set; }
    public string? InactiveReason { get; set; }
}

public class StationEmployeeListResult
{
    public List<StationEmployeeDto> Items { get; set; } = new();
    // Angka pada toggle Aktif/Nonaktif -- tidak terpengaruh kata kunci pencarian.
    public int ActiveCount { get; set; }
    public int InactiveCount { get; set; }
}

// Divisi, line, dan kode karyawan TIDAK dikirim client: semuanya ditentukan server dari
// token + operator sesi (lihat SIS_StationEmployee_Manage CREATE).
public class StationEmployeeCreateRequest
{
    public int ResourceId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string PhoneNo { get; set; } = string.Empty;
    public int PositionId { get; set; }
    // Tanggal mulai kerja. NULL = hari ini (SP yang mengisinya); tidak boleh di masa depan.
    public DateTime? JoinDate { get; set; }
}

// Dari stasiun hanya nama, no. telp, jabatan, dan tanggal masuk yang bisa diubah -- divisi,
// line, kode karyawan, dan status aktif tetap wewenang Master Karyawan.
public class StationEmployeeUpdateRequest
{
    public int ResourceId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string PhoneNo { get; set; } = string.Empty;
    public int PositionId { get; set; }
    public DateTime? JoinDate { get; set; }
}

public class StationEmployeeInactiveRequest
{
    public int ResourceId { get; set; }
    public DateTime InactiveDate { get; set; }
    // RESIGN / HABIS_KONTRAK / DIBERHENTIKAN / PINDAH_DIVISI (ditegakkan di SP).
    public string InactiveReason { get; set; } = string.Empty;
}

public class StationEmployeeReactivateRequest
{
    public int ResourceId { get; set; }
}

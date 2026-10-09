namespace TerakarsaApp.Shared.Attendance;

// Prompt 70 -- rekap & koreksi attendance_sessions (halaman admin /attendance tab 2 & 3).
// Izin/sakit/cuti TIDAK ada di sini: tidak ada tap = tidak ada baris.

public static class AttendanceSessionStatuses
{
    public const string Open = "OPEN";
    public const string Closed = "CLOSED";
    public const string Anomali = "ANOMALI";
}

public static class AttendanceSessionFlags
{
    public const string LemburDikonfirmasi = "LEMBUR_DIKONFIRMASI";
    public const string BelumCheckout = "BELUM_CHECKOUT";
    public const string LupaKembali = "LUPA_KEMBALI";
    public const string Dikoreksi = "DIKOREKSI";
    // Lihat catatan di sql/sp_Attendance.sql: "tandai sudah benar" di tab Koreksi.
    public const string Diverifikasi = "DIVERIFIKASI";
}

public class AttendanceSessionDto
{
    public int Id { get; set; }
    public DateTime WorkDate { get; set; }
    public int EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    // Divisi & resource adalah SNAPSHOT saat check in -- mutasi line tidak mengubah riwayat.
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public string? ColorHex { get; set; }
    public DateTime CheckInAt { get; set; }
    public DateTime? CheckOutAt { get; set; }
    public int? DurationMinutes { get; set; }
    public string SessionStatus { get; set; } = string.Empty;
    public string? SessionFlag { get; set; }
    public string EntrySource { get; set; } = string.Empty;
    public string? Remarks { get; set; }
}

public class AttendanceReportRequest
{
    public DateTime DateFrom { get; set; }
    public DateTime DateTo { get; set; }
    public int? DivisionId { get; set; }
    public int? ResourceId { get; set; }
    public int? EmployeeId { get; set; }
}

public class AttendanceAnomaliRequest
{
    public DateTime DateFrom { get; set; }
    public DateTime DateTo { get; set; }
}

// Koreksi jam sesi yang sudah ada. Catatan WAJIB -- jam absensi yang diubah manusia harus
// punya alasan tertulis.
public class AttendanceCorrectRequest
{
    public int Id { get; set; }
    public DateTime CheckInAt { get; set; }
    public DateTime CheckOutAt { get; set; }
    public string Remarks { get; set; } = string.Empty;
}

// Sesi untuk karyawan yang kartunya hilang / lupa tap sama sekali.
public class AttendanceManualRequest
{
    public int EmployeeId { get; set; }
    public DateTime CheckInAt { get; set; }
    public DateTime? CheckOutAt { get; set; }
    public string Remarks { get; set; } = string.Empty;
}

// "Tandai sudah benar": jam pulang memang tidak diketahui dan tidak akan pernah diketahui.
public class AttendanceAckRequest
{
    public int Id { get; set; }
    public string Remarks { get; set; } = string.Empty;
}

public class AttendanceDeleteRequest
{
    public int Id { get; set; }
    public string Remarks { get; set; } = string.Empty;
}

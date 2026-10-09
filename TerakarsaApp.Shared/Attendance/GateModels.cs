namespace TerakarsaApp.Shared.Attendance;

// Prompt 70 -- kontrak antara TerakarsaApp.GateApp dan api/gate (header X-Gate-Api-Key).
// Dipakai bersama oleh API, GateApp, dan (sebagian) Client.
//
// Aturan yang tercermin di bentuk DTO ini: GateApp TIDAK pernah menentukan masuk/pulang.
// Ia mengirim tap mentah (UID + waktu tap asli) dan menampilkan ResultCode dari server.

public static class GateResultCodes
{
    public const string CheckIn = "CHECK_IN";
    public const string CheckOut = "CHECK_OUT";
    public const string NeedConfirm = "PERLU_KONFIRMASI";
    public const string Duplicate = "DUPLIKAT";
    public const string UnknownCard = "KARTU_TIDAK_DIKENAL";
    public const string InactiveCard = "KARTU_NONAKTIF";
}

public static class GateConfirmActions
{
    public const string Lembur = "LEMBUR";
    public const string LupaKembali = "LUPA_KEMBALI";
}

public static class GatePendingModes
{
    public const string BelumAmbil = "BELUM_AMBIL";
    public const string BelumKembali = "BELUM_KEMBALI";
    public const string BelumPunyaKartu = "BELUM_PUNYA_KARTU";
}

// ---------- GET api/gate/cards (SIS_Gate_CardSync) ----------

public class GateCardSyncResult
{
    public List<GateCardDto> Cards { get; set; } = new();
    public List<GateEmployeeDto> Employees { get; set; } = new();
    // Jam server, dibandingkan CardSyncService dengan jam lokal tablet: selisih di atas
    // ClockDriftWarningSeconds memunculkan peringatan di layar gate. Jam tablet yang salah
    // merusak semua jam absensi, karena check_in_at/check_out_at memakai tapped_at dari gate.
    public DateTime ServerTime { get; set; }
    public int ActiveEmployeeCount { get; set; }
}

public class GateCardDto
{
    public string CardUid { get; set; } = string.Empty;
    public string CardType { get; set; } = string.Empty;
    public int EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    public string PositionName { get; set; } = string.Empty;
    // Dari positions.is_gate_operator: kartu yang boleh membuka menu satpam.
    public bool IsGateOperator { get; set; }
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public string? ResourceName { get; set; }
    public string? ColorHex { get; set; }
    // Jam masuk divisi ini hari sinkronisasi -- hanya untuk ditampilkan; penentuan jendela
    // check-in tetap dihitung server di SIS_Gate_Tap.
    public TimeSpan? StartTime { get; set; }
}

public class GateEmployeeDto
{
    public int EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    public string? Phone { get; set; }
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public string PositionName { get; set; } = string.Empty;
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public string? ColorHex { get; set; }
    public bool HasActiveCard { get; set; }
}

// ---------- POST api/gate/taps ----------

public class GateTapRequest
{
    // Digenerate GateApp sekali per tap dan TIDAK berubah saat dikirim ulang -- inilah kunci
    // idempoten yang mencegah tap terhitung dua kali kalau jaringan putus setelah server commit.
    public Guid TapUid { get; set; }
    public string CardUid { get; set; } = string.Empty;
    // WAKTU TAP ASLI. Server memakai nilai ini untuk check_in_at/check_out_at, bukan jam terima.
    public DateTime TappedAt { get; set; }
    public string? ConfirmAction { get; set; }
    public bool IsOfflineReplay { get; set; }
}

public class GateTapBatchRequest
{
    public string? GateCode { get; set; }
    public List<GateTapRequest> Taps { get; set; } = new();
}

public class GateTapResultDto
{
    public string ResultCode { get; set; } = string.Empty;
    public string? EmployeeName { get; set; }
    public string? EmployeeCode { get; set; }
    public string? PositionName { get; set; }
    public string? ResourceName { get; set; }
    public string? ColorHex { get; set; }
    public DateTime? CheckInAt { get; set; }
    public DateTime? CheckOutAt { get; set; }
    public int? DurationMinutes { get; set; }
    public string? CardUid { get; set; }
    public string? Message { get; set; }
}

// ---------- GET api/gate/counts ----------

public class GateCountsDto
{
    public int PresentCount { get; set; }
    public int NotTakenCount { get; set; }
    public int NeedCheckCount { get; set; }
}

// ---------- GET api/gate/pending ----------

public class GatePendingRowDto
{
    public int EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public string? ResourceName { get; set; }
    public string? ColorHex { get; set; }
    public DateTime? CheckInAt { get; set; }
    // Hanya terisi untuk mode BELUM_KEMBALI (sesi OPEN) -- target tombol "Batalkan".
    public int? SessionId { get; set; }
}

// ---------- POST api/gate/cards/register ----------

public class GateRegisterCardRequest
{
    public int EmployeeId { get; set; }
    public string CardUid { get; set; } = string.Empty;
    public string CardType { get; set; } = "TETAP";
    // Satu karyawan BOLEH punya beberapa kartu AKTIF sekaligus, jadi penonaktifan kartu lama
    // adalah pilihan satpam, bukan otomatis.
    public bool DeactivateOldCards { get; set; }
    // Satpam yang menjalankan, dari kartu yang dipakai membuka menu (is_gate_operator = 1).
    public int OperatorEmployeeId { get; set; }
}

public class GateRegisterCardResult
{
    public int NewId { get; set; }
    public string CardUid { get; set; } = string.Empty;
}

// ---------- POST api/gate/employees/update ----------

// SENGAJA tanpa ResourceId/DivisionId/PositionId, dan jangan ditambahkan: resource menentukan
// siapa dibayar untuk hasil produksi (Laporan Hanca), itu keputusan supervisor bukan satpam.
public class GateUpdateEmployeeRequest
{
    public int EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? Phone { get; set; }
    public int OperatorEmployeeId { get; set; }
}

// ---------- POST api/gate/sessions/cancel ----------

// Satpam membatalkan sesi OPEN (mis. karyawan salah ambil kartu). Butuh ONLINE.
public class GateCancelSessionRequest
{
    public int SessionId { get; set; }
    public string Reason { get; set; } = string.Empty;
    public int OperatorEmployeeId { get; set; }
}

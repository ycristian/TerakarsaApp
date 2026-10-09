namespace TerakarsaApp.Shared.Attendance;

// Prompt 70 -- kartu RFID pegawai (employee_cards). Lapis identitas UMUM, bukan milik modul
// absensi: kartu yang sama nantinya dipakai untuk pengambilan barang di gudang.
// Hanya UID kartu yang dipakai; tidak ada data yang ditulis ke kartu.

public class EmployeeCardDto
{
    public int Id { get; set; }
    // 10 digit desimal, sudah di-pad nol di depan oleh SP.
    public string CardUid { get; set; } = string.Empty;
    public int EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public string PositionName { get; set; } = string.Empty;
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public string? ColorHex { get; set; }
    // TETAP / SEMENTARA
    public string CardType { get; set; } = string.Empty;
    // AKTIF / NONAKTIF
    public string CardStatus { get; set; } = string.Empty;
    public DateTime IssuedAt { get; set; }
    public int? IssuedByEmployeeId { get; set; }
    // Nama satpam yang mendaftarkan dari gate; NULL kalau dari admin panel.
    public string? IssuedByEmployeeName { get; set; }
    public string? Remarks { get; set; }
}

public class EmployeeCardListRequest
{
    public string? Search { get; set; }
    public bool OnlyActive { get; set; }
}

public class EmployeeCardCreateRequest
{
    public int EmployeeId { get; set; }
    public string CardUid { get; set; } = string.Empty;
    public string CardType { get; set; } = "TETAP";
    public string? Remarks { get; set; }
}

public class EmployeeCardUpdateRequest
{
    public int Id { get; set; }
    public int EmployeeId { get; set; }
    public string CardUid { get; set; } = string.Empty;
    public string CardType { get; set; } = "TETAP";
    public string? Remarks { get; set; }
}

// Jalur NORMAL untuk kartu hilang/diganti: card_status jadi NONAKTIF, bukan soft delete,
// supaya riwayat tetap utuh dan UID-nya bebas didaftarkan ke kartu baru.
public class EmployeeCardDeactivateRequest
{
    public int Id { get; set; }
    public string? Remarks { get; set; }
}

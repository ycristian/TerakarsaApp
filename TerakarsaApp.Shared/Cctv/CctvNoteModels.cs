namespace TerakarsaApp.Shared.Cctv;

// Catatan kejadian di rekaman CCTV (tabel cctv.camera_notes): satu kejadian di satu kamera
// pada satu detik. Semua waktu WIB (+07:00).

public class CctvNoteDto
{
    public int NoteId { get; set; }
    public int CameraId { get; set; }
    public string CameraName { get; set; } = string.Empty;
    public string? Area { get; set; }
    public string MtxPath { get; set; } = string.Empty;
    public DateTimeOffset EventAt { get; set; }
    public string? Tag { get; set; }
    public string Note { get; set; } = string.Empty;
    public string? CreatedByName { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class CctvNoteSaveRequest
{
    public int CameraId { get; set; }          // hanya dipakai saat tambah
    public DateTimeOffset EventAt { get; set; }
    public string? Tag { get; set; }
    public string Note { get; set; } = string.Empty;
}

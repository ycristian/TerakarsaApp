namespace TerakarsaApp.GateApp.Services;

// Prompt 70: seluruh konfigurasi perangkat gate, dari appsettings.json di folder exe.
// ApiKey HARUS sama persis dengan GateService:ApiKey di appsettings API.
public class GateWorkerOptions
{
    public string ApiBaseUrl { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;

    // Dikirim di setiap tap dan tersimpan di gate_taps.gate_code. Ganti nilainya kalau tablet
    // ini dipindah ke pintu lain -- tidak ada yang hardcode di kode.
    public string GateCode { get; set; } = "GATE-UTAMA";

    public int CardSyncSeconds { get; set; } = 300;
    public int QueueFlushSeconds { get; set; } = 10;

    // Dicek LOKAL dulu dari antrian supaya tap dobel tidak membebani API. Server tetap mengecek
    // ulang 30 detik yang sama di SIS_Gate_Tap -- cek lokal hanya mempercepat, bukan otoritas.
    public int TapCooldownSeconds { get; set; } = 30;

    // Selisih jam tablet vs jam server di atas nilai ini memunculkan peringatan. Jam tablet yang
    // salah merusak SEMUA jam absensi, karena check_in_at/check_out_at memakai tapped_at.
    public int ClockDriftWarningSeconds { get; set; } = 120;

    public int MenuIdleTimeoutSeconds { get; set; } = 60;

    // Layar hasil tampil sekian detik lalu kembali ke layar tunggu. Tidak ada tombol OK.
    public int ResultScreenSeconds { get; set; } = 5;

    // 0-100. Dipakai bunyi yang disintesis GateSoundPlayer (lihat catatan di sana: System.Media
    // .SoundPlayer tidak punya pengatur volume, jadi volumenya dibentuk di gelombangnya).
    public int SoundVolumePercent { get; set; } = 80;
}

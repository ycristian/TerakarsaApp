namespace TerakarsaApp.Shared.Cctv;

// Prompt 92: token stream pendek (HMAC) untuk satu path kamera. Dikirim sebagai query ?t=
// ke rute proxy API (api/cctv/hls/..., api/cctv/playback/...). Tidak pernah berisi alamat MediaMTX.
public class CctvStreamTokenDto
{
    public int CameraId { get; set; }
    public string Path { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Token { get; set; } = string.Empty;
    public DateTimeOffset ExpiresAt { get; set; }

    // 2026-11-24: base URL WebRTC (WHEP) MediaMTX yang dipakai browser, dari konfigurasi API
    // (Cctv:PublicWebRtcBaseUrl). Null = klien memakai host halaman + port 8889.
    public string? WebRtcBaseUrl { get; set; }
}

// Prompt 93: rentang rekaman (WIB, +07:00), sudah dipotong ke batas hari & digabung bila
// bersambung (selisih <= 2 detik).
public class CctvRecordingSpanDto
{
    public DateTimeOffset Start { get; set; }
    public DateTimeOffset End { get; set; }
}

// Prompt 93: rekaman paling lama & paling baru yang masih tersedia di server playback.
public class CctvRecordingRangeDto
{
    public DateTimeOffset? Oldest { get; set; }
    public DateTimeOffset? Newest { get; set; }
}

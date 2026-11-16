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
}

namespace TerakarsaApp.Shared.Cctv;

// Prompt 91: DTO master kamera module CCTV (schema cctv).
// Kamera = satu path MediaMTX. Terakarsa tidak pernah menyimpan kredensial kamera.

public static class CctvCameraStatus
{
    public const string Online = "ONLINE";
    public const string Offline = "OFFLINE";
    public const string Unknown = "UNKNOWN";   // server MediaMTX tidak terjangkau
}

public class CctvCameraDto
{
    public int CameraId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Area { get; set; }
    public string MtxPath { get; set; } = string.Empty;
    public string? IpAddress { get; set; }
    public string? SerialNo { get; set; }
    public int? NvrChannel { get; set; }
    public int SortOrder { get; set; }
    public bool IsVisible { get; set; }
    public string? Note { get; set; }
    public string? ResourceNames { get; set; }
    public string? DivisionNames { get; set; }

    // Dari MediaMTX (bukan dari SP).
    public string Status { get; set; } = CctvCameraStatus.Unknown;
    public string? VideoCodec { get; set; }    // mis. "H264", "H265" -- null kalau tidak diketahui

    // H265 tidak bisa diputar di kebanyakan browser.
    public bool IsH265 => VideoCodec is not null
        && (VideoCodec.Contains("265", StringComparison.OrdinalIgnoreCase)
            || VideoCodec.Contains("HEVC", StringComparison.OrdinalIgnoreCase));

    public string StationText
    {
        get
        {
            var parts = new[] { ResourceNames, DivisionNames }.Where(s => !string.IsNullOrWhiteSpace(s));
            var text = string.Join(", ", parts);
            return text.Length == 0 ? "—" : text;
        }
    }
}

public class CctvCameraListResponse
{
    public bool MtxReachable { get; set; }
    public List<CctvCameraDto> Cameras { get; set; } = new();
}

public class CctvCameraLinkDto
{
    public int CameraLinkId { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int? DivisionId { get; set; }
    public string? DivisionName { get; set; }
}

public class CctvCameraDetailDto
{
    public int CameraId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Area { get; set; }
    public string MtxPath { get; set; } = string.Empty;
    public string? IpAddress { get; set; }
    public string? SerialNo { get; set; }
    public int? NvrChannel { get; set; }
    public int SortOrder { get; set; }
    public bool IsVisible { get; set; }
    public string? Note { get; set; }
    public List<CctvCameraLinkDto> Links { get; set; } = new();
}

public class CctvCameraSaveRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Area { get; set; }
    public string? MtxPath { get; set; }       // hanya dipakai saat tambah manual
    public string? IpAddress { get; set; }
    public string? SerialNo { get; set; }
    public int? NvrChannel { get; set; }
    public int SortOrder { get; set; }
    public bool IsVisible { get; set; } = true;
    public string? Note { get; set; }
}

public class CctvCameraLinksRequest
{
    public List<int> ResourceIds { get; set; } = new();
    public List<int> DivisionIds { get; set; } = new();
}

public class CctvLookupItemDto
{
    public string Kind { get; set; } = string.Empty;   // RESOURCE | DIVISION
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? GroupName { get; set; }             // nama divisi untuk RESOURCE
}

public class CctvSyncResultDto
{
    public bool Reachable { get; set; }
    public int PathCount { get; set; }
    public int Added { get; set; }
}

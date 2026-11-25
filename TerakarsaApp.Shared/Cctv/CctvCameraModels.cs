namespace TerakarsaApp.Shared.Cctv;

// Prompt 91: DTO master kamera module CCTV (schema cctv).
// Kamera = satu path MediaMTX. Terakarsa tidak pernah menyimpan kredensial kamera.

public static class CctvCameraStatus
{
    public const string Online = "ONLINE";
    public const string Offline = "OFFLINE";
    public const string Unknown = "UNKNOWN";   // server MediaMTX tidak terjangkau
}

// Prompt 97: kualitas rekaman per kamera (kolom cctv.cameras.record_quality).
public static class CctvRecordQuality
{
    public const string Sub = "SUB";     // aliran ...02 (768x432)
    public const string Main = "MAIN";   // aliran ...01 (1920x1080)
}

// Prompt 97: status sinkron kualitas ke MediaMTX -- hanya di memori API, tidak disimpan di DB.
// Null = belum dicek / tidak diketahui.
public static class CctvQualitySyncStatus
{
    public const string Sesuai = "SESUAI";
    public const string Menunggu = "MENUNGGU";             // MediaMTX tak terjangkau / PATCH gagal
    public const string TidakDidukung = "TIDAK_DIDUKUNG";  // source path bukan pola .../Streaming/Channels/<ch><01|02>
    public const string PathTidakAda = "PATH_TIDAK_ADA";   // path tidak ada di konfigurasi MediaMTX
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
    public string RecordQuality { get; set; } = CctvRecordQuality.Sub;

    // Prompt 97: dari service sinkron kualitas (memori API), lihat CctvQualitySyncStatus.
    public string? QualitySyncStatus { get; set; }

    public bool IsMain => RecordQuality == CctvRecordQuality.Main;

    // Dari MediaMTX (bukan dari SP).
    public string Status { get; set; } = CctvCameraStatus.Unknown;
    public string? VideoCodec { get; set; }    // mis. "H264", "H265" -- null kalau tidak diketahui

    // 2026-11-24: path ubahan H264 untuk live view (MediaMTX "<MtxPath>_h264", hasil ffmpeg) bila
    // path itu siap. Null = live view memakai MtxPath. Rekaman/playback tetap dari MtxPath.
    public string? LivePath { get; set; }

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
    public string RecordQuality { get; set; } = CctvRecordQuality.Sub;
    public string? QualitySyncStatus { get; set; }   // Prompt 97, lihat CctvQualitySyncStatus
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
    // Prompt 97: SUB | MAIN. Null = tidak diubah (UPDATE) / SUB (CREATE).
    public string? RecordQuality { get; set; }
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

// Prompt 94: kamera untuk sebuah transaksi (cctv.SIS_Camera_ForEvent).
public class CctvEventCameraDto
{
    public int CameraId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Area { get; set; }
    public string MtxPath { get; set; } = string.Empty;
    public string MatchedBy { get; set; } = string.Empty;   // RESOURCE | DIVISION | AREA
}

public class CctvForEventResponse
{
    public List<CctvEventCameraDto> Cameras { get; set; } = new();   // tertaut resource / divisi
    public List<CctvEventCameraDto> Others { get; set; } = new();    // kamera lain di area yang sama
}

public class CctvSyncResultDto
{
    public bool Reachable { get; set; }
    public int PathCount { get; set; }
    public int Added { get; set; }
}

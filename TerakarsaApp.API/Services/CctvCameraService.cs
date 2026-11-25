using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Services;

// Prompt 91: master kamera CCTV. Aturan (path unik & valid, tautan tepat satu target)
// ditegakkan di cctv.SIS_Camera_Manage -- service merakit parameter, menggabungkan
// status dari MediaMTX, dan menerjemahkan SqlException jadi pesan UI.
public class CctvCameraService
{
    private readonly AppDbContext _db;
    private readonly CctvMediaMtxClient _mtx;
    private readonly CctvQualitySync _qualitySync;

    public CctvCameraService(AppDbContext db, CctvMediaMtxClient mtx, CctvQualitySync qualitySync)
    {
        _db = db;
        _mtx = mtx;
        _qualitySync = qualitySync;
    }

    // Baris mentah SP (tanpa Status/Codec -- kolom itu tidak ada di result set).
    private class CameraRow
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
        public string RecordQuality { get; set; } = CctvRecordQuality.Sub;   // Prompt 97
        public string? ResourceNames { get; set; }
        public string? DivisionNames { get; set; }
    }

    // ==================== BACA ====================

    public async Task<CctvCameraListResponse> GetListAsync(bool onlyVisible, string? area, CancellationToken ct = default)
    {
        var rowsTask = _db.Database
            .SqlQueryRaw<CameraRow>(
                "EXEC cctv.SIS_Camera_List @OnlyVisible = @OnlyVisible, @Area = @Area",
                new SqlParameter("@OnlyVisible", onlyVisible),
                new SqlParameter("@Area", (object?)NullIfEmpty(area) ?? DBNull.Value))
            .ToListAsync(ct);

        var mtxTask = _mtx.GetPathsAsync(ct);
        await Task.WhenAll(rowsTask, mtxTask);

        var mtx = mtxTask.Result;
        var paths = mtx.Paths
            .GroupBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        var cameras = rowsTask.Result.Select(r =>
        {
            paths.TryGetValue(r.MtxPath, out var p);
            return new CctvCameraDto
            {
                CameraId = r.CameraId,
                Name = r.Name,
                Area = r.Area,
                MtxPath = r.MtxPath,
                IpAddress = r.IpAddress,
                SerialNo = r.SerialNo,
                NvrChannel = r.NvrChannel,
                SortOrder = r.SortOrder,
                IsVisible = r.IsVisible,
                Note = r.Note,
                ResourceNames = r.ResourceNames,
                DivisionNames = r.DivisionNames,
                RecordQuality = r.RecordQuality,
                QualitySyncStatus = _qualitySync.GetStatus(r.MtxPath),
                Status =!mtx.Reachable ? CctvCameraStatus.Unknown
                    : p is { Ready: true } ? CctvCameraStatus.Online
                    : CctvCameraStatus.Offline,
                VideoCodec = p?.VideoCodec,
                LivePath = paths.TryGetValue(LiveAlias(r.MtxPath), out var alias) && alias.Ready ? alias.Name : null
            };
        }).ToList();

        return new CctvCameraListResponse { MtxReachable = mtx.Reachable, Cameras = cameras };
    }

    // cctv.SIS_Camera_Get: result set 1 = detail, result set 2 = tautan.
    // EF SqlQueryRaw hanya membaca satu result set -> SqlCommand + NextResultAsync
    // (pola CuttingService.GetSpreadDetailAsync).
    public async Task<CctvCameraDetailDto?> GetByIdAsync(int cameraId, CancellationToken ct = default)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync(ct);

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "cctv.SIS_Camera_Get";
            cmd.CommandType = CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@CameraId", cameraId));

            using var reader = await cmd.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct)) return null;

            var hasil = new CctvCameraDetailDto
            {
                CameraId = reader.GetInt32(reader.GetOrdinal("CameraId")),
                Name = reader.GetString(reader.GetOrdinal("Name")),
                Area = Str(reader, "Area"),
                MtxPath = reader.GetString(reader.GetOrdinal("MtxPath")),
                IpAddress = Str(reader, "IpAddress"),
                SerialNo = Str(reader, "SerialNo"),
                NvrChannel = Int(reader, "NvrChannel"),
                SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                IsVisible = reader.GetBoolean(reader.GetOrdinal("IsVisible")),
                Note = Str(reader, "Note"),
                RecordQuality = Str(reader, "RecordQuality") ?? CctvRecordQuality.Sub
            };
            hasil.QualitySyncStatus = _qualitySync.GetStatus(hasil.MtxPath);

            if (await reader.NextResultAsync(ct))
            {
                while (await reader.ReadAsync(ct))
                {
                    hasil.Links.Add(new CctvCameraLinkDto
                    {
                        CameraLinkId = reader.GetInt32(reader.GetOrdinal("CameraLinkId")),
                        ResourceId = Int(reader, "ResourceId"),
                        ResourceName = Str(reader, "ResourceName"),
                        DivisionId = Int(reader, "DivisionId"),
                        DivisionName = Str(reader, "DivisionName")
                    });
                }
            }

            return hasil;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public Task<List<CctvLookupItemDto>> GetLookupAsync(CancellationToken ct = default) =>
        _db.Database.SqlQueryRaw<CctvLookupItemDto>("EXEC cctv.SIS_Camera_Lookup").ToListAsync(ct);

    // ==================== MUTASI ====================

    // Kamera baru dengan kualitas MAIN diterapkan oleh tick background berikutnya (CctvQualitySyncHostedService).
    public Task<(bool Success, string Error, int Id)> CreateAsync(CctvCameraSaveRequest r, int userId) =>
        ManageAsync(
            @"EXEC cctv.SIS_Camera_Manage @Action = 'CREATE', @Name = @Name, @Area = @Area, @MtxPath = @MtxPath,
                @IpAddress = @IpAddress, @SerialNo = @SerialNo, @NvrChannel = @NvrChannel,
                @SortOrder = @SortOrder, @IsVisible = @IsVisible, @Note = @Note,
                @RecordQuality = @RecordQuality, @UserId = @UserId",
            P("@Name", r.Name), P("@Area", r.Area), P("@MtxPath", r.MtxPath),
            P("@IpAddress", r.IpAddress), P("@SerialNo", r.SerialNo), P("@NvrChannel", r.NvrChannel),
            P("@SortOrder", r.SortOrder), P("@IsVisible", r.IsVisible), P("@Note", r.Note),
            P("@RecordQuality", NullIfEmpty(r.RecordQuality)), P("@UserId", userId));

    // Prompt 97: simpan ke DB dulu, lalu langsung coba terapkan kualitas ke MediaMTX.
    // Gagal menerapkan (MediaMTX mati / PATCH gagal) TIDAK menggagalkan simpan -> status "menunggu sinkron".
    public async Task<(bool Success, string Error, int Id)> UpdateAsync(int cameraId, CctvCameraSaveRequest r, int userId)
    {
        var hasil = await ManageAsync(
            @"EXEC cctv.SIS_Camera_Manage @Action = 'UPDATE', @CameraId = @CameraId, @Name = @Name, @Area = @Area,
                @IpAddress = @IpAddress, @SerialNo = @SerialNo, @NvrChannel = @NvrChannel,
                @SortOrder = @SortOrder, @IsVisible = @IsVisible, @Note = @Note,
                @RecordQuality = @RecordQuality, @UserId = @UserId",
            P("@CameraId", cameraId), P("@Name", r.Name), P("@Area", r.Area),
            P("@IpAddress", r.IpAddress), P("@SerialNo", r.SerialNo), P("@NvrChannel", r.NvrChannel),
            P("@SortOrder", r.SortOrder), P("@IsVisible", r.IsVisible), P("@Note", r.Note),
            P("@RecordQuality", NullIfEmpty(r.RecordQuality)), P("@UserId", userId));

        if (hasil.Success && !string.IsNullOrWhiteSpace(r.RecordQuality))
        {
            // Nilai dari DB (sumber kebenaran), bukan dari request.
            var detail = await GetByIdAsync(cameraId);
            if (detail is not null)
                await _qualitySync.ApplyAsync(_mtx, detail.MtxPath, detail.RecordQuality, CancellationToken.None);
        }

        return hasil;
    }

    // Prompt 97: target sinkron kualitas -- semua kamera hidup (tampil atau tidak) di cctv.cameras.
    public async Task<List<(string MtxPath, string RecordQuality)>> GetQualityTargetsAsync(CancellationToken ct = default)
    {
        var rows = await _db.Database
            .SqlQueryRaw<CameraRow>("EXEC cctv.SIS_Camera_List @OnlyVisible = 0, @Area = NULL")
            .ToListAsync(ct);
        return rows.Select(r => (r.MtxPath, r.RecordQuality)).ToList();
    }

    public Task<(bool Success, string Error, int Id)> DeleteAsync(int cameraId, int userId) =>
        ManageAsync(
            "EXEC cctv.SIS_Camera_Manage @Action = 'DELETE', @CameraId = @CameraId, @UserId = @UserId",
            P("@CameraId", cameraId), P("@UserId", userId));

    public Task<(bool Success, string Error, int Id)> SetLinksAsync(int cameraId, CctvCameraLinksRequest r, int userId) =>
        ManageAsync(
            @"EXEC cctv.SIS_Camera_Manage @Action = 'SET_LINKS', @CameraId = @CameraId,
                @ResourceIds = @ResourceIds, @DivisionIds = @DivisionIds, @UserId = @UserId",
            P("@CameraId", cameraId),
            P("@ResourceIds", string.Join(",", r.ResourceIds.Distinct())),
            P("@DivisionIds", string.Join(",", r.DivisionIds.Distinct())),
            P("@UserId", userId));

    // Ambil path dari MediaMTX -> SYNC_ADD per path. Path yang sudah ada dilewati di SP.
    public async Task<CctvSyncResultDto> SyncAsync(int userId, CancellationToken ct = default)
    {
        var mtx = await _mtx.GetPathsAsync(ct);
        var hasil = new CctvSyncResultDto { Reachable = mtx.Reachable, PathCount = mtx.Paths.Count };
        if (!mtx.Reachable) return hasil;

        // Path ubahan H264 ("<path>_h264") bukan kamera tersendiri -- dipakai live view kamera induknya.
        foreach (var path in mtx.Paths.Select(p => p.Name).Distinct(StringComparer.OrdinalIgnoreCase)
                     .Where(n => !IsLiveAlias(n)))
        {
            var ids = await _db.Database.SqlQueryRaw<int>(
                    "EXEC cctv.SIS_Camera_Manage @Action = 'SYNC_ADD', @MtxPath = @MtxPath, @UserId = @UserId",
                    P("@MtxPath", path), P("@UserId", userId))
                .ToListAsync(ct);

            if (ids.FirstOrDefault() > 0) hasil.Added++;
        }

        return hasil;
    }

    // Path kamera hidup (dipakai token stream Prompt 92). Null kalau tidak ada / sudah dihapus.
    public async Task<(string MtxPath, string Name)?> GetPathAsync(int cameraId, CancellationToken ct = default)
    {
        var detail = await GetByIdAsync(cameraId, ct);
        return detail is null ? null : (detail.MtxPath, detail.Name);
    }

    // 2026-11-24: kamera H265 di-ubah ke H264 oleh ffmpeg di MediaMTX (runOnReady) ke path "<path>_h264".
    private const string LiveAliasSuffix = "_h264";

    public static string LiveAlias(string mtxPath) => mtxPath + LiveAliasSuffix;

    public static bool IsLiveAlias(string mtxPath) => mtxPath.EndsWith(LiveAliasSuffix, StringComparison.OrdinalIgnoreCase);

    // Path untuk LIVE view: "<path>_h264" kalau path itu ada & siap di MediaMTX, selain itu path kamera.
    public async Task<string> GetLivePathAsync(string mtxPath, CancellationToken ct = default)
    {
        var mtx = await _mtx.GetPathsAsync(ct);
        var alias = LiveAlias(mtxPath);
        return mtx.Paths.Any(p => p.Ready && string.Equals(p.Name, alias, StringComparison.OrdinalIgnoreCase))
            ? alias
            : mtxPath;
    }

    // Prompt 94: kamera untuk sebuah transaksi. Result set 1 = tertaut resource (atau divisi
    // kalau resource tidak punya kamera), result set 2 = kamera lain di area yang sama.
    public async Task<CctvForEventResponse> GetForEventAsync(int? resourceId, int? divisionId, CancellationToken ct = default)
    {
        var hasil = new CctvForEventResponse();
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync(ct);

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "cctv.SIS_Camera_ForEvent";
            cmd.CommandType = CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@DivisionId", (object?)divisionId ?? DBNull.Value));

            using var reader = await cmd.ExecuteReaderAsync(ct);
            await BacaKameraEvent(reader, hasil.Cameras, ct);
            if (await reader.NextResultAsync(ct)) await BacaKameraEvent(reader, hasil.Others, ct);
            return hasil;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    private static async Task BacaKameraEvent(SqlDataReader reader, List<CctvEventCameraDto> list, CancellationToken ct)
    {
        while (await reader.ReadAsync(ct))
        {
            list.Add(new CctvEventCameraDto
            {
                CameraId = reader.GetInt32(reader.GetOrdinal("CameraId")),
                Name = reader.GetString(reader.GetOrdinal("Name")),
                Area = Str(reader, "Area"),
                MtxPath = reader.GetString(reader.GetOrdinal("MtxPath")),
                MatchedBy = reader.GetString(reader.GetOrdinal("MatchedBy"))
            });
        }
    }

    // Prompt 93: nama kamera hidup untuk path (nama file unduhan). Null kalau tidak ada.
    public async Task<string?> GetNameByPathAsync(string mtxPath, CancellationToken ct = default)
    {
        var rows = await _db.Database
            .SqlQueryRaw<CameraRow>("EXEC cctv.SIS_Camera_List @OnlyVisible = 0, @Area = NULL")
            .ToListAsync(ct);
        return rows.FirstOrDefault(r => string.Equals(r.MtxPath, mtxPath, StringComparison.OrdinalIgnoreCase))?.Name;
    }

    // ==================== bantuan ====================

    private async Task<(bool Success, string Error, int Id)> ManageAsync(string sql, params SqlParameter[] parameters)
    {
        try
        {
            var ids = await _db.Database.SqlQueryRaw<int>(sql, parameters).ToListAsync();
            return (true, string.Empty, ids.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    private static SqlParameter P(string name, object? value) => new(name, value ?? DBNull.Value);

    private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    private static string? Str(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetString(i);
    }

    private static int? Int(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetInt32(i);
    }
}

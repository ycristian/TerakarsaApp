using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Services;

// Catatan kejadian di rekaman CCTV (cctv.camera_notes). Aturan ditegakkan di
// cctv.SIS_CameraNote_Manage; service hanya mengubah waktu WIB <-> datetime2 tanpa offset.
public class CctvNoteService
{
    private readonly AppDbContext _db;

    public CctvNoteService(AppDbContext db)
    {
        _db = db;
    }

    private class NoteRow
    {
        public int NoteId { get; set; }
        public int CameraId { get; set; }
        public string CameraName { get; set; } = string.Empty;
        public string? Area { get; set; }
        public string MtxPath { get; set; } = string.Empty;
        public DateTime EventAt { get; set; }
        public string? Tag { get; set; }
        public string Note { get; set; } = string.Empty;
        public string? CreatedByName { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // Kejadian pada satu tanggal WIB, urut waktu. cameraId null = semua kamera.
    public async Task<List<CctvNoteDto>> GetByDateAsync(DateOnly date, int? cameraId, CancellationToken ct = default)
    {
        var from = date.ToDateTime(TimeOnly.MinValue);
        var rows = await _db.Database
            .SqlQueryRaw<NoteRow>(
                "EXEC cctv.SIS_CameraNote_List @From = @From, @To = @To, @CameraId = @CameraId",
                new SqlParameter("@From", System.Data.SqlDbType.DateTime2) { Value = from },
                new SqlParameter("@To", System.Data.SqlDbType.DateTime2) { Value = from.AddDays(1) },
                new SqlParameter("@CameraId", (object?)cameraId ?? DBNull.Value))
            .ToListAsync(ct);

        return rows.Select(r => new CctvNoteDto
        {
            NoteId = r.NoteId,
            CameraId = r.CameraId,
            CameraName = r.CameraName,
            Area = r.Area,
            MtxPath = r.MtxPath,
            EventAt = Wib(r.EventAt),
            Tag = r.Tag,
            Note = r.Note,
            CreatedByName = r.CreatedByName,
            CreatedAt = Wib(r.CreatedAt)
        }).ToList();
    }

    public Task<List<string>> GetTagsAsync(CancellationToken ct = default) =>
        _db.Database.SqlQueryRaw<string>("EXEC cctv.SIS_CameraNote_Tags").ToListAsync(ct);

    public Task<(bool Success, string Error, int Id)> CreateAsync(CctvNoteSaveRequest r, int userId) =>
        ManageAsync(
            @"EXEC cctv.SIS_CameraNote_Manage @Action = 'CREATE', @CameraId = @CameraId, @EventAt = @EventAt,
                @Tag = @Tag, @Note = @Note, @UserId = @UserId",
            P("@CameraId", r.CameraId), EventAt(r.EventAt), P("@Tag", r.Tag), P("@Note", r.Note), P("@UserId", userId));

    public Task<(bool Success, string Error, int Id)> UpdateAsync(int noteId, CctvNoteSaveRequest r, int userId) =>
        ManageAsync(
            @"EXEC cctv.SIS_CameraNote_Manage @Action = 'UPDATE', @NoteId = @NoteId, @EventAt = @EventAt,
                @Tag = @Tag, @Note = @Note, @UserId = @UserId",
            P("@NoteId", noteId), EventAt(r.EventAt), P("@Tag", r.Tag), P("@Note", r.Note), P("@UserId", userId));

    public Task<(bool Success, string Error, int Id)> DeleteAsync(int noteId, int userId) =>
        ManageAsync(
            "EXEC cctv.SIS_CameraNote_Manage @Action = 'DELETE', @NoteId = @NoteId, @UserId = @UserId",
            P("@NoteId", noteId), P("@UserId", userId));

    // ==================== bantuan ====================

    // datetime2 di DB = jam WIB tanpa offset.
    private static DateTimeOffset Wib(DateTime t) =>
        new(DateTime.SpecifyKind(t, DateTimeKind.Unspecified), CctvTime.Wib);

    // Ke WIB, dibulatkan ke detik (kolom datetime2(0)).
    private static SqlParameter EventAt(DateTimeOffset t)
    {
        var w = CctvTime.ToWib(t).DateTime;
        w = new DateTime(w.Ticks - w.Ticks % TimeSpan.TicksPerSecond, DateTimeKind.Unspecified);
        return new SqlParameter("@EventAt", System.Data.SqlDbType.DateTime2) { Value = w };
    }

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
}

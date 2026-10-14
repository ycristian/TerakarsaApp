using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.API.Services;

// Prompt 74: stock opname benang. SELURUH aturan (satu sesi OPEN, semua SKU harus
// dihitung sebelum tutup, alasan wajib untuk ADJUST, hasil akhir harus sama dengan
// counted_qty) ada di inv.SIS_ThreadOpname_Manage -- service hanya merakit JSON
// parameter dan menerjemahkan SqlException jadi pesan UI.
//
// CATATAN: action CLOSE TIDAK BOLEH dipanggil lewat INSERT ... EXEC (lihat komentar
// di SP) -- di sini dipanggil lewat SqlQueryRaw/ExecuteSqlRaw biasa.
public class ThreadOpnameService
{
    private static readonly JsonSerializerOptions JsonOpt = new() { PropertyNamingPolicy = null };

    private readonly AppDbContext _db;

    public ThreadOpnameService(AppDbContext db)
    {
        _db = db;
    }

    // ==================== BACA ====================

    public async Task<ThreadOpnameCurrentDto> GetCurrentAsync()
    {
        var sesi = (await _db.Database
            .SqlQueryRaw<ThreadOpnameSessionDto>("EXEC inv.SIS_ThreadOpname_Current @Bagian = 'SESI'")
            .ToListAsync()).FirstOrDefault();

        if (sesi is null) return new ThreadOpnameCurrentDto();

        var rak = await _db.Database
            .SqlQueryRaw<ThreadOpnameLocationDto>("EXEC inv.SIS_ThreadOpname_Current @Bagian = 'RAK'")
            .ToListAsync();

        return new ThreadOpnameCurrentDto { Session = sesi, Locations = rak };
    }

    public async Task<ThreadOpnameRakDto> GetLinesAsync(int sessionId, int? locationId)
    {
        var lines = await _db.Database
            .SqlQueryRaw<ThreadOpnameLineDto>(
                "EXEC inv.SIS_ThreadOpname_Lines @SessionId = @SessionId, @LocationId = @LocationId, @Bagian = 'LINE'",
                new SqlParameter("@SessionId", sessionId),
                new SqlParameter("@LocationId", locationId ?? (object)DBNull.Value))
            .ToListAsync();

        var splits = await _db.Database
            .SqlQueryRaw<ThreadOpnameSplitDto>(
                "EXEC inv.SIS_ThreadOpname_Lines @SessionId = @SessionId, @LocationId = @LocationId, @Bagian = 'SPLIT'",
                new SqlParameter("@SessionId", sessionId),
                new SqlParameter("@LocationId", locationId ?? (object)DBNull.Value))
            .ToListAsync();

        return new ThreadOpnameRakDto { Lines = lines, Splits = splits };
    }

    public Task<List<ThreadOpnameSessionDto>> GetListAsync(int top) =>
        _db.Database.SqlQueryRaw<ThreadOpnameSessionDto>(
                "EXEC inv.SIS_ThreadOpname_List @Top = @Top",
                new SqlParameter("@Top", top))
            .ToListAsync();

    public async Task<ThreadOpnameDetailDto?> GetByIdAsync(int sessionId)
    {
        var sesi = (await _db.Database
            .SqlQueryRaw<ThreadOpnameSessionDto>(
                "EXEC inv.SIS_ThreadOpname_GetById @SessionId = @SessionId, @Bagian = 'SESI'",
                new SqlParameter("@SessionId", sessionId))
            .ToListAsync()).FirstOrDefault();

        if (sesi is null) return null;

        var hasil = await _db.Database
            .SqlQueryRaw<ThreadOpnameResultDto>(
                "EXEC inv.SIS_ThreadOpname_GetById @SessionId = @SessionId, @Bagian = 'HASIL'",
                new SqlParameter("@SessionId", sessionId))
            .ToListAsync();

        return new ThreadOpnameDetailDto { Session = sesi, Results = hasil };
    }

    public Task<List<ThreadOpnameProposalDto>> PreviewCloseAsync(int sessionId) =>
        _db.Database.SqlQueryRaw<ThreadOpnameProposalDto>(
                "EXEC inv.SIS_ThreadOpname_Manage @Action = 'PREVIEW_CLOSE', @SessionId = @SessionId",
                new SqlParameter("@SessionId", sessionId))
            .ToListAsync();

    public Task<List<ThreadReasonCodeDto>> GetReasonCodesAsync() =>
        _db.Database.SqlQueryRaw<ThreadReasonCodeDto>("EXEC inv.SIS_ThreadReasonCode_List").ToListAsync();

    // ==================== MUTASI ====================

    public Task<(bool Success, string Error, int Id)> OpenAsync(ThreadOpnameOpenRequest request, int userId)
    {
        var json = request.LocationIds.Count == 0
            ? null
            : JsonSerializer.Serialize(request.LocationIds);

        return ManageAsync(
            "EXEC inv.SIS_ThreadOpname_Manage @Action = 'OPEN', @LocationIdsJson = @LocationIdsJson, @Note = @Note, @UserId = @UserId",
            new SqlParameter("@LocationIdsJson", (object?)json ?? DBNull.Value),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value),
            new SqlParameter("@UserId", userId));
    }

    public Task<(bool Success, string Error, int Id)> AddLineAsync(ThreadOpnameAddLineRequest request, int userId) =>
        ManageAsync(
            @"EXEC inv.SIS_ThreadOpname_Manage @Action = 'ADD_LINE', @SessionId = @SessionId,
                @LocationId = @LocationId, @ItemId = @ItemId, @UserId = @UserId",
            new SqlParameter("@SessionId", request.SessionId),
            new SqlParameter("@LocationId", request.LocationId),
            new SqlParameter("@ItemId", request.ThreadItemId),
            new SqlParameter("@UserId", userId));

    public Task<(bool Success, string Error, int Id)> CountAsync(ThreadOpnameCountRequest request, int userId)
    {
        // Nama field JSON harus snake_case -- OPENJSON di SP membacanya begitu.
        var splitJson = request.Splits.Count == 0
            ? null
            : JsonSerializer.Serialize(request.Splits.Select(s => new
            {
                split_cone_id = s.SplitConeId,
                is_found = s.IsFound
            }));

        return ManageAsync(
            @"EXEC inv.SIS_ThreadOpname_Manage @Action = 'COUNT', @LineId = @LineId,
                @CountedQty = @CountedQty, @SplitFoundJson = @SplitFoundJson, @UserId = @UserId",
            new SqlParameter("@LineId", request.LineId),
            new SqlParameter("@CountedQty", request.CountedQty),
            new SqlParameter("@SplitFoundJson", (object?)splitJson ?? DBNull.Value),
            new SqlParameter("@UserId", userId));
    }

    public Task<(bool Success, string Error, int Id)> LocationDoneAsync(int sessionId, int locationId, int userId) =>
        ManageAsync(
            @"EXEC inv.SIS_ThreadOpname_Manage @Action = 'LOCATION_DONE', @SessionId = @SessionId,
                @LocationId = @LocationId, @UserId = @UserId",
            new SqlParameter("@SessionId", sessionId),
            new SqlParameter("@LocationId", locationId),
            new SqlParameter("@UserId", userId));

    public Task<(bool Success, string Error, int Id)> CloseAsync(ThreadOpnameCloseRequest request, int userId)
    {
        var json = JsonSerializer.Serialize(request.Resolutions.Select(r => new
        {
            line_id = r.LineId,
            action = r.Action,
            qty = r.Qty,
            from_location_id = r.FromLocationId,
            to_location_id = r.ToLocationId,
            split_cone_id = r.SplitConeId,
            reason_code = r.ReasonCode,
            note = r.Note
        }));

        return ManageAsync(
            @"EXEC inv.SIS_ThreadOpname_Manage @Action = 'CLOSE', @SessionId = @SessionId,
                @ResolutionsJson = @ResolutionsJson, @Note = @Note, @UserId = @UserId",
            new SqlParameter("@SessionId", request.SessionId),
            new SqlParameter("@ResolutionsJson", json),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value),
            new SqlParameter("@UserId", userId));
    }

    public Task<(bool Success, string Error, int Id)> CancelAsync(int sessionId, int userId) =>
        ManageAsync(
            "EXEC inv.SIS_ThreadOpname_Manage @Action = 'CANCEL', @SessionId = @SessionId, @UserId = @UserId",
            new SqlParameter("@SessionId", sessionId),
            new SqlParameter("@UserId", userId));

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
}

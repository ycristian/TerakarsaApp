using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.API.Services;

// Prompt 70: CRUD kartu pegawai + rekap/koreksi absensi untuk halaman admin /attendance
// (module HR_ATTENDANCE). Semua lewat JWT user biasa -- berbeda dengan GateService yang dipakai
// perangkat gate tanpa login.
public class AttendanceService
{
    private readonly AppDbContext _db;

    public AttendanceService(AppDbContext db)
    {
        _db = db;
    }

    // ---------- Kartu pegawai ----------

    public async Task<List<EmployeeCardDto>> GetCardsAsync(EmployeeCardListRequest request)
    {
        var searchParam = new SqlParameter("@Search", (object?)request.Search ?? DBNull.Value);
        var onlyActiveParam = new SqlParameter("@OnlyActive", request.OnlyActive);

        return await _db.Database
            .SqlQueryRaw<EmployeeCardDto>(
                "EXEC SIS_EmployeeCard_List @Search = @Search, @OnlyActive = @OnlyActive",
                searchParam, onlyActiveParam)
            .ToListAsync();
    }

    public async Task<EmployeeCardDto?> GetCardByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var rows = await _db.Database
            .SqlQueryRaw<EmployeeCardDto>("EXEC SIS_EmployeeCard_GetById @Id = @Id", idParam)
            .ToListAsync();

        return rows.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> CreateCardAsync(EmployeeCardCreateRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "CREATE"),
            new SqlParameter("@EmployeeId", request.EmployeeId),
            new SqlParameter("@CardUid", request.CardUid ?? string.Empty),
            new SqlParameter("@CardType", request.CardType ?? string.Empty),
            new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_EmployeeCard_Manage @Action = @Action, @EmployeeId = @EmployeeId, @CardUid = @CardUid, @CardType = @CardType, @Remarks = @Remarks, @UserId = @UserId",
            parameters);
    }

    public async Task<(bool Success, string Error)> UpdateCardAsync(EmployeeCardUpdateRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "UPDATE"),
            new SqlParameter("@Id", request.Id),
            new SqlParameter("@EmployeeId", request.EmployeeId),
            new SqlParameter("@CardUid", request.CardUid ?? string.Empty),
            new SqlParameter("@CardType", request.CardType ?? string.Empty),
            new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_EmployeeCard_Manage @Action = @Action, @Id = @Id, @EmployeeId = @EmployeeId, @CardUid = @CardUid, @CardType = @CardType, @Remarks = @Remarks, @UserId = @UserId",
            parameters);
    }

    // Jalur NORMAL kartu hilang/diganti -- bukan soft delete, supaya riwayat tetap utuh.
    public async Task<(bool Success, string Error)> DeactivateCardAsync(EmployeeCardDeactivateRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "DEACTIVATE"),
            new SqlParameter("@Id", request.Id),
            new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_EmployeeCard_Manage @Action = @Action, @Id = @Id, @Remarks = @Remarks, @UserId = @UserId",
            parameters);
    }

    // Hanya untuk salah input.
    public async Task<(bool Success, string Error)> DeleteCardAsync(int id, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "DELETE"),
            new SqlParameter("@Id", id),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_EmployeeCard_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            parameters);
    }

    // ---------- Rekap & koreksi ----------

    public async Task<List<AttendanceSessionDto>> GetReportAsync(AttendanceReportRequest request)
    {
        var parameters = new[]
        {
            new SqlParameter("@DateFrom", request.DateFrom.Date),
            new SqlParameter("@DateTo", request.DateTo.Date),
            new SqlParameter("@DivisionId", (object?)request.DivisionId ?? DBNull.Value),
            new SqlParameter("@ResourceId", (object?)request.ResourceId ?? DBNull.Value),
            new SqlParameter("@EmployeeId", (object?)request.EmployeeId ?? DBNull.Value),
        };

        return await _db.Database
            .SqlQueryRaw<AttendanceSessionDto>(
                "EXEC SIS_Attendance_Report @DateFrom = @DateFrom, @DateTo = @DateTo, @DivisionId = @DivisionId, @ResourceId = @ResourceId, @EmployeeId = @EmployeeId",
                parameters)
            .ToListAsync();
    }

    public async Task<List<AttendanceSessionDto>> GetAnomaliAsync(AttendanceAnomaliRequest request)
    {
        var dateFromParam = new SqlParameter("@DateFrom", request.DateFrom.Date);
        var dateToParam = new SqlParameter("@DateTo", request.DateTo.Date);

        return await _db.Database
            .SqlQueryRaw<AttendanceSessionDto>(
                "EXEC SIS_Attendance_Anomali @DateFrom = @DateFrom, @DateTo = @DateTo",
                dateFromParam, dateToParam)
            .ToListAsync();
    }

    public async Task<(bool Success, string Error)> CorrectAsync(AttendanceCorrectRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "UPDATE"),
            new SqlParameter("@Id", request.Id),
            new SqlParameter("@CheckInAt", request.CheckInAt),
            new SqlParameter("@CheckOutAt", request.CheckOutAt),
            new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_Attendance_Manage @Action = @Action, @Id = @Id, @CheckInAt = @CheckInAt, @CheckOutAt = @CheckOutAt, @Remarks = @Remarks, @UserId = @UserId",
            parameters);
    }

    public async Task<(bool Success, string Error)> CreateManualAsync(AttendanceManualRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "CREATE_MANUAL"),
            new SqlParameter("@EmployeeId", request.EmployeeId),
            new SqlParameter("@CheckInAt", request.CheckInAt),
            new SqlParameter("@CheckOutAt", (object?)request.CheckOutAt ?? DBNull.Value),
            new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_Attendance_Manage @Action = @Action, @EmployeeId = @EmployeeId, @CheckInAt = @CheckInAt, @CheckOutAt = @CheckOutAt, @Remarks = @Remarks, @UserId = @UserId",
            parameters);
    }

    public async Task<(bool Success, string Error)> AckAsync(AttendanceAckRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "ACK"),
            new SqlParameter("@Id", request.Id),
            new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_Attendance_Manage @Action = @Action, @Id = @Id, @Remarks = @Remarks, @UserId = @UserId",
            parameters);
    }

    public async Task<(bool Success, string Error)> DeleteSessionAsync(AttendanceDeleteRequest request, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "DELETE"),
            new SqlParameter("@Id", request.Id),
            new SqlParameter("@Remarks", (object?)request.Remarks ?? DBNull.Value),
            new SqlParameter("@UserId", userId),
        };

        return await ExecAsync(
            "EXEC SIS_Attendance_Manage @Action = @Action, @Id = @Id, @Remarks = @Remarks, @UserId = @UserId",
            parameters);
    }

    // Validasi bisnis ditegakkan di SP (RAISERROR pesan Indonesia), jadi pesan aslinya
    // diteruskan apa adanya ke UI -- termasuk pesan "kartu sudah aktif untuk <nama>".
    private async Task<(bool Success, string Error)> ExecAsync(string sql, SqlParameter[] parameters)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(sql, parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}

using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.WorkSchedules;

namespace TerakarsaApp.API.Services;

// Prompt 36: setting default jam kerja per divisi per hari + jam istirahat, fondasi
// dashboard target harian (Prompt 38). Target default (default_target_per_person) hidup
// di kolom divisions, jadi disimpan lewat DivisionService.UpdateAsync (SIS_Division_Manage
// UPDATE) yang sudah ada -- bukan action baru -- supaya satu baris divisi hanya diubah
// lewat satu jalur SP.
public class WorkScheduleService
{
    private readonly AppDbContext _db;
    private readonly DivisionService _divisionService;

    public WorkScheduleService(AppDbContext db, DivisionService divisionService)
    {
        _db = db;
        _divisionService = divisionService;
    }

    // SIS_WorkScheduleDefault_List mengembalikan 2 result set (divisi, baris jam kerja) --
    // EF Core SqlQueryRaw hanya mendukung satu result set, jadi pakai SqlCommand mentah +
    // reader.NextResultAsync() (pola sama dengan ReportWipService.GetSummaryAsync).
    public async Task<List<WorkScheduleDivisionDto>> GetDefaultsAsync()
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_WorkScheduleDefault_List";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;

            using var reader = await cmd.ExecuteReaderAsync();

            var divisions = new List<WorkScheduleDivisionDto>();
            while (await reader.ReadAsync())
            {
                divisions.Add(new WorkScheduleDivisionDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionCode = reader.GetString(reader.GetOrdinal("DivisionCode")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    ShowInDashboard = reader.GetBoolean(reader.GetOrdinal("ShowInDashboard")),
                    DashboardMode = reader.GetString(reader.GetOrdinal("DashboardMode")),
                    DashboardSortOrder = reader.GetInt32(reader.GetOrdinal("DashboardSortOrder")),
                    DefaultTargetPerPerson = reader.GetInt32(reader.GetOrdinal("DefaultTargetPerPerson")),
                });
            }

            var byDivisionId = divisions.ToDictionary(d => d.Id);

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                var divisionId = reader.GetInt32(reader.GetOrdinal("DivisionId"));
                if (!byDivisionId.TryGetValue(divisionId, out var division)) continue;

                division.Days.Add(new WorkScheduleDayDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    DivisionId = divisionId,
                    DayOfWeek = reader.GetByte(reader.GetOrdinal("DayOfWeek")),
                    IsWorkingDay = reader.GetBoolean(reader.GetOrdinal("IsWorkingDay")),
                    StartTime = reader.GetTimeSpan(reader.GetOrdinal("StartTime")),
                    EndTime = reader.GetTimeSpan(reader.GetOrdinal("EndTime")),
                });
            }

            return divisions;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<(bool Success, string Error)> SaveDivisionScheduleAsync(SaveDivisionScheduleRequest request, int userId)
    {
        var division = await _divisionService.GetByIdAsync(request.DivisionId);
        if (division is null) return (false, "Divisi tidak ditemukan.");

        var targetUpdateResult = await _divisionService.UpdateAsync(new Shared.Divisions.DivisionUpdateRequest
        {
            Id = division.Id,
            DivisionCode = division.DivisionCode,
            DivisionName = division.DivisionName,
            ShowInDashboard = division.ShowInDashboard,
            DashboardMode = division.DashboardMode,
            DashboardSortOrder = division.DashboardSortOrder,
            DefaultTargetPerPerson = request.DefaultTargetPerPerson
        }, userId);
        if (!targetUpdateResult.Success) return targetUpdateResult;

        var daysJson = JsonSerializer.Serialize(request.Days.Select(d => new
        {
            dayOfWeek = d.DayOfWeek,
            isWorkingDay = d.IsWorkingDay,
            startTime = d.StartTime.ToString(@"hh\:mm\:ss"),
            endTime = d.EndTime.ToString(@"hh\:mm\:ss")
        }));

        var actionParam = new SqlParameter("@Action", "SAVE_DIVISION");
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var daysJsonParam = new SqlParameter("@DaysJson", daysJson);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkScheduleDefault_Manage @Action = @Action, @DivisionId = @DivisionId, @DaysJson = @DaysJson, @UserId = @UserId",
                actionParam, divisionIdParam, daysJsonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<List<WorkBreakDto>> GetBreaksAsync()
    {
        return await _db.Database
            .SqlQueryRaw<WorkBreakDto>("EXEC SIS_WorkBreakDefault_List")
            .ToListAsync();
    }

    public async Task<(bool Success, string Error)> CreateBreakAsync(WorkBreakCreateRequest request, int userId)
    {
        return await SaveBreakAsync(null, request.BreakName, request.DayOfWeek, request.StartTime, request.EndTime, request.SortOrder, userId);
    }

    public async Task<(bool Success, string Error)> UpdateBreakAsync(WorkBreakUpdateRequest request, int userId)
    {
        return await SaveBreakAsync(request.Id, request.BreakName, request.DayOfWeek, request.StartTime, request.EndTime, request.SortOrder, userId);
    }

    private async Task<(bool Success, string Error)> SaveBreakAsync(int? id, string breakName, int? dayOfWeek, TimeSpan startTime, TimeSpan endTime, int sortOrder, int userId)
    {
        var actionParam = new SqlParameter("@Action", "SAVE_BREAK");
        var idParam = new SqlParameter("@Id", (object?)id ?? DBNull.Value);
        var breakNameParam = new SqlParameter("@BreakName", breakName);
        var dayOfWeekParam = new SqlParameter("@DayOfWeek", (object?)dayOfWeek ?? DBNull.Value);
        var startTimeParam = new SqlParameter("@StartTime", startTime.ToString(@"hh\:mm\:ss"));
        var endTimeParam = new SqlParameter("@EndTime", endTime.ToString(@"hh\:mm\:ss"));
        var sortOrderParam = new SqlParameter("@SortOrder", sortOrder);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkScheduleDefault_Manage @Action = @Action, @Id = @Id, @BreakName = @BreakName, @DayOfWeek = @DayOfWeek, @StartTime = @StartTime, @EndTime = @EndTime, @SortOrder = @SortOrder, @UserId = @UserId",
                actionParam, idParam, breakNameParam, dayOfWeekParam, startTimeParam, endTimeParam, sortOrderParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task DeleteBreakAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE_BREAK");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_WorkScheduleDefault_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

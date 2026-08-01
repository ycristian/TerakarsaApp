using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.DailyPlans;
using TerakarsaApp.Shared.WorkSchedules;

namespace TerakarsaApp.API.Services;

public class DailyPlanService
{
    private readonly AppDbContext _db;

    public DailyPlanService(AppDbContext db)
    {
        _db = db;
    }

    // SIS_DailyPlan_GetByDate mengembalikan 3 result set (divisi, resource, istirahat) --
    // EF Core SqlQueryRaw hanya mendukung satu result set, jadi pakai SqlCommand mentah +
    // reader.NextResultAsync() (pola sama dengan ReportWipService.GetSummaryAsync /
    // WorkScheduleService.GetDefaultsAsync).
    public async Task<DailyPlanGetByDateResult> GetByDateAsync(DateTime planDate)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_DailyPlan_GetByDate";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@PlanDate", planDate.Date));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new DailyPlanGetByDateResult();

            while (await reader.ReadAsync())
            {
                result.Divisions.Add(new DailyPlanDivisionDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    DashboardMode = reader.GetString(reader.GetOrdinal("DashboardMode")),
                    DefaultTargetPerPerson = reader.GetInt32(reader.GetOrdinal("DefaultTargetPerPerson")),
                    IsSaved = reader.GetBoolean(reader.GetOrdinal("IsSaved")),
                    DailyDivisionPlanId = reader.IsDBNull(reader.GetOrdinal("DailyDivisionPlanId")) ? null : reader.GetInt32(reader.GetOrdinal("DailyDivisionPlanId")),
                    IsHoliday = reader.GetBoolean(reader.GetOrdinal("IsHoliday")),
                    StartTime = reader.IsDBNull(reader.GetOrdinal("StartTime")) ? null : reader.GetTimeSpan(reader.GetOrdinal("StartTime")),
                    EndTime = reader.IsDBNull(reader.GetOrdinal("EndTime")) ? null : reader.GetTimeSpan(reader.GetOrdinal("EndTime")),
                    Headcount = reader.IsDBNull(reader.GetOrdinal("Headcount")) ? null : reader.GetInt32(reader.GetOrdinal("Headcount")),
                    TargetPerPerson = reader.IsDBNull(reader.GetOrdinal("TargetPerPerson")) ? null : reader.GetInt32(reader.GetOrdinal("TargetPerPerson")),
                    Remark = reader.IsDBNull(reader.GetOrdinal("Remark")) ? null : reader.GetString(reader.GetOrdinal("Remark")),
                    UpdatedAt = reader.IsDBNull(reader.GetOrdinal("UpdatedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                    SavedByName = reader.IsDBNull(reader.GetOrdinal("SavedByName")) ? null : reader.GetString(reader.GetOrdinal("SavedByName")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Resources.Add(new DailyPlanResourceDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    ResourceId = reader.GetInt32(reader.GetOrdinal("ResourceId")),
                    ResourceName = reader.GetString(reader.GetOrdinal("ResourceName")),
                    Headcount = reader.IsDBNull(reader.GetOrdinal("Headcount")) ? null : reader.GetInt32(reader.GetOrdinal("Headcount")),
                    TargetPerPerson = reader.IsDBNull(reader.GetOrdinal("TargetPerPerson")) ? null : reader.GetInt32(reader.GetOrdinal("TargetPerPerson")),
                    StartTime = reader.IsDBNull(reader.GetOrdinal("StartTime")) ? null : reader.GetTimeSpan(reader.GetOrdinal("StartTime")),
                    EndTime = reader.IsDBNull(reader.GetOrdinal("EndTime")) ? null : reader.GetTimeSpan(reader.GetOrdinal("EndTime")),
                    Remark = reader.IsDBNull(reader.GetOrdinal("Remark")) ? null : reader.GetString(reader.GetOrdinal("Remark")),
                    IsSaved = reader.GetBoolean(reader.GetOrdinal("IsSaved")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Breaks.Add(new WorkBreakDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    BreakName = reader.GetString(reader.GetOrdinal("BreakName")),
                    DayOfWeek = reader.IsDBNull(reader.GetOrdinal("DayOfWeek")) ? null : reader.GetByte(reader.GetOrdinal("DayOfWeek")),
                    StartTime = reader.GetTimeSpan(reader.GetOrdinal("StartTime")),
                    EndTime = reader.GetTimeSpan(reader.GetOrdinal("EndTime")),
                    SortOrder = reader.GetInt32(reader.GetOrdinal("SortOrder")),
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<(bool Success, string Error, int PlanId)> SaveAsync(int divisionId, SaveDailyPlanRequest request, int userId)
    {
        var resourcesJson = JsonSerializer.Serialize(request.Resources.Select(r => new
        {
            resourceId = r.ResourceId,
            headcount = r.Headcount,
            targetPerPerson = r.TargetPerPerson,
            startTime = r.StartTime,
            endTime = r.EndTime,
            remark = r.Remark
        }));

        var actionParam = new SqlParameter("@Action", "SAVE");
        var planDateParam = new SqlParameter("@PlanDate", request.PlanDate.Date);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var isHolidayParam = new SqlParameter("@IsHoliday", request.IsHoliday);
        var startTimeParam = new SqlParameter("@StartTime", (object?)request.StartTime ?? DBNull.Value);
        var endTimeParam = new SqlParameter("@EndTime", (object?)request.EndTime ?? DBNull.Value);
        var headcountParam = new SqlParameter("@Headcount", (object?)request.Headcount ?? DBNull.Value);
        var targetParam = new SqlParameter("@TargetPerPerson", (object?)request.TargetPerPerson ?? DBNull.Value);
        var remarkParam = new SqlParameter("@Remark", (object?)request.Remark ?? DBNull.Value);
        var resourcesJsonParam = new SqlParameter("@ResourcesJson", resourcesJson);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_DailyPlan_Manage @Action = @Action, @PlanDate = @PlanDate, @DivisionId = @DivisionId, @IsHoliday = @IsHoliday, @StartTime = @StartTime, @EndTime = @EndTime, @Headcount = @Headcount, @TargetPerPerson = @TargetPerPerson, @Remark = @Remark, @ResourcesJson = @ResourcesJson, @UserId = @UserId",
                    actionParam, planDateParam, divisionIdParam, isHolidayParam, startTimeParam, endTimeParam, headcountParam, targetParam, remarkParam, resourcesJsonParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    public async Task DeleteAsync(DateTime planDate, int divisionId, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var planDateParam = new SqlParameter("@PlanDate", planDate.Date);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var userIdParam = new SqlParameter("@UserId", userId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_DailyPlan_Manage @Action = @Action, @PlanDate = @PlanDate, @DivisionId = @DivisionId, @UserId = @UserId",
            actionParam, planDateParam, divisionIdParam, userIdParam);
    }

    public async Task<(bool Success, string Error, int CopiedCount)> CopyAsync(CopyDailyPlanRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "COPY_FROM_DATE");
        var sourceDateParam = new SqlParameter("@SourceDate", request.SourceDate.Date);
        var targetDateParam = new SqlParameter("@TargetDate", request.TargetDate.Date);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_DailyPlan_Manage @Action = @Action, @SourceDate = @SourceDate, @TargetDate = @TargetDate, @UserId = @UserId",
                    actionParam, sourceDateParam, targetDateParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    public async Task<List<DailyPlanDateSummaryDto>> GetDatesAsync(DateTime fromDate, DateTime toDate)
    {
        var fromParam = new SqlParameter("@FromDate", fromDate.Date);
        var toParam = new SqlParameter("@ToDate", toDate.Date);

        return await _db.Database
            .SqlQueryRaw<DailyPlanDateSummaryDto>(
                "EXEC SIS_DailyPlan_ListDates @FromDate = @FromDate, @ToDate = @ToDate",
                fromParam, toParam)
            .ToListAsync();
    }
}

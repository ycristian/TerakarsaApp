using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Dashboards;

namespace TerakarsaApp.API.Services;

// Kiosk (X-Dashboard-Token, tanpa JWT) -- murni read-only, tidak menulis apa pun ke
// tabel manapun selain TOUCH last_seen_at (di RequireDashboardTokenAttribute, terpisah
// dari service ini).
public class DashboardService
{
    private readonly AppDbContext _db;

    public DashboardService(AppDbContext db)
    {
        _db = db;
    }

    // SIS_Dashboard_TargetHarian mengembalikan 3 result set (header, divisi, resource) --
    // EF Core SqlQueryRaw hanya mendukung satu result set, jadi pakai SqlCommand mentah +
    // reader.NextResultAsync() (pola sama dengan WorkScheduleService.GetDefaultsAsync).
    public async Task<DashboardTargetHarianResult> GetTargetHarianAsync(DateTime planDate)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Dashboard_TargetHarian";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@PlanDate", planDate.Date));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new DashboardTargetHarianResult();

            if (await reader.ReadAsync())
            {
                result.Header = new DashboardHeaderDto
                {
                    PlanDate = reader.GetDateTime(reader.GetOrdinal("PlanDate")),
                    ServerTime = reader.GetDateTime(reader.GetOrdinal("ServerTime")),
                    TotalDivision = reader.GetInt32(reader.GetOrdinal("TotalDivision")),
                    PlannedDivision = reader.GetInt32(reader.GetOrdinal("PlannedDivision")),
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Divisions.Add(new DashboardDivisionDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    DashboardMode = reader.GetString(reader.GetOrdinal("DashboardMode")),
                    HasPlan = reader.GetBoolean(reader.GetOrdinal("HasPlan")),
                    IsHoliday = reader.GetBoolean(reader.GetOrdinal("IsHoliday")),
                    HasTarget = reader.GetBoolean(reader.GetOrdinal("HasTarget")),
                    StartTime = GetNullableTimeSpan(reader, "StartTime"),
                    EndTime = GetNullableTimeSpan(reader, "EndTime"),
                    Headcount = GetNullableInt32(reader, "Headcount"),
                    TargetPerPerson = GetNullableInt32(reader, "TargetPerPerson"),
                    TargetTotal = GetNullableInt32(reader, "TargetTotal"),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyReject = reader.GetInt32(reader.GetOrdinal("QtyReject")),
                    Wip = reader.GetInt32(reader.GetOrdinal("Wip")),
                    Transit = reader.GetInt32(reader.GetOrdinal("Transit")),
                    EffectiveMinutesTotal = GetNullableInt32(reader, "EffectiveMinutesTotal"),
                    EffectiveMinutesElapsed = GetNullableInt32(reader, "EffectiveMinutesElapsed"),
                    ExpectedPercent = GetNullableDouble(reader, "ExpectedPercent"),
                    ActualPercent = GetNullableDouble(reader, "ActualPercent"),
                    DiffQty = GetNullableInt32(reader, "DiffQty"),
                    DiffPercent = GetNullableDouble(reader, "DiffPercent"),
                    RemainingQty = GetNullableInt32(reader, "RemainingQty"),
                    OutputPerPersonPerHour = GetNullableDouble(reader, "OutputPerPersonPerHour"),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Resources.Add(new DashboardResourceDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    ResourceId = reader.GetInt32(reader.GetOrdinal("ResourceId")),
                    ResourceName = reader.GetString(reader.GetOrdinal("ResourceName")),
                    HasPlan = reader.GetBoolean(reader.GetOrdinal("HasPlan")),
                    IsHoliday = reader.GetBoolean(reader.GetOrdinal("IsHoliday")),
                    HasTarget = reader.GetBoolean(reader.GetOrdinal("HasTarget")),
                    HasTimeOverride = reader.GetBoolean(reader.GetOrdinal("HasTimeOverride")),
                    StartTime = GetNullableTimeSpan(reader, "StartTime"),
                    EndTime = GetNullableTimeSpan(reader, "EndTime"),
                    Headcount = GetNullableInt32(reader, "Headcount"),
                    TargetPerPerson = GetNullableInt32(reader, "TargetPerPerson"),
                    TargetTotal = GetNullableInt32(reader, "TargetTotal"),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyReject = reader.GetInt32(reader.GetOrdinal("QtyReject")),
                    Wip = reader.GetInt32(reader.GetOrdinal("Wip")),
                    EffectiveMinutesTotal = GetNullableInt32(reader, "EffectiveMinutesTotal"),
                    EffectiveMinutesElapsed = GetNullableInt32(reader, "EffectiveMinutesElapsed"),
                    ExpectedPercent = GetNullableDouble(reader, "ExpectedPercent"),
                    ActualPercent = GetNullableDouble(reader, "ActualPercent"),
                    DiffQty = GetNullableInt32(reader, "DiffQty"),
                    DiffPercent = GetNullableDouble(reader, "DiffPercent"),
                    RemainingQty = GetNullableInt32(reader, "RemainingQty"),
                    OutputPerPersonPerHour = GetNullableDouble(reader, "OutputPerPersonPerHour"),
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    private static int? GetNullableInt32(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetInt32(ordinal);
    }

    private static double? GetNullableDouble(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDouble(ordinal);
    }

    private static TimeSpan? GetNullableTimeSpan(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetTimeSpan(ordinal);
    }
}

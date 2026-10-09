using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Services;

// Prompt 58: absensi + pengelolaan pegawai dari perangkat stasiun. Dipakai HANYA oleh
// StationDeviceController (token perangkat) -- divisi selalu dari token, line dari operator
// sesi, jadi service ini selalu menerima keduanya sebagai argumen terpisah dan tidak pernah
// membacanya dari request body.
//
// SIS_StationAttendance_List/_Recap mengembalikan beberapa result set, jadi dibaca dengan
// SqlCommand mentah + reader.NextResultAsync() (pola sama dengan DailyPlanService.GetByDateAsync).
public class StationAttendanceService
{
    private readonly AppDbContext _db;

    public StationAttendanceService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<StationAttendanceListResult> GetListAsync(int divisionId, int resourceId, DateTime attendanceDate)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_StationAttendance_List";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@DivisionId", divisionId));
            cmd.Parameters.Add(new SqlParameter("@ResourceId", resourceId));
            cmd.Parameters.Add(new SqlParameter("@AttendanceDate", attendanceDate.Date));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new StationAttendanceListResult();

            while (await reader.ReadAsync())
            {
                result.Rows.Add(new StationAttendanceRowDto
                {
                    EmployeeId = reader.GetInt32(reader.GetOrdinal("EmployeeId")),
                    EmployeeCode = GetNullableString(reader, "EmployeeCode"),
                    EmployeeName = reader.GetString(reader.GetOrdinal("EmployeeName")),
                    PositionName = reader.GetString(reader.GetOrdinal("PositionName")),
                    IsActive = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    AttendanceId = GetNullableInt(reader, "AttendanceId"),
                    Status = GetNullableString(reader, "Status"),
                    CheckIn = GetNullableTime(reader, "CheckIn"),
                    CheckOut = GetNullableTime(reader, "CheckOut"),
                    Note = GetNullableString(reader, "Note"),
                    Source = GetNullableString(reader, "Source"),
                    IsLate = reader.GetBoolean(reader.GetOrdinal("IsLate")),
                    LateMinutes = reader.GetInt32(reader.GetOrdinal("LateMinutes")),
                });
            }

            await reader.NextResultAsync();
            if (await reader.ReadAsync())
            {
                result.Schedule = new StationAttendanceScheduleDto
                {
                    IsWorkingDay = reader.GetBoolean(reader.GetOrdinal("IsWorkingDay")),
                    StartTime = GetNullableTime(reader, "StartTime"),
                    EndTime = GetNullableTime(reader, "EndTime"),
                    HadirCount = GetIntOrZero(reader, "HadirCount"),
                    IzinCount = GetIntOrZero(reader, "IzinCount"),
                    SakitCount = GetIntOrZero(reader, "SakitCount"),
                    AlpaCount = GetIntOrZero(reader, "AlpaCount"),
                    CutiCount = GetIntOrZero(reader, "CutiCount"),
                    BelumCount = GetIntOrZero(reader, "BelumCount"),
                    TelatCount = GetIntOrZero(reader, "TelatCount"),
                    TotalCount = GetIntOrZero(reader, "TotalCount"),
                };
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // payrollPeriodId NULL = periode absen berjalan (ditentukan SP).
    public async Task<StationAttendanceRecapResult> GetRecapAsync(int divisionId, int resourceId, int? payrollPeriodId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_StationAttendance_Recap";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@DivisionId", divisionId));
            cmd.Parameters.Add(new SqlParameter("@ResourceId", resourceId));
            cmd.Parameters.Add(new SqlParameter("@PayrollPeriodId", (object?)payrollPeriodId ?? DBNull.Value));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new StationAttendanceRecapResult();

            while (await reader.ReadAsync())
            {
                result.Dates.Add(new StationAttendanceRecapDateDto
                {
                    AttendanceDate = reader.GetDateTime(reader.GetOrdinal("AttendanceDate")),
                    IsWorkingDay = reader.GetBoolean(reader.GetOrdinal("IsWorkingDay")),
                    StartTime = GetNullableTime(reader, "StartTime"),
                    EndTime = GetNullableTime(reader, "EndTime"),
                    IsToday = reader.GetBoolean(reader.GetOrdinal("IsToday")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Employees.Add(new StationAttendanceRecapEmployeeDto
                {
                    EmployeeId = reader.GetInt32(reader.GetOrdinal("EmployeeId")),
                    EmployeeName = reader.GetString(reader.GetOrdinal("EmployeeName")),
                    PositionName = reader.GetString(reader.GetOrdinal("PositionName")),
                    IsActive = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    HadirCount = reader.GetInt32(reader.GetOrdinal("HadirCount")),
                    WorkingDayCount = reader.GetInt32(reader.GetOrdinal("WorkingDayCount")),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Cells.Add(new StationAttendanceRecapCellDto
                {
                    EmployeeId = reader.GetInt32(reader.GetOrdinal("EmployeeId")),
                    AttendanceDate = reader.GetDateTime(reader.GetOrdinal("AttendanceDate")),
                    Code = reader.GetString(reader.GetOrdinal("Code")),
                });
            }

            await reader.NextResultAsync();
            if (await reader.ReadAsync())
            {
                result.Summary = new StationAttendanceRecapSummaryDto
                {
                    AttendancePercent = reader.GetInt32(reader.GetOrdinal("AttendancePercent")),
                    TelatCount = reader.GetInt32(reader.GetOrdinal("TelatCount")),
                    AlpaCount = reader.GetInt32(reader.GetOrdinal("AlpaCount")),
                    BelumCount = reader.GetInt32(reader.GetOrdinal("BelumCount")),
                    WorkingDayCount = reader.GetInt32(reader.GetOrdinal("WorkingDayCount")),
                    StartDate = reader.GetDateTime(reader.GetOrdinal("StartDate")),
                    EndDate = reader.GetDateTime(reader.GetOrdinal("EndDate")),
                    PayrollPeriodId = GetNullableInt(reader, "PayrollPeriodId"),
                    PeriodCode = GetNullableString(reader, "PeriodCode"),
                };
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // Dropdown periode di sub-tab Rekap -- tidak terikat divisi/line (daftar periode gajian).
    public async Task<List<StationAttendancePeriodDto>> GetPeriodsAsync()
    {
        return await _db.Database
            .SqlQueryRaw<StationAttendancePeriodDto>("EXEC SIS_StationAttendance_Periods")
            .ToListAsync();
    }

    public async Task<List<StationAttendancePendingDateDto>> GetPendingDatesAsync(int divisionId, int resourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);

        return await _db.Database
            .SqlQueryRaw<StationAttendancePendingDateDto>(
                "EXEC SIS_StationAttendance_PendingDates @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
            .ToListAsync();
    }

    public async Task<(bool Success, string Error)> SaveAsync(
        StationAttendanceSaveRequest request, int resourceId, int stationId, int userId)
    {
        // Jam dikirim apa adanya sebagai teks "HH:mm" -- SP yang meng-TRY_CONVERT ke TIME(0)
        // dan memaksa NULL untuk status selain Hadir.
        var itemsJson = JsonSerializer.Serialize(request.Items.Select(i => new
        {
            employeeId = i.EmployeeId,
            status = i.Status,
            checkIn = i.CheckIn,
            checkOut = i.CheckOut,
            note = i.Note
        }));

        var actionParam = new SqlParameter("@Action", "SAVE");
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);
        var stationIdParam = new SqlParameter("@StationId", stationId);
        var dateParam = new SqlParameter("@AttendanceDate", request.AttendanceDate.Date);
        var itemsParam = new SqlParameter("@ItemsJson", itemsJson);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_StationAttendance_Manage @Action = @Action, @ResourceId = @ResourceId, @StationId = @StationId, @AttendanceDate = @AttendanceDate, @ItemsJson = @ItemsJson, @UserId = @UserId",
                actionParam, resourceIdParam, stationIdParam, dateParam, itemsParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<StationEmployeeListResult> GetEmployeesAsync(int resourceId, bool isActive, string? search)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_StationEmployee_List";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@ResourceId", resourceId));
            cmd.Parameters.Add(new SqlParameter("@IsActive", isActive));
            cmd.Parameters.Add(new SqlParameter("@Search", (object?)search ?? DBNull.Value));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new StationEmployeeListResult();

            while (await reader.ReadAsync())
            {
                result.Items.Add(new StationEmployeeDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    EmployeeCode = GetNullableString(reader, "EmployeeCode"),
                    EmployeeName = reader.GetString(reader.GetOrdinal("EmployeeName")),
                    PositionId = reader.GetInt32(reader.GetOrdinal("PositionId")),
                    PositionName = reader.GetString(reader.GetOrdinal("PositionName")),
                    PhoneNo = GetNullableString(reader, "PhoneNo"),
                    IsActive = reader.GetBoolean(reader.GetOrdinal("IsActive")),
                    JoinDate = GetNullableDate(reader, "JoinDate"),
                    InactiveDate = GetNullableDate(reader, "InactiveDate"),
                    InactiveReason = GetNullableString(reader, "InactiveReason"),
                });
            }

            await reader.NextResultAsync();
            if (await reader.ReadAsync())
            {
                result.ActiveCount = reader.GetInt32(reader.GetOrdinal("ActiveCount"));
                result.InactiveCount = reader.GetInt32(reader.GetOrdinal("InactiveCount"));
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<(bool Success, string Error)> CreateEmployeeAsync(
        StationEmployeeCreateRequest request, int divisionId, int resourceId, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);
        var nameParam = new SqlParameter("@EmployeeName", request.EmployeeName);
        var phoneParam = new SqlParameter("@PhoneNo", (object?)request.PhoneNo ?? DBNull.Value);
        var positionIdParam = new SqlParameter("@PositionId", request.PositionId);
        // NULL = hari ini (diisi SP).
        var joinDateParam = new SqlParameter("@JoinDate", (object?)request.JoinDate?.Date ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_StationEmployee_Manage @Action = @Action, @DivisionId = @DivisionId, @ResourceId = @ResourceId, @EmployeeName = @EmployeeName, @PhoneNo = @PhoneNo, @PositionId = @PositionId, @JoinDate = @JoinDate, @UserId = @UserId",
                actionParam, divisionIdParam, resourceIdParam, nameParam, phoneParam, positionIdParam, joinDateParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            // Pesan PHONE_ACTIVE|/PHONE_INACTIVE| diteruskan apa adanya -- client yang
            // mengubahnya jadi kalimat + tawaran "Aktifkan lagi?".
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateEmployeeAsync(
        int employeeId, StationEmployeeUpdateRequest request, int divisionId, int resourceId, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", employeeId);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);
        var nameParam = new SqlParameter("@EmployeeName", request.EmployeeName);
        var phoneParam = new SqlParameter("@PhoneNo", (object?)request.PhoneNo ?? DBNull.Value);
        var positionIdParam = new SqlParameter("@PositionId", request.PositionId);
        // NULL = hari ini (diisi SP).
        var joinDateParam = new SqlParameter("@JoinDate", (object?)request.JoinDate?.Date ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_StationEmployee_Manage @Action = @Action, @Id = @Id, @DivisionId = @DivisionId, @ResourceId = @ResourceId, @EmployeeName = @EmployeeName, @PhoneNo = @PhoneNo, @PositionId = @PositionId, @JoinDate = @JoinDate, @UserId = @UserId",
                actionParam, idParam, divisionIdParam, resourceIdParam, nameParam, phoneParam, positionIdParam, joinDateParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> SetEmployeeInactiveAsync(
        int employeeId, StationEmployeeInactiveRequest request, int divisionId, int resourceId, int userId)
    {
        var actionParam = new SqlParameter("@Action", "SETINACTIVE");
        var idParam = new SqlParameter("@Id", employeeId);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);
        var inactiveDateParam = new SqlParameter("@InactiveDate", request.InactiveDate.Date);
        var reasonParam = new SqlParameter("@InactiveReason", (object?)request.InactiveReason ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_StationEmployee_Manage @Action = @Action, @Id = @Id, @DivisionId = @DivisionId, @ResourceId = @ResourceId, @InactiveDate = @InactiveDate, @InactiveReason = @InactiveReason, @UserId = @UserId",
                actionParam, idParam, divisionIdParam, resourceIdParam, inactiveDateParam, reasonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> ReactivateEmployeeAsync(
        int employeeId, int divisionId, int resourceId, int userId)
    {
        var actionParam = new SqlParameter("@Action", "REACTIVATE");
        var idParam = new SqlParameter("@Id", employeeId);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_StationEmployee_Manage @Action = @Action, @Id = @Id, @DivisionId = @DivisionId, @ResourceId = @ResourceId, @UserId = @UserId",
                actionParam, idParam, divisionIdParam, resourceIdParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    private static string? GetNullableString(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }

    private static int? GetNullableInt(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetInt32(ordinal);
    }

    private static TimeSpan? GetNullableTime(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetTimeSpan(ordinal);
    }

    private static DateTime? GetNullableDate(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }

    // Ringkasan dihitung dengan SUM() tanpa GROUP BY: tanpa pegawai sama sekali hasilnya NULL.
    private static int GetIntOrZero(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? 0 : reader.GetInt32(ordinal);
    }
}

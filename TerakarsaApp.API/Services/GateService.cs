using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.API.Services;

// ApiKey dicocokkan oleh RequireGateApiKeyAttribute terhadap header X-Gate-Api-Key yang
// dikirim TerakarsaApp.GateApp.
public class GateServiceOptions
{
    public string ApiKey { get; set; } = string.Empty;
}

// UserId dari sql/seed_70_attendance_module.sql (user 'gate_system'), dipakai sebagai
// created_by/updated_by untuk semua mutasi dari endpoint gate (tidak ada JWT di sana).
// Pelaku sebenarnya (satpam) tercatat di kolom *_by_employee_id.
public class GateOptions
{
    public int SystemUserId { get; set; }
}

// Prompt 70: seluruh keputusan masuk/pulang ada di SIS_Gate_Tap, BUKAN di service ini dan bukan
// di GateApp. Service ini hanya meneruskan parameter dan memetakan result set.
//
// SIS_Gate_CardSync mengembalikan tiga result set, jadi dibaca dengan SqlCommand mentah +
// reader.NextResultAsync() (pola sama dengan StationAttendanceService.GetListAsync).
public class GateService
{
    private readonly AppDbContext _db;

    public GateService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<GateCardSyncResult> GetCardSyncAsync()
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Gate_CardSync";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new GateCardSyncResult();

            while (await reader.ReadAsync())
            {
                result.Cards.Add(new GateCardDto
                {
                    CardUid = reader.GetString(reader.GetOrdinal("CardUid")),
                    CardType = reader.GetString(reader.GetOrdinal("CardType")),
                    EmployeeId = reader.GetInt32(reader.GetOrdinal("EmployeeId")),
                    EmployeeName = reader.GetString(reader.GetOrdinal("EmployeeName")),
                    EmployeeCode = GetNullableString(reader, "EmployeeCode"),
                    PositionName = reader.GetString(reader.GetOrdinal("PositionName")),
                    IsGateOperator = reader.GetBoolean(reader.GetOrdinal("IsGateOperator")),
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    ResourceName = GetNullableString(reader, "ResourceName"),
                    ColorHex = GetNullableString(reader, "ColorHex"),
                    StartTime = GetNullableTime(reader, "StartTime"),
                });
            }

            await reader.NextResultAsync();

            while (await reader.ReadAsync())
            {
                result.Employees.Add(new GateEmployeeDto
                {
                    EmployeeId = reader.GetInt32(reader.GetOrdinal("EmployeeId")),
                    EmployeeName = reader.GetString(reader.GetOrdinal("EmployeeName")),
                    EmployeeCode = GetNullableString(reader, "EmployeeCode"),
                    Phone = GetNullableString(reader, "Phone"),
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    PositionName = reader.GetString(reader.GetOrdinal("PositionName")),
                    ResourceId = GetNullableInt(reader, "ResourceId"),
                    ResourceName = GetNullableString(reader, "ResourceName"),
                    ColorHex = GetNullableString(reader, "ColorHex"),
                    HasActiveCard = reader.GetBoolean(reader.GetOrdinal("HasActiveCard")),
                });
            }

            await reader.NextResultAsync();

            if (await reader.ReadAsync())
            {
                result.ServerTime = reader.GetDateTime(reader.GetOrdinal("ServerTime"));
                result.ActiveEmployeeCount = reader.GetInt32(reader.GetOrdinal("ActiveEmployeeCount"));
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // Satu tap. Dipanggil berurutan oleh ProcessTapsAsync -- satu tap gagal TIDAK boleh
    // membatalkan tap lain, jadi exception-nya ditangkap di sana, bukan di sini.
    public async Task<GateTapResultDto> ProcessTapAsync(GateTapRequest tap, string gateCode, int systemUserId)
    {
        var parameters = new[]
        {
            new SqlParameter("@TapUid", tap.TapUid),
            new SqlParameter("@CardUid", tap.CardUid ?? string.Empty),
            new SqlParameter("@TappedAt", tap.TappedAt),
            new SqlParameter("@GateCode", gateCode),
            new SqlParameter("@ConfirmAction", (object?)tap.ConfirmAction ?? DBNull.Value),
            new SqlParameter("@IsOfflineReplay", tap.IsOfflineReplay),
            new SqlParameter("@UserId", systemUserId),
        };

        var rows = await _db.Database
            .SqlQueryRaw<GateTapResultDto>(
                "EXEC SIS_Gate_Tap @TapUid = @TapUid, @CardUid = @CardUid, @TappedAt = @TappedAt, @GateCode = @GateCode, @ConfirmAction = @ConfirmAction, @IsOfflineReplay = @IsOfflineReplay, @UserId = @UserId",
                parameters)
            .ToListAsync();

        return rows.FirstOrDefault() ?? new GateTapResultDto
        {
            ResultCode = GateResultCodes.UnknownCard,
            CardUid = tap.CardUid,
            Message = "Tap tidak dapat diproses."
        };
    }

    // Tap offline diproses BERURUTAN menurut tapped_at: sesi dibangun dari urutan waktu tap
    // asli, jadi urutan kirim tidak boleh menentukan hasil. Urutan response tetap sama dengan
    // urutan input supaya GateApp bisa memetakan hasil ke baris antriannya.
    public async Task<List<GateTapResultDto>> ProcessTapsAsync(List<GateTapRequest> taps, string gateCode, int systemUserId)
    {
        var results = new GateTapResultDto[taps.Count];
        var ordered = taps
            .Select((tap, index) => (tap, index))
            .OrderBy(x => x.tap.TappedAt)
            .ToList();

        foreach (var (tap, index) in ordered)
        {
            try
            {
                results[index] = await ProcessTapAsync(tap, gateCode, systemUserId);
            }
            catch (SqlException ex)
            {
                // Satu tap gagal tidak membatalkan tap lain -- GateApp menyimpan barisnya di
                // antrian dan mencoba lagi siklus berikutnya.
                results[index] = new GateTapResultDto
                {
                    ResultCode = "GAGAL",
                    CardUid = tap.CardUid,
                    Message = ex.Message
                };
            }
        }

        return results.ToList();
    }

    public async Task<GateCountsDto> GetCountsAsync(string? gateCode, DateTime? atDate)
    {
        var gateCodeParam = new SqlParameter("@GateCode", (object?)gateCode ?? DBNull.Value);
        var atDateParam = new SqlParameter("@AtDate", (object?)atDate?.Date ?? DBNull.Value);

        var rows = await _db.Database
            .SqlQueryRaw<GateCountsDto>(
                "EXEC SIS_Gate_Counts @GateCode = @GateCode, @AtDate = @AtDate",
                gateCodeParam, atDateParam)
            .ToListAsync();

        return rows.FirstOrDefault() ?? new GateCountsDto();
    }

    public async Task<List<GatePendingRowDto>> GetPendingAsync(string mode)
    {
        var modeParam = new SqlParameter("@Mode", mode);

        return await _db.Database
            .SqlQueryRaw<GatePendingRowDto>("EXEC SIS_Gate_Pending @Mode = @Mode", modeParam)
            .ToListAsync();
    }

    public async Task<(bool Success, string Error, GateRegisterCardResult? Result)> RegisterCardAsync(
        GateRegisterCardRequest request, int systemUserId)
    {
        var parameters = new[]
        {
            new SqlParameter("@EmployeeId", request.EmployeeId),
            new SqlParameter("@CardUid", request.CardUid ?? string.Empty),
            new SqlParameter("@CardType", request.CardType ?? string.Empty),
            new SqlParameter("@DeactivateOldCards", request.DeactivateOldCards),
            new SqlParameter("@OperatorEmployeeId", request.OperatorEmployeeId),
            new SqlParameter("@UserId", systemUserId),
        };

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<GateRegisterCardResult>(
                    "EXEC SIS_Gate_RegisterCard @EmployeeId = @EmployeeId, @CardUid = @CardUid, @CardType = @CardType, @DeactivateOldCards = @DeactivateOldCards, @OperatorEmployeeId = @OperatorEmployeeId, @UserId = @UserId",
                    parameters)
                .ToListAsync();

            return (true, string.Empty, rows.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error)> UpdateEmployeeAsync(
        GateUpdateEmployeeRequest request, int systemUserId)
    {
        var parameters = new[]
        {
            new SqlParameter("@EmployeeId", request.EmployeeId),
            new SqlParameter("@EmployeeName", request.EmployeeName ?? string.Empty),
            new SqlParameter("@Phone", (object?)request.Phone ?? DBNull.Value),
            new SqlParameter("@OperatorEmployeeId", request.OperatorEmployeeId),
            new SqlParameter("@UserId", systemUserId),
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Gate_UpdateEmployee @EmployeeId = @EmployeeId, @EmployeeName = @EmployeeName, @Phone = @Phone, @OperatorEmployeeId = @OperatorEmployeeId, @UserId = @UserId",
                parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> CancelSessionAsync(
        GateCancelSessionRequest request, int systemUserId)
    {
        var parameters = new[]
        {
            new SqlParameter("@SessionId", request.SessionId),
            new SqlParameter("@Reason", request.Reason ?? string.Empty),
            new SqlParameter("@OperatorEmployeeId", request.OperatorEmployeeId),
            new SqlParameter("@UserId", systemUserId),
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Gate_CancelSession @SessionId = @SessionId, @Reason = @Reason, @OperatorEmployeeId = @OperatorEmployeeId, @UserId = @UserId",
                parameters);
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
}

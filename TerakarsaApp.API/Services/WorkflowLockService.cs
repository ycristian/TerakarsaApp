using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Payroll;
using TerakarsaApp.Shared.UnlockRequests;

namespace TerakarsaApp.API.Services;

// Prompt 55/56/57: lock baris article_workflow_logs + pengajuan unlock (stasiun) + daftar/detail
// & keputusan pengajuan (admin, module UNLOCK_REQUEST).
// Semua aturan (baris milik divisi ini, belum di-lock, periode belum final, batas periode ke
// depan, alasan minimal 5 karakter, dst) ditegakkan di SP -- service ini hanya meneruskan
// parameter dan mengembalikan pesan error SP APA ADANYA supaya prefix seperti 'LOCKED|'
// sampai ke client tanpa diubah. Lihat sql/sp_WorkflowLock_Manage.sql,
// sql/sp_UnlockRequest_Manage.sql, sql/sp_PayrollPeriod_Manage.sql.
public class WorkflowLockService
{
    private readonly AppDbContext _db;

    public WorkflowLockService(AppDbContext db)
    {
        _db = db;
    }

    // Dropdown "Periode Gajian" pada modal LOCK. @DefaultAt = created_at TERBARU di antara
    // baris yang dipilih operator (lihat SIS_PayrollPeriod_Options).
    public async Task<List<PayrollPeriodOptionDto>> GetPayrollPeriodOptionsAsync(DateTime? defaultAt)
    {
        var defaultAtParam = new SqlParameter("@DefaultAt", (object?)defaultAt ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<PayrollPeriodOptionDto>(
                "EXEC SIS_PayrollPeriod_Options @DefaultAt = @DefaultAt",
                defaultAtParam)
            .ToListAsync();
    }

    // Prompt 83: satu lock menampung DUA sumber baris -- article_workflow_logs dan
    // manual_outputs. manualOutputIds boleh kosong (SP menolak kalau KEDUANYA kosong).
    public async Task<(bool Success, string Error)> LockAsync(
        IEnumerable<int> workflowLogIds, IEnumerable<int> manualOutputIds, int payrollPeriodId,
        int divisionId, int? stationId, int resourceId, int userId)
    {
        var csv = string.Join(",", workflowLogIds.Distinct());
        var manualCsv = string.Join(",", manualOutputIds.Distinct());

        var parameters = new[]
        {
            new SqlParameter("@Action", "LOCK"),
            new SqlParameter("@WorkflowLogIds", csv),
            new SqlParameter("@ManualOutputIds", manualCsv),
            new SqlParameter("@DivisionId", divisionId),
            new SqlParameter("@StationId", (object?)stationId ?? DBNull.Value),
            new SqlParameter("@ResourceId", resourceId),
            new SqlParameter("@PayrollPeriodId", payrollPeriodId),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowLock_Manage @Action = @Action, @WorkflowLogIds = @WorkflowLogIds, " +
                "@ManualOutputIds = @ManualOutputIds, " +
                "@DivisionId = @DivisionId, @StationId = @StationId, @ResourceId = @ResourceId, " +
                "@PayrollPeriodId = @PayrollPeriodId, @UserId = @UserId",
                parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> CreateUnlockRequestAsync(
        IEnumerable<int> workflowLogIds, string reason, int divisionId, int? stationId, int resourceId, int userId)
    {
        var csv = string.Join(",", workflowLogIds.Distinct());

        var parameters = new[]
        {
            new SqlParameter("@Action", "CREATE"),
            new SqlParameter("@WorkflowLogIds", csv),
            new SqlParameter("@Reason", (object?)reason ?? DBNull.Value),
            new SqlParameter("@DivisionId", divisionId),
            new SqlParameter("@StationId", (object?)stationId ?? DBNull.Value),
            new SqlParameter("@ResourceId", resourceId),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_UnlockRequest_Manage @Action = @Action, @WorkflowLogIds = @WorkflowLogIds, " +
                "@Reason = @Reason, @DivisionId = @DivisionId, @StationId = @StationId, " +
                "@ResourceId = @ResourceId, @UserId = @UserId",
                parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // ------------------------------------------------------------------
    // Prompt 57 -- sisi admin (module UNLOCK_REQUEST).
    // ------------------------------------------------------------------

    public async Task<List<UnlockRequestListItemDto>> ListAsync(
        string? state, int? divisionId, DateTime? dateFrom, DateTime? dateTo)
    {
        var parameters = new[]
        {
            new SqlParameter("@State", (object?)state ?? "PENDING"),
            new SqlParameter("@DivisionId", (object?)divisionId ?? DBNull.Value),
            new SqlParameter("@DateFrom", (object?)dateFrom?.Date ?? DBNull.Value),
            new SqlParameter("@DateTo", (object?)dateTo?.Date ?? DBNull.Value)
        };

        return await _db.Database
            .SqlQueryRaw<UnlockRequestListItemDto>(
                "EXEC SIS_UnlockRequest_List @State = @State, @DivisionId = @DivisionId, " +
                "@DateFrom = @DateFrom, @DateTo = @DateTo",
                parameters)
            .ToListAsync();
    }

    // SIS_UnlockRequest_Detail mengembalikan 2 result set (header + baris), jadi EF Core
    // SqlQueryRaw tidak cukup -- pola sama dengan ArticleWorkflowService.ExecutePreviewAsync.
    public async Task<(UnlockRequestDetailDto? Result, string? Error)> GetDetailAsync(int requestId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_UnlockRequest_Detail";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@RequestId", requestId));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new UnlockRequestDetailDto();

            if (await reader.ReadAsync())
            {
                result.Header = new UnlockRequestListItemDto
                {
                    RequestId = reader.GetInt32(reader.GetOrdinal("RequestId")),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    StationName = GetNullableString(reader, "StationName"),
                    RequestedByResourceName = GetNullableString(reader, "RequestedByResourceName"),
                    Reason = reader.GetString(reader.GetOrdinal("Reason")),
                    JumlahBaris = reader.GetInt32(reader.GetOrdinal("JumlahBaris")),
                    TotalQty = reader.GetInt32(reader.GetOrdinal("TotalQty")),
                    State = reader.GetString(reader.GetOrdinal("State")),
                    DecidedAt = GetNullableDateTime(reader, "DecidedAt"),
                    DecidedByName = GetNullableString(reader, "DecidedByName"),
                    AdminNote = GetNullableString(reader, "AdminNote"),
                    PeriodeFinal = reader.GetBoolean(reader.GetOrdinal("PeriodeFinal"))
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Items.Add(new UnlockRequestItemDto
                {
                    RequestItemId = reader.GetInt32(reader.GetOrdinal("RequestItemId")),
                    WorkflowLogId = reader.GetInt32(reader.GetOrdinal("WorkflowLogId")),
                    ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                    NoPo = GetNullableString(reader, "NoPo"),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    Style = GetNullableString(reader, "Style"),
                    Color = GetNullableString(reader, "Color"),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    BundleId = GetNullableInt(reader, "BundleId"),
                    BundleNo = GetNullableInt(reader, "BundleNo"),
                    BundleLetter = GetNullableString(reader, "BundleLetter"),
                    Serial = GetNullableString(reader, "Serial"),
                    SizeName = GetNullableString(reader, "SizeName"),
                    PenjahitName = GetNullableString(reader, "PenjahitName"),
                    PeriodeLock = reader.GetString(reader.GetOrdinal("PeriodeLock")),
                    LockedAt = reader.GetDateTime(reader.GetOrdinal("LockedAt")),
                    PeriodeLockFinal = reader.GetBoolean(reader.GetOrdinal("PeriodeLockFinal")),
                    SebelumQtyOk = reader.GetInt32(reader.GetOrdinal("SebelumQtyOk")),
                    SebelumQtyRejectPrint = reader.GetInt32(reader.GetOrdinal("SebelumQtyRejectPrint")),
                    SebelumQtyRejectFabric = reader.GetInt32(reader.GetOrdinal("SebelumQtyRejectFabric")),
                    SebelumQtyRejectSewing = reader.GetInt32(reader.GetOrdinal("SebelumQtyRejectSewing")),
                    SebelumQtyRejectRework = reader.GetInt32(reader.GetOrdinal("SebelumQtyRejectRework")),
                    SebelumQtyLost = reader.GetInt32(reader.GetOrdinal("SebelumQtyLost")),
                    SebelumSizeName = GetNullableString(reader, "SebelumSizeName"),
                    SebelumResourceName = GetNullableString(reader, "SebelumResourceName"),
                    SekarangQtyOk = reader.GetInt32(reader.GetOrdinal("SekarangQtyOk")),
                    SekarangQtyRejectPrint = reader.GetInt32(reader.GetOrdinal("SekarangQtyRejectPrint")),
                    SekarangQtyRejectFabric = reader.GetInt32(reader.GetOrdinal("SekarangQtyRejectFabric")),
                    SekarangQtyRejectSewing = reader.GetInt32(reader.GetOrdinal("SekarangQtyRejectSewing")),
                    SekarangQtyRejectRework = reader.GetInt32(reader.GetOrdinal("SekarangQtyRejectRework")),
                    SekarangQtyLost = reader.GetInt32(reader.GetOrdinal("SekarangQtyLost")),
                    SekarangSizeName = GetNullableString(reader, "SekarangSizeName"),
                    SekarangResourceName = GetNullableString(reader, "SekarangResourceName"),
                    IsDeleted = reader.GetBoolean(reader.GetOrdinal("IsDeleted")),
                    LockUlangPeriode = GetNullableString(reader, "LockUlangPeriode"),
                    LockUlangLockedAt = GetNullableDateTime(reader, "LockUlangLockedAt"),
                    Berubah = reader.GetBoolean(reader.GetOrdinal("Berubah"))
                });
            }

            return (result.Header is null ? null : result, null);
        }
        catch (SqlException ex)
        {
            return (null, ex.Message);
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // APPROVE/REJECT -- seluruh aturan (pengajuan masih menunggu, periode belum final, lock item
    // belum bergeser, catatan wajib saat menolak) ditegakkan SIS_UnlockRequest_Manage.
    public async Task<(bool Success, string Error)> DecideAsync(
        int requestId, bool approve, string? adminNote, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", approve ? "APPROVE" : "REJECT"),
            new SqlParameter("@Id", requestId),
            new SqlParameter("@AdminNote", (object?)adminNote ?? DBNull.Value),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_UnlockRequest_Manage @Action = @Action, @Id = @Id, " +
                "@AdminNote = @AdminNote, @UserId = @UserId",
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
        var i = reader.GetOrdinal(column);
        return reader.IsDBNull(i) ? null : reader.GetString(i);
    }

    private static int? GetNullableInt(SqlDataReader reader, string column)
    {
        var i = reader.GetOrdinal(column);
        return reader.IsDBNull(i) ? null : reader.GetInt32(i);
    }

    private static DateTime? GetNullableDateTime(SqlDataReader reader, string column)
    {
        var i = reader.GetOrdinal(column);
        return reader.IsDBNull(i) ? null : reader.GetDateTime(i);
    }
}

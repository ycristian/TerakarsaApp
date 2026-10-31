using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Payroll;

namespace TerakarsaApp.API.Services;

// Prompt 83: Rekap Gajian admin -- isi satu periode gajian (baris LOG + MANUAL), koreksi
// harga per lock item, dan finalisasi/unfinalisasi periode.
//
// Semua aturan ditegakkan di SP: harga tidak bisa diubah kalau periode sudah final
// (SIS_LockItem_UpdatePrice), finalisasi ditolak kalau masih ada harga kosong
// (SIS_PayrollPeriod_Manage FINALIZE, pesan berprefix 'HARGA_KOSONG|' + result set berisi
// baris bermasalah). Pesan error SP diteruskan APA ADANYA.
//
// Lihat sql/sp_PayrollRekap_Select.sql, sql/sp_LockItem_Manage.sql,
// sql/sp_PayrollPeriod_Manage.sql.
public class PayrollRekapService
{
    private readonly AppDbContext _db;

    public PayrollRekapService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<PayrollRekapPeriodDto>> GetPeriodsAsync()
    {
        return await _db.Database
            .SqlQueryRaw<PayrollRekapPeriodDto>("EXEC SIS_PayrollRekap_Periods")
            .ToListAsync();
    }

    // Tiga result set: header, baris, ringkasan per resource -- dibaca dengan
    // NextResultAsync (pola sama dengan StationRekapProduksiService).
    public async Task<PayrollRekapResultDto> GetAsync(
        int payrollPeriodId, int? divisionId, int? resourceId, bool onlyMissingPrice)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_PayrollRekap_List";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@PayrollPeriodId", payrollPeriodId));
            cmd.Parameters.Add(new SqlParameter("@DivisionId", (object?)divisionId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@OnlyMissingPrice", onlyMissingPrice));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new PayrollRekapResultDto();

            // ---- 1. header ----
            if (await reader.ReadAsync())
            {
                result.Header = new PayrollRekapHeaderDto
                {
                    PayrollPeriodId = reader.GetInt32(reader.GetOrdinal("PayrollPeriodId")),
                    PeriodCode = reader.GetString(reader.GetOrdinal("PeriodCode")),
                    PeriodStart = reader.GetDateTime(reader.GetOrdinal("PeriodStart")),
                    PeriodEnd = reader.GetDateTime(reader.GetOrdinal("PeriodEnd")),
                    FinalizedAt = GetNullableDateTime(reader, "FinalizedAt"),
                    IsFinalized = reader.GetBoolean(reader.GetOrdinal("IsFinalized")),
                    FinalizedByName = GetNullableString(reader, "FinalizedByName")
                };
            }

            // ---- 2. baris ----
            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Rows.Add(new PayrollRekapRowDto
                {
                    LockItemId = reader.GetInt32(reader.GetOrdinal("LockItemId")),
                    Source = reader.GetString(reader.GetOrdinal("Source")),
                    IsManual = reader.GetBoolean(reader.GetOrdinal("IsManual")),
                    DivisionId = GetNullableInt(reader, "DivisionId"),
                    DivisionName = GetNullableString(reader, "DivisionName"),
                    ResourceId = GetNullableInt(reader, "ResourceId"),
                    ResourceName = GetNullableString(reader, "ResourceName"),
                    ArticleId = GetNullableInt(reader, "ArticleId"),
                    ArticleName = GetNullableString(reader, "ArticleName"),
                    NoPo = GetNullableString(reader, "NoPo"),
                    StepName = GetNullableString(reader, "StepName"),
                    WorkDescription = GetNullableString(reader, "WorkDescription"),
                    SizeName = GetNullableString(reader, "SizeName"),
                    Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                    RejectQty = reader.GetInt32(reader.GetOrdinal("RejectQty")),
                    UnitPrice = GetNullableDecimal(reader, "UnitPrice"),
                    Total = GetNullableDecimal(reader, "Total"),
                    IsMissingPrice = reader.GetBoolean(reader.GetOrdinal("IsMissingPrice")),
                    IsPotongan = reader.GetBoolean(reader.GetOrdinal("IsPotongan")),
                    Note = GetNullableString(reader, "Note"),
                    ManualOutputId = GetNullableInt(reader, "ManualOutputId"),
                    WorkflowLogId = GetNullableInt(reader, "WorkflowLogId")
                });
            }

            // ---- 3. ringkasan per resource ----
            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Resources.Add(new PayrollRekapResourceDto
                {
                    ResourceId = GetNullableInt(reader, "ResourceId"),
                    ResourceName = GetNullableString(reader, "ResourceName"),
                    DivisionName = GetNullableString(reader, "DivisionName"),
                    ItemCount = reader.GetInt32(reader.GetOrdinal("ItemCount")),
                    MissingPriceCount = reader.GetInt32(reader.GetOrdinal("MissingPriceCount")),
                    TotalQty = reader.GetInt32(reader.GetOrdinal("TotalQty")),
                    TotalNilai = reader.GetDecimal(reader.GetOrdinal("TotalNilai"))
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // Nilai MINUS diperbolehkan; null = kosongkan harga lagi.
    public async Task<(bool Success, string Error)> UpdateLockItemPriceAsync(
        int lockItemId, decimal? unitPrice, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@LockItemId", lockItemId),
            new SqlParameter("@UnitPrice", (object?)unitPrice ?? DBNull.Value),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_LockItem_UpdatePrice @LockItemId = @LockItemId, @UnitPrice = @UnitPrice, @UserId = @UserId",
                parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // FINALIZE mengembalikan DAFTAR baris bermasalah kalau ditolak, jadi dibaca lewat
    // reader: result set dulu (kalau ada), error SP menyusul saat reader ditutup.
    // Pesan error tetap diteruskan apa adanya (berprefix 'HARGA_KOSONG|').
    public async Task<(bool Success, string Error, List<PayrollMissingPriceRowDto> MissingRows)> FinalizeAsync(
        int payrollPeriodId, int userId)
    {
        var missing = new List<PayrollMissingPriceRowDto>();

        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_PayrollPeriod_Manage";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@Action", "FINALIZE"));
            cmd.Parameters.Add(new SqlParameter("@PayrollPeriodId", payrollPeriodId));
            cmd.Parameters.Add(new SqlParameter("@UserId", userId));

            using var reader = await cmd.ExecuteReaderAsync();

            // Result set pertama bisa berupa daftar baris bermasalah (saat ditolak) ATAU
            // konfirmasi sukses (PayrollPeriodId/PeriodCode) -- dibedakan dari kolomnya.
            var isMissingSet = reader.FieldCount > 0 && HasColumn(reader, "LockItemId");

            if (isMissingSet)
            {
                while (await reader.ReadAsync())
                {
                    missing.Add(new PayrollMissingPriceRowDto
                    {
                        LockItemId = reader.GetInt32(reader.GetOrdinal("LockItemId")),
                        Source = reader.GetString(reader.GetOrdinal("Source")),
                        ResourceName = GetNullableString(reader, "ResourceName"),
                        Description = GetNullableString(reader, "Description"),
                        Qty = reader.GetInt32(reader.GetOrdinal("Qty"))
                    });
                }
            }

            // RAISERROR setelah SELECT baru dilempar saat sisa stream dibaca.
            while (await reader.NextResultAsync()) { }

            return (true, string.Empty, missing);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, missing);
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<(bool Success, string Error)> UnfinalizeAsync(int payrollPeriodId, int userId)
    {
        var parameters = new[]
        {
            new SqlParameter("@Action", "UNFINALIZE"),
            new SqlParameter("@PayrollPeriodId", payrollPeriodId),
            new SqlParameter("@UserId", userId)
        };

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_PayrollPeriod_Manage @Action = @Action, @PayrollPeriodId = @PayrollPeriodId, @UserId = @UserId",
                parameters);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    private static bool HasColumn(SqlDataReader reader, string column)
    {
        for (var i = 0; i < reader.FieldCount; i++)
            if (string.Equals(reader.GetName(i), column, StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
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

    private static decimal? GetNullableDecimal(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDecimal(ordinal);
    }

    private static DateTime? GetNullableDateTime(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }
}

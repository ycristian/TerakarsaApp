using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Services;

// Prompt 42: tab "Rekap Produksi" di /station (menggantikan RekapPenjahitService Prompt 41) --
// lihat sql/sp_Report_RekapStruk.sql. SIS_Report_RekapStruk mengembalikan 3 result set
// (header, detail harian, WIP snapshot) -- EF Core SqlQueryRaw hanya mendukung satu result set,
// jadi di sini pakai SqlCommand mentah + reader.NextResultAsync() (pola sama dengan
// ReportBundleService.GetArticleProgressAsync).
public class RekapProduksiService
{
    private readonly AppDbContext _db;

    public RekapProduksiService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<RekapStrukResultDto> GetAsync(string level, int divisionId, int? resourceId, int? employeeId, DateTime? date)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Report_RekapStruk";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@Level", level));
            cmd.Parameters.Add(new SqlParameter("@DivisionId", divisionId));
            cmd.Parameters.Add(new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@EmployeeId", (object?)employeeId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@Date", (object?)date?.Date ?? DBNull.Value));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new RekapStrukResultDto();

            if (await reader.ReadAsync())
            {
                result.Header = new RekapStrukHeaderDto
                {
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    ResourceName = reader.IsDBNull(reader.GetOrdinal("ResourceName")) ? null : reader.GetString(reader.GetOrdinal("ResourceName")),
                    EmployeeName = reader.IsDBNull(reader.GetOrdinal("EmployeeName")) ? null : reader.GetString(reader.GetOrdinal("EmployeeName")),
                    Level = reader.GetString(reader.GetOrdinal("Level")),
                    PeriodStart = reader.GetDateTime(reader.GetOrdinal("PeriodStart")),
                    PeriodEnd = reader.GetDateTime(reader.GetOrdinal("PeriodEnd")),
                    TotalQty = reader.GetInt32(reader.GetOrdinal("TotalQty")),
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Detail.Add(ReadRow(reader, hasEventDate: true));
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Wip.Add(ReadRow(reader, hasEventDate: false));
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    private static RekapStrukRowDto ReadRow(SqlDataReader reader, bool hasEventDate)
    {
        var eventDateOrdinal = reader.GetOrdinal("EventDate");
        return new RekapStrukRowDto
        {
            EventDate = reader.IsDBNull(eventDateOrdinal) ? null : reader.GetDateTime(eventDateOrdinal),
            ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
            SizeName = reader.IsDBNull(reader.GetOrdinal("SizeName")) ? null : reader.GetString(reader.GetOrdinal("SizeName")),
            Label = reader.IsDBNull(reader.GetOrdinal("Label")) ? string.Empty : reader.GetString(reader.GetOrdinal("Label")),
            Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
            QtyRejectPrint = reader.GetInt32(reader.GetOrdinal("QtyRejectPrint")),
            QtyRejectFabric = reader.GetInt32(reader.GetOrdinal("QtyRejectFabric")),
            QtyRejectSewing = reader.GetInt32(reader.GetOrdinal("QtyRejectSewing")),
            QtyRejectRework = reader.GetInt32(reader.GetOrdinal("QtyRejectRework")),
            QtyLost = reader.GetInt32(reader.GetOrdinal("QtyLost")),
        };
    }

    public async Task<(bool Success, string Error, int PrintJobId)> PrintAsync(RekapStrukPrintRequest request, int userId)
    {
        var levelParam = new SqlParameter("@Level", request.Level);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)request.ResourceId ?? DBNull.Value);
        var employeeIdParam = new SqlParameter("@EmployeeId", (object?)request.EmployeeId ?? DBNull.Value);
        var dateParam = new SqlParameter("@Date", request.Date.Date);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_Report_RekapStrukPrint @Level = @Level, @DivisionId = @DivisionId, @ResourceId = @ResourceId, @EmployeeId = @EmployeeId, @Date = @Date, @UserId = @UserId",
                    levelParam, divisionIdParam, resourceIdParam, employeeIdParam, dateParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }
}

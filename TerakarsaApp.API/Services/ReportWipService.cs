using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.API.Services;

// Prompt 22: Dashboard WIP per Divisi & Resource -- murni read-only (SIS_Report_* di
// sql/sp_Report_DivisionWip.sql), tidak menulis apa pun ke database.
public class ReportWipService
{
    private readonly AppDbContext _db;

    public ReportWipService(AppDbContext db)
    {
        _db = db;
    }

    // SIS_Report_DivisionWip mengembalikan 2 result set (Dikerjakan, Belum diterima), masing-
    // masing dengan kolom ArticlesJson (FOR JSON PATH) -- EF Core SqlQueryRaw hanya mendukung
    // satu result set, jadi di sini pakai SqlCommand mentah + reader.NextResultAsync() (pola
    // sama dengan ReportBundleService.GetArticleProgressAsync).
    public async Task<DivisionWipSummaryDto> GetSummaryAsync()
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Report_DivisionWip";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new DivisionWipSummaryDto();

            while (await reader.ReadAsync())
            {
                result.Working.Add(new DivisionWipWorkingDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    ResourceId = reader.IsDBNull(reader.GetOrdinal("ResourceId")) ? null : reader.GetInt32(reader.GetOrdinal("ResourceId")),
                    ResourceName = reader.IsDBNull(reader.GetOrdinal("ResourceName")) ? null : reader.GetString(reader.GetOrdinal("ResourceName")),
                    BundleCount = reader.GetInt32(reader.GetOrdinal("BundleCount")),
                    TotalPcs = reader.GetInt32(reader.GetOrdinal("TotalPcs")),
                    OldestReceivedAt = reader.IsDBNull(reader.GetOrdinal("OldestReceivedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("OldestReceivedAt")),
                    Articles = ParseArticlesJson(reader, "ArticlesJson"),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Pending.Add(new DivisionWipPendingDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    BundleCount = reader.GetInt32(reader.GetOrdinal("BundleCount")),
                    TotalPcs = reader.GetInt32(reader.GetOrdinal("TotalPcs")),
                    OldestSentAt = reader.IsDBNull(reader.GetOrdinal("OldestSentAt")) ? null : reader.GetDateTime(reader.GetOrdinal("OldestSentAt")),
                    Articles = ParseArticlesJson(reader, "ArticlesJson"),
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    private static List<WipArticleSummaryDto> ParseArticlesJson(SqlDataReader reader, string columnName)
    {
        var ordinal = reader.GetOrdinal(columnName);
        if (reader.IsDBNull(ordinal)) return new();

        var json = reader.GetString(ordinal);
        return JsonSerializer.Deserialize<List<WipArticleSummaryDto>>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? new();
    }

    public async Task<(bool Success, string Error, List<DivisionWipBundleDto> Result)> GetBundlesAsync(
        int divisionId, string mode, int? resourceId, bool filterResource)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var modeParam = new SqlParameter("@Mode", mode);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var filterResourceParam = new SqlParameter("@FilterResource", filterResource);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<DivisionWipBundleDto>(
                    "EXEC SIS_Report_DivisionWipBundles @DivisionId = @DivisionId, @Mode = @Mode, @ResourceId = @ResourceId, @FilterResource = @FilterResource",
                    divisionIdParam, modeParam, resourceIdParam, filterResourceParam)
                .ToListAsync();
            return (true, string.Empty, result);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, new List<DivisionWipBundleDto>());
        }
    }
}

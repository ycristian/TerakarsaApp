using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.API.Services;

// ApiKey dicocokkan oleh RequirePrintApiKeyAttribute terhadap header X-Print-Api-Key
// yang dikirim TerakarsaApp.PrintService (Windows Worker Service).
public class PrintServiceOptions
{
    public string ApiKey { get; set; } = string.Empty;
}

public class PrintJobService
{
    private readonly AppDbContext _db;

    public PrintJobService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<PrintJobClaimedDto>> ClaimAsync(int batchSize)
    {
        var batchSizeParam = new SqlParameter("@BatchSize", batchSize);

        return await _db.Database
            .SqlQueryRaw<PrintJobClaimedDto>("EXEC SIS_PrintJob_Claim @BatchSize = @BatchSize", batchSizeParam)
            .ToListAsync();
    }

    public async Task ReportAsync(PrintJobReportRequest request)
    {
        var idParam = new SqlParameter("@PrintJobId", request.PrintJobId);
        var successParam = new SqlParameter("@Success", request.Success);
        var errorMessageParam = new SqlParameter("@ErrorMessage", (object?)request.ErrorMessage ?? DBNull.Value);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_PrintJob_Report @PrintJobId = @PrintJobId, @Success = @Success, @ErrorMessage = @ErrorMessage",
            idParam, successParam, errorMessageParam);
    }
}

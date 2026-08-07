using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Reports;

namespace TerakarsaApp.API.Services;

// Prompt 47: Modul Log Aktivitas -- murni read-only (SIS_Report_ActivityLog di
// sql/sp_Report_ActivityLog.sql), tidak menulis apa pun ke database.
public class ReportActivityLogService
{
    private readonly AppDbContext _db;

    public ReportActivityLogService(AppDbContext db)
    {
        _db = db;
    }

    private class ActivityLogCountRow
    {
        public int TotalCount { get; set; }
        public int TotalQtyOk { get; set; }
    }

    public async Task<ActivityLogPagedResult> GetPagedAsync(ActivityLogPagedRequest request)
    {
        var items = await _db.Database
            .SqlQueryRaw<ActivityLogRowDto>(
                @"EXEC SIS_Report_ActivityLog @Action = @Action, @DateFrom = @DateFrom, @DateTo = @DateTo,
                    @TimeBasis = @TimeBasis, @DivisionId = @DivisionId, @ResourceId = @ResourceId,
                    @EmployeeId = @EmployeeId, @ProjectId = @ProjectId, @SearchTerm = @SearchTerm,
                    @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn,
                    @SortDirection = @SortDirection",
                new SqlParameter("@Action", "LIST"),
                new SqlParameter("@DateFrom", request.DateFrom),
                new SqlParameter("@DateTo", request.DateTo),
                new SqlParameter("@TimeBasis", request.TimeBasis),
                new SqlParameter("@DivisionId", (object?)request.DivisionId ?? DBNull.Value),
                new SqlParameter("@ResourceId", (object?)request.ResourceId ?? DBNull.Value),
                new SqlParameter("@EmployeeId", (object?)request.EmployeeId ?? DBNull.Value),
                new SqlParameter("@ProjectId", (object?)request.ProjectId ?? DBNull.Value),
                new SqlParameter("@SearchTerm", (object?)request.SearchTerm ?? DBNull.Value),
                new SqlParameter("@PageNumber", request.PageNumber),
                new SqlParameter("@PageSize", request.PageSize),
                new SqlParameter("@SortColumn", (object?)request.SortColumn ?? DBNull.Value),
                new SqlParameter("@SortDirection", request.SortDirection))
            .ToListAsync();

        var countResult = await _db.Database
            .SqlQueryRaw<ActivityLogCountRow>(
                @"EXEC SIS_Report_ActivityLog @Action = @Action, @DateFrom = @DateFrom, @DateTo = @DateTo,
                    @TimeBasis = @TimeBasis, @DivisionId = @DivisionId, @ResourceId = @ResourceId,
                    @EmployeeId = @EmployeeId, @ProjectId = @ProjectId, @SearchTerm = @SearchTerm",
                new SqlParameter("@Action", "COUNT"),
                new SqlParameter("@DateFrom", request.DateFrom),
                new SqlParameter("@DateTo", request.DateTo),
                new SqlParameter("@TimeBasis", request.TimeBasis),
                new SqlParameter("@DivisionId", (object?)request.DivisionId ?? DBNull.Value),
                new SqlParameter("@ResourceId", (object?)request.ResourceId ?? DBNull.Value),
                new SqlParameter("@EmployeeId", (object?)request.EmployeeId ?? DBNull.Value),
                new SqlParameter("@ProjectId", (object?)request.ProjectId ?? DBNull.Value),
                new SqlParameter("@SearchTerm", (object?)request.SearchTerm ?? DBNull.Value))
            .ToListAsync();

        var counts = countResult.FirstOrDefault() ?? new ActivityLogCountRow();

        return new ActivityLogPagedResult
        {
            Items = items,
            TotalCount = counts.TotalCount,
            PageNumber = request.PageNumber,
            PageSize = request.PageSize,
            TotalQtyOk = counts.TotalQtyOk
        };
    }
}

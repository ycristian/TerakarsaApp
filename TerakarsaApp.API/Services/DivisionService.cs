using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Divisions;

namespace TerakarsaApp.API.Services;

public class DivisionService
{
    private readonly AppDbContext _db;

    public DivisionService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<DivisionPagedResult> GetPagedAsync(DivisionPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<DivisionDto>(
                "EXEC SIS_Division_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Division_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new DivisionPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<DivisionDto>> GetActiveAsync()
    {
        var result = await GetPagedAsync(new DivisionPagedRequest
        {
            PageNumber = 1,
            PageSize = 1000,
            SortColumn = "DivisionName",
            SortDirection = "asc"
        });
        return result.Items;
    }

    public async Task<DivisionDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<DivisionDto>("EXEC SIS_Division_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> CreateAsync(DivisionCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var codeParam = new SqlParameter("@DivisionCode", request.DivisionCode);
        var nameParam = new SqlParameter("@DivisionName", request.DivisionName);
        var showInDashboardParam = new SqlParameter("@ShowInDashboard", request.ShowInDashboard);
        var dashboardModeParam = new SqlParameter("@DashboardMode", request.DashboardMode);
        var dashboardSortOrderParam = new SqlParameter("@DashboardSortOrder", request.DashboardSortOrder);
        var defaultTargetParam = new SqlParameter("@DefaultTargetPerPerson", request.DefaultTargetPerPerson);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Division_Manage @Action = @Action, @DivisionCode = @DivisionCode, @DivisionName = @DivisionName, @ShowInDashboard = @ShowInDashboard, @DashboardMode = @DashboardMode, @DashboardSortOrder = @DashboardSortOrder, @DefaultTargetPerPerson = @DefaultTargetPerPerson, @UserId = @UserId",
                actionParam, codeParam, nameParam, showInDashboardParam, dashboardModeParam, dashboardSortOrderParam, defaultTargetParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(DivisionUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@DivisionCode", request.DivisionCode);
        var nameParam = new SqlParameter("@DivisionName", request.DivisionName);
        var showInDashboardParam = new SqlParameter("@ShowInDashboard", request.ShowInDashboard);
        var dashboardModeParam = new SqlParameter("@DashboardMode", request.DashboardMode);
        var dashboardSortOrderParam = new SqlParameter("@DashboardSortOrder", request.DashboardSortOrder);
        var defaultTargetParam = new SqlParameter("@DefaultTargetPerPerson", request.DefaultTargetPerPerson);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Division_Manage @Action = @Action, @Id = @Id, @DivisionCode = @DivisionCode, @DivisionName = @DivisionName, @ShowInDashboard = @ShowInDashboard, @DashboardMode = @DashboardMode, @DashboardSortOrder = @DashboardSortOrder, @DefaultTargetPerPerson = @DefaultTargetPerPerson, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, showInDashboardParam, dashboardModeParam, dashboardSortOrderParam, defaultTargetParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task DeleteAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Division_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

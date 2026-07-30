using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Employees;

namespace TerakarsaApp.API.Services;

public class EmployeeService
{
    private readonly AppDbContext _db;

    public EmployeeService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<EmployeePagedResult> GetPagedAsync(EmployeePagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<EmployeeDto>(
                "EXEC SIS_Employee_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Employee_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new EmployeePagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<EmployeeDto>> GetActiveAsync()
    {
        var result = await GetPagedAsync(new EmployeePagedRequest
        {
            PageNumber = 1,
            PageSize = 1000,
            SortColumn = "EmployeeName",
            SortDirection = "asc"
        });
        return result.Items;
    }

    // Prompt 32: dropdown "Penjahit" cascading di bawah dropdown Line/resource.
    public async Task<List<EmployeeLookupDto>> GetActiveByResourceAsync(int resourceId)
    {
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);

        return await _db.Database
            .SqlQueryRaw<EmployeeLookupDto>(
                "EXEC SIS_Employee_GetActiveByResource @ResourceId = @ResourceId",
                resourceIdParam)
            .ToListAsync();
    }

    public async Task<EmployeeDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<EmployeeDto>("EXEC SIS_Employee_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> CreateAsync(EmployeeCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var codeParam = new SqlParameter("@EmployeeCode", (object?)request.EmployeeCode ?? DBNull.Value);
        var nameParam = new SqlParameter("@EmployeeName", request.EmployeeName);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var positionIdParam = new SqlParameter("@PositionId", request.PositionId);
        var resourceIdParam = new SqlParameter("@ResourceId", request.ResourceId ?? (object)DBNull.Value);
        var joinDateParam = new SqlParameter("@JoinDate", request.JoinDate ?? (object)DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Employee_Manage @Action = @Action, @EmployeeCode = @EmployeeCode, @EmployeeName = @EmployeeName, @DivisionId = @DivisionId, @PositionId = @PositionId, @ResourceId = @ResourceId, @JoinDate = @JoinDate, @UserId = @UserId",
                actionParam, codeParam, nameParam, divisionIdParam, positionIdParam, resourceIdParam, joinDateParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(EmployeeUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@EmployeeCode", (object?)request.EmployeeCode ?? DBNull.Value);
        var nameParam = new SqlParameter("@EmployeeName", request.EmployeeName);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var positionIdParam = new SqlParameter("@PositionId", request.PositionId);
        var resourceIdParam = new SqlParameter("@ResourceId", request.ResourceId ?? (object)DBNull.Value);
        var joinDateParam = new SqlParameter("@JoinDate", request.JoinDate ?? (object)DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Employee_Manage @Action = @Action, @Id = @Id, @EmployeeCode = @EmployeeCode, @EmployeeName = @EmployeeName, @DivisionId = @DivisionId, @PositionId = @PositionId, @ResourceId = @ResourceId, @JoinDate = @JoinDate, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, divisionIdParam, positionIdParam, resourceIdParam, joinDateParam, userIdParam);
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
            "EXEC SIS_Employee_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

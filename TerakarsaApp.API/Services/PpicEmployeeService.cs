using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Employees;
using TerakarsaApp.Shared.Positions;
using TerakarsaApp.Shared.Resources;

namespace TerakarsaApp.API.Services;

// Prompt 53: layer data untuk module PPIC_EMPLOYEE -- pintu masuk mandiri terpisah dari
// EmployeeService/SIS_Employee_Manage (dipakai MASTER_EMPLOYEE). Guard cakupan PPIC
// (ppic_managed) ditegakkan di SP (SIS_PpicEmployee_*), bukan di sini -- lihat
// sql/sp_PpicEmployee_Manage.sql & sp_PpicEmployee_Select.sql.
public class PpicEmployeeService
{
    private readonly AppDbContext _db;
    // Dropdown Jabatan & Line/Resource di form PPIC -- proxy tipis ke service yang sudah ada
    // (bukan duplikasi SP), diekspos di sini supaya user PPIC_EMPLOYEE-only (tanpa module
    // MASTER_POSITION/MASTER_RESOURCE) tetap bisa isi dropdown-nya -- pola sama dengan
    // SuperAdminService.
    private readonly PositionService _positionService;
    private readonly ResourceService _resourceService;

    public PpicEmployeeService(AppDbContext db, PositionService positionService, ResourceService resourceService)
    {
        _db = db;
        _positionService = positionService;
        _resourceService = resourceService;
    }

    public Task<List<PositionDto>> GetPositionsAsync() => _positionService.GetActiveAsync();

    public Task<List<ResourceLookupDto>> GetResourcesByDivisionAsync(int divisionId) =>
        _resourceService.GetActiveByDivisionAsync(divisionId);

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
                "EXEC SIS_PpicEmployee_List @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_PpicEmployee_List @Action = @Action, @SearchTerm = @SearchTerm",
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

    public async Task<EmployeeDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<EmployeeDto>("EXEC SIS_PpicEmployee_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<List<DivisionDto>> GetPpicManagedDivisionsAsync()
    {
        return await _db.Database
            .SqlQueryRaw<DivisionDto>("EXEC SIS_Division_GetPpicManaged")
            .ToListAsync();
    }

    public async Task<string?> GetNextCodeAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        var result = await _db.Database
            .SqlQueryRaw<EmployeeNextCodeDto>("EXEC SIS_Employee_NextCode @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();

        return result.FirstOrDefault()?.SuggestedCode;
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
                "EXEC SIS_PpicEmployee_Manage @Action = @Action, @EmployeeCode = @EmployeeCode, @EmployeeName = @EmployeeName, @DivisionId = @DivisionId, @PositionId = @PositionId, @ResourceId = @ResourceId, @JoinDate = @JoinDate, @UserId = @UserId",
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
                "EXEC SIS_PpicEmployee_Manage @Action = @Action, @Id = @Id, @EmployeeCode = @EmployeeCode, @EmployeeName = @EmployeeName, @DivisionId = @DivisionId, @PositionId = @PositionId, @ResourceId = @ResourceId, @JoinDate = @JoinDate, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, divisionIdParam, positionIdParam, resourceIdParam, joinDateParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_PpicEmployee_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
                actionParam, idParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> SetActiveAsync(int id, bool isActive, int userId)
    {
        var actionParam = new SqlParameter("@Action", "SETACTIVE");
        var idParam = new SqlParameter("@Id", id);
        var isActiveParam = new SqlParameter("@IsActive", isActive);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_PpicEmployee_Manage @Action = @Action, @Id = @Id, @IsActive = @IsActive, @UserId = @UserId",
                actionParam, idParam, isActiveParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}

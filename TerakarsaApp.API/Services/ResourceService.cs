using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Resources;

namespace TerakarsaApp.API.Services;

public class ResourceService
{
    private readonly AppDbContext _db;

    public ResourceService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ResourcePagedResult> GetPagedAsync(ResourcePagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<ResourceDto>(
                "EXEC SIS_Resource_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Resource_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new ResourcePagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<ResourceLookupDto>> GetActiveByDivisionAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        return await _db.Database
            .SqlQueryRaw<ResourceLookupDto>(
                "EXEC SIS_Resource_GetActiveByDivision @DivisionId = @DivisionId",
                divisionIdParam)
            .ToListAsync();
    }

    public async Task<ResourceDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<ResourceDto>("EXEC SIS_Resource_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> CreateAsync(ResourceCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var resourceTypeIdParam = new SqlParameter("@ResourceTypeId", request.ResourceTypeId);
        var nameParam = new SqlParameter("@ResourceName", request.ResourceName);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Resource_Manage @Action = @Action, @DivisionId = @DivisionId, @ResourceTypeId = @ResourceTypeId, @ResourceName = @ResourceName, @IsActive = @IsActive, @UserId = @UserId",
                actionParam, divisionIdParam, resourceTypeIdParam, nameParam, isActiveParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ResourceUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var resourceTypeIdParam = new SqlParameter("@ResourceTypeId", request.ResourceTypeId);
        var nameParam = new SqlParameter("@ResourceName", request.ResourceName);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Resource_Manage @Action = @Action, @Id = @Id, @DivisionId = @DivisionId, @ResourceTypeId = @ResourceTypeId, @ResourceName = @ResourceName, @IsActive = @IsActive, @UserId = @UserId",
                actionParam, idParam, divisionIdParam, resourceTypeIdParam, nameParam, isActiveParam, userIdParam);
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
            "EXEC SIS_Resource_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.ResourceTypes;

namespace TerakarsaApp.API.Services;

public class ResourceTypeService
{
    private readonly AppDbContext _db;

    public ResourceTypeService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ResourceTypePagedResult> GetPagedAsync(ResourceTypePagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<ResourceTypeDto>(
                "EXEC SIS_ResourceType_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_ResourceType_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new ResourceTypePagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<ResourceTypeDto>> GetActiveAsync()
    {
        var result = await GetPagedAsync(new ResourceTypePagedRequest
        {
            PageNumber = 1,
            PageSize = 1000,
            SortColumn = "ResourceTypeName",
            SortDirection = "asc"
        });
        return result.Items;
    }

    public async Task<ResourceTypeDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<ResourceTypeDto>("EXEC SIS_ResourceType_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> CreateAsync(ResourceTypeCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var codeParam = new SqlParameter("@ResourceTypeCode", request.ResourceTypeCode);
        var nameParam = new SqlParameter("@ResourceTypeName", request.ResourceTypeName);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_ResourceType_Manage @Action = @Action, @ResourceTypeCode = @ResourceTypeCode, @ResourceTypeName = @ResourceTypeName, @UserId = @UserId",
                actionParam, codeParam, nameParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ResourceTypeUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@ResourceTypeCode", request.ResourceTypeCode);
        var nameParam = new SqlParameter("@ResourceTypeName", request.ResourceTypeName);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_ResourceType_Manage @Action = @Action, @Id = @Id, @ResourceTypeCode = @ResourceTypeCode, @ResourceTypeName = @ResourceTypeName, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, userIdParam);
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
            "EXEC SIS_ResourceType_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

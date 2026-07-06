using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Modules;

namespace TerakarsaApp.API.Services;

public class ModuleService
{
    private readonly AppDbContext _db;

    public ModuleService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<ModuleDto>> GetByUserIdAsync(int userId)
    {
        var userIdParam = new SqlParameter("@UserId", userId);

        return await _db.Database
            .SqlQueryRaw<ModuleDto>(
                "EXEC SIS_Module_Manage @Action = 'GET_BY_USER', @UserId = @UserId",
                userIdParam)
            .ToListAsync();
    }

    public async Task<List<int>> GetAssignedIdsAsync(int userId)
    {
        var userIdParam = new SqlParameter("@UserId", userId);

        return await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_UserModule_Manage @Action = 'GET_BY_USER', @UserId = @UserId",
                userIdParam)
            .ToListAsync();
    }

    public async Task AssignAsync(UserModuleAssignRequest request)
    {
        var userIdParam = new SqlParameter("@UserId", request.UserId);
        var moduleIdsParam = new SqlParameter("@ModuleIds", string.Join(",", request.ModuleIds));

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_UserModule_Manage @Action = 'SET', @UserId = @UserId, @ModuleIds = @ModuleIds",
            userIdParam, moduleIdsParam);
    }

    public async Task<ModulePagedResult> GetPagedAsync(ModulePagedRequest request)
    {
        var searchParam = new SqlParameter("@Search", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<ModuleDto>(
                "EXEC SIS_Module_Manage @Action = 'GET', @Search = @Search, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countParam = new SqlParameter("@Search", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Module_Manage @Action = 'COUNT', @Search = @Search",
                countParam)
            .ToListAsync();

        return new ModulePagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task CreateAsync(ModuleCreateRequest request)
    {
        var codeParam = new SqlParameter("@Code", request.Code);
        var nameParam = new SqlParameter("@Name", request.Name);
        var categoryParam = new SqlParameter("@Category", request.Category);
        var subCategoryParam = new SqlParameter("@SubCategory", request.SubCategory ?? (object)DBNull.Value);
        var routeParam = new SqlParameter("@Route", request.Route);
        var iconParam = new SqlParameter("@Icon", request.Icon);
        var sortOrderParam = new SqlParameter("@SortOrder", request.SortOrder);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Module_Manage @Action = 'INSERT', @Code = @Code, @Name = @Name, @Category = @Category, @SubCategory = @SubCategory, @Route = @Route, @Icon = @Icon, @SortOrder = @SortOrder",
            codeParam, nameParam, categoryParam, subCategoryParam, routeParam, iconParam, sortOrderParam);
    }

    public async Task UpdateAsync(ModuleUpdateRequest request)
    {
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@Code", request.Code);
        var nameParam = new SqlParameter("@Name", request.Name);
        var categoryParam = new SqlParameter("@Category", request.Category);
        var subCategoryParam = new SqlParameter("@SubCategory", request.SubCategory ?? (object)DBNull.Value);
        var routeParam = new SqlParameter("@Route", request.Route);
        var iconParam = new SqlParameter("@Icon", request.Icon);
        var sortOrderParam = new SqlParameter("@SortOrder", request.SortOrder);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Module_Manage @Action = 'UPDATE', @Id = @Id, @Code = @Code, @Name = @Name, @Category = @Category, @SubCategory = @SubCategory, @Route = @Route, @Icon = @Icon, @SortOrder = @SortOrder, @IsActive = @IsActive",
            idParam, codeParam, nameParam, categoryParam, subCategoryParam, routeParam, iconParam, sortOrderParam, isActiveParam);
    }

    public async Task DeleteAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Module_Manage @Action = 'DELETE', @Id = @Id",
            idParam);
    }
}

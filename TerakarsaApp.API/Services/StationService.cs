using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Services;

public class StationService
{
    private readonly AppDbContext _db;

    public StationService(AppDbContext db)
    {
        _db = db;
    }

    private class NewStationRow
    {
        public int NewId { get; set; }
        public string NewToken { get; set; } = string.Empty;
    }

    private class NewTokenRow
    {
        public string NewToken { get; set; } = string.Empty;
    }

    public async Task<StationPagedResult> GetPagedAsync(StationPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<StationDto>(
                "EXEC SIS_Station_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Station_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new StationPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<StationDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<StationDto>("EXEC SIS_Station_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<StationMeDto?> GetByTokenAsync(string token)
    {
        var tokenParam = new SqlParameter("@Token", token);

        var result = await _db.Database
            .SqlQueryRaw<StationMeDto>("EXEC SIS_Station_GetByToken @Token = @Token", tokenParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error, StationTokenResult? Result)> CreateAsync(StationCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var codeParam = new SqlParameter("@StationCode", request.StationCode);
        var nameParam = new SqlParameter("@StationName", request.StationName);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var defaultResourceIdParam = new SqlParameter("@DefaultResourceId", request.DefaultResourceId ?? (object)DBNull.Value);
        var allowResourceChangeParam = new SqlParameter("@AllowResourceChange", request.AllowResourceChange);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<NewStationRow>(
                    "EXEC SIS_Station_Manage @Action = @Action, @StationCode = @StationCode, @StationName = @StationName, @DivisionId = @DivisionId, @IsActive = @IsActive, @DefaultResourceId = @DefaultResourceId, @AllowResourceChange = @AllowResourceChange, @UserId = @UserId",
                    actionParam, codeParam, nameParam, divisionIdParam, isActiveParam, defaultResourceIdParam, allowResourceChangeParam, userIdParam)
                .ToListAsync();

            var row = result.FirstOrDefault();
            if (row is null) return (false, "Gagal membuat stasiun.", null);

            return (true, string.Empty, new StationTokenResult { Id = row.NewId, Token = row.NewToken });
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(StationUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@StationCode", request.StationCode);
        var nameParam = new SqlParameter("@StationName", request.StationName);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var defaultResourceIdParam = new SqlParameter("@DefaultResourceId", request.DefaultResourceId ?? (object)DBNull.Value);
        var allowResourceChangeParam = new SqlParameter("@AllowResourceChange", request.AllowResourceChange);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Station_Manage @Action = @Action, @Id = @Id, @StationCode = @StationCode, @StationName = @StationName, @DivisionId = @DivisionId, @IsActive = @IsActive, @DefaultResourceId = @DefaultResourceId, @AllowResourceChange = @AllowResourceChange, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, divisionIdParam, isActiveParam, defaultResourceIdParam, allowResourceChangeParam, userIdParam);
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
            "EXEC SIS_Station_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }

    public async Task<(bool Success, string Error, StationTokenResult? Result)> RegenerateTokenAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "REGENERATE_TOKEN");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<NewTokenRow>(
                    "EXEC SIS_Station_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
                    actionParam, idParam, userIdParam)
                .ToListAsync();

            var row = result.FirstOrDefault();
            if (row is null) return (false, "Stasiun tidak ditemukan.", null);

            return (true, string.Empty, new StationTokenResult { Id = id, Token = row.NewToken });
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }
}

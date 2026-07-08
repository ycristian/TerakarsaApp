using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.SizePacks;

namespace TerakarsaApp.API.Services;

public class SizePackService
{
    private readonly AppDbContext _db;

    public SizePackService(AppDbContext db)
    {
        _db = db;
    }

    // EF Core builds an ad-hoc keyless model for SqlQueryRaw<T>; a List<T> property like
    // SizePackDto.Details is seen as an unsupported navigation, so the header projection
    // must go through this flat row type instead of SizePackDto directly.
    private class SizePackRow
    {
        public int Id { get; set; }
        public int? BuyerId { get; set; }
        public string? BuyerName { get; set; }
        public string SizePackName { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public int CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public int? UpdatedBy { get; set; }
    }

    private static SizePackDto ToDto(SizePackRow row) => new()
    {
        Id = row.Id,
        BuyerId = row.BuyerId,
        BuyerName = row.BuyerName,
        SizePackName = row.SizePackName,
        CreatedAt = row.CreatedAt,
        CreatedBy = row.CreatedBy,
        UpdatedAt = row.UpdatedAt,
        UpdatedBy = row.UpdatedBy
    };

    public async Task<SizePackPagedResult> GetPagedAsync(SizePackPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var rows = await _db.Database
            .SqlQueryRaw<SizePackRow>(
                "EXEC SIS_SizePack_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_SizePack_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new SizePackPagedResult
        {
            Items = rows.Select(ToDto).ToList(),
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<SizePackDto>> GetActiveAsync()
    {
        var result = await GetPagedAsync(new SizePackPagedRequest
        {
            PageNumber = 1,
            PageSize = 1000,
            SortColumn = "SizePackName",
            SortDirection = "asc"
        });
        return result.Items;
    }

    public async Task<SizePackDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var header = await _db.Database
            .SqlQueryRaw<SizePackRow>("EXEC SIS_SizePack_GetById @Id = @Id", idParam)
            .ToListAsync();

        var row = header.FirstOrDefault();
        if (row is null) return null;

        var dto = ToDto(row);

        var sizePackIdParam = new SqlParameter("@SizePackId", id);
        dto.Details = await _db.Database
            .SqlQueryRaw<SizePackDetailDto>("EXEC SIS_SizePackDetail_GetBySizePack @SizePackId = @SizePackId", sizePackIdParam)
            .ToListAsync();

        return dto;
    }

    public async Task<(bool Success, string Error, int Id)> CreateAsync(SizePackCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var buyerIdParam = new SqlParameter("@BuyerId", (object?)request.BuyerId ?? DBNull.Value);
        var nameParam = new SqlParameter("@SizePackName", request.SizePackName);
        var detailsParam = new SqlParameter("@Details", JsonSerializer.Serialize(request.Details));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_SizePack_Manage @Action = @Action, @BuyerId = @BuyerId, @SizePackName = @SizePackName, @Details = @Details, @UserId = @UserId",
                    actionParam, buyerIdParam, nameParam, detailsParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(SizePackUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var buyerIdParam = new SqlParameter("@BuyerId", (object?)request.BuyerId ?? DBNull.Value);
        var nameParam = new SqlParameter("@SizePackName", request.SizePackName);
        var detailsParam = new SqlParameter("@Details", JsonSerializer.Serialize(request.Details));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_SizePack_Manage @Action = @Action, @Id = @Id, @BuyerId = @BuyerId, @SizePackName = @SizePackName, @Details = @Details, @UserId = @UserId",
                actionParam, idParam, buyerIdParam, nameParam, detailsParam, userIdParam);
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
            "EXEC SIS_SizePack_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

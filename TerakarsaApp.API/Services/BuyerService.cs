using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Buyers;

namespace TerakarsaApp.API.Services;

public class BuyerService
{
    private readonly AppDbContext _db;

    public BuyerService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<BuyerPagedResult> GetPagedAsync(BuyerPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<BuyerDto>(
                "EXEC SIS_Buyer_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Buyer_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new BuyerPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<BuyerDto>> GetActiveAsync()
    {
        var result = await GetPagedAsync(new BuyerPagedRequest
        {
            PageNumber = 1,
            PageSize = 1000,
            SortColumn = "BuyerName",
            SortDirection = "asc"
        });
        return result.Items;
    }

    public async Task<BuyerDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<BuyerDto>("EXEC SIS_Buyer_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> CreateAsync(BuyerCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var codeParam = new SqlParameter("@BuyerCode", request.BuyerCode);
        var nameParam = new SqlParameter("@BuyerName", request.BuyerName);
        var addressParam = new SqlParameter("@Address", request.Address ?? (object)DBNull.Value);
        var phoneParam = new SqlParameter("@Phone", request.Phone ?? (object)DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Buyer_Manage @Action = @Action, @BuyerCode = @BuyerCode, @BuyerName = @BuyerName, @Address = @Address, @Phone = @Phone, @UserId = @UserId",
                actionParam, codeParam, nameParam, addressParam, phoneParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(BuyerUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@BuyerCode", request.BuyerCode);
        var nameParam = new SqlParameter("@BuyerName", request.BuyerName);
        var addressParam = new SqlParameter("@Address", request.Address ?? (object)DBNull.Value);
        var phoneParam = new SqlParameter("@Phone", request.Phone ?? (object)DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Buyer_Manage @Action = @Action, @Id = @Id, @BuyerCode = @BuyerCode, @BuyerName = @BuyerName, @Address = @Address, @Phone = @Phone, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, addressParam, phoneParam, userIdParam);
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
            "EXEC SIS_Buyer_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

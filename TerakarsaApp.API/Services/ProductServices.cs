using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Products;

namespace TerakarsaApp.API.Services;

public class ProductService
{
    private readonly AppDbContext _db;

    public ProductService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<ProductDto>> GetAllAsync()
    {
        return await _db.Database
            .SqlQueryRaw<ProductDto>(
                "EXEC SIS_Product_Manage @Action = 'GET'")
            .ToListAsync();
    }

    public async Task<ProductDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<ProductDto>(
                "EXEC SIS_Product_Manage @Action = 'GET', @Id = @Id",
                idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task CreateAsync(ProductCreateRequest request)
    {
        var nameParam = new SqlParameter("@Name", request.Name);
        var priceParam = new SqlParameter("@Price", request.Price);
        var stockParam = new SqlParameter("@Stock", request.Stock);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Product_Manage @Action = 'INSERT', @Name = @Name, @Price = @Price, @Stock = @Stock",
            nameParam, priceParam, stockParam);
    }

    public async Task UpdateAsync(ProductUpdateRequest request)
    {
        var idParam = new SqlParameter("@Id", request.Id);
        var nameParam = new SqlParameter("@Name", request.Name);
        var priceParam = new SqlParameter("@Price", request.Price);
        var stockParam = new SqlParameter("@Stock", request.Stock);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Product_Manage @Action = 'UPDATE', @Id = @Id, @Name = @Name, @Price = @Price, @Stock = @Stock",
            idParam, nameParam, priceParam, stockParam);
    }

    public async Task DeleteAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Product_Manage @Action = 'DELETE', @Id = @Id",
            idParam);
    }

    public async Task<ProductPagedResult> GetPagedAsync(ProductPagedRequest request)
    {
        var searchParam = new SqlParameter("@Search", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<ProductDto>(
                "EXEC SIS_Product_Manage @Action = 'GET', @Search = @Search, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countParam = new SqlParameter("@Search", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Product_Manage @Action = 'COUNT', @Search = @Search",
                countParam)
            .ToListAsync();

        var totalCount = countResult.FirstOrDefault();

        return new ProductPagedResult
        {
            Items = items,
            TotalCount = totalCount,
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }
}
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using System.Text.Json;
using TerakarsaApp.Shared.Positions;

namespace TerakarsaApp.API.Services;

public class PositionService
{
    private readonly AppDbContext _db;

    public PositionService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<PositionPagedResult> GetPagedAsync(PositionPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<PositionDto>(
                "EXEC SIS_Position_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Position_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new PositionPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<PositionDto>> GetActiveAsync()
    {
        var result = await GetPagedAsync(new PositionPagedRequest
        {
            PageNumber = 1,
            PageSize = 1000,
            SortColumn = "PositionName",
            SortDirection = "asc"
        });
        return result.Items;
    }

    public async Task<PositionDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<PositionDto>("EXEC SIS_Position_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> CreateAsync(PositionCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var nameParam = new SqlParameter("@PositionName", request.PositionName);
        var gateOperatorParam = new SqlParameter("@IsGateOperator", request.IsGateOperator);
        var divisionIdsParam = new SqlParameter("@DivisionIdsJson", DivisionIdsJson(request.DivisionIds));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Position_Manage @Action = @Action, @PositionName = @PositionName, @IsGateOperator = @IsGateOperator, @DivisionIdsJson = @DivisionIdsJson, @UserId = @UserId",
                actionParam, nameParam, gateOperatorParam, divisionIdsParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(PositionUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var nameParam = new SqlParameter("@PositionName", request.PositionName);
        var gateOperatorParam = new SqlParameter("@IsGateOperator", request.IsGateOperator);
        var divisionIdsParam = new SqlParameter("@DivisionIdsJson", DivisionIdsJson(request.DivisionIds));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Position_Manage @Action = @Action, @Id = @Id, @PositionName = @PositionName, @IsGateOperator = @IsGateOperator, @DivisionIdsJson = @DivisionIdsJson, @UserId = @UserId",
                actionParam, idParam, nameParam, gateOperatorParam, divisionIdsParam, userIdParam);
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
            "EXEC SIS_Position_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }

    // Prompt 58 (lanjutan): divisi yang sudah dipilih untuk satu jabatan -- form Master
    // Jabatan memakainya untuk mencentang ulang pilihan tersimpan.
    public async Task<List<int>> GetDivisionIdsAsync(int positionId)
    {
        var positionIdParam = new SqlParameter("@PositionId", positionId);

        return await _db.Database
            .SqlQueryRaw<int>("EXEC SIS_Position_GetDivisions @PositionId = @PositionId", positionIdParam)
            .ToListAsync();
    }

    // Pilihan jabatan untuk satu divisi (dipakai form pegawai di stasiun). Divisi yang belum
    // punya pemetaan tetap mendapat SEMUA jabatan -- lihat SIS_Position_GetByDivision.
    public async Task<List<PositionDto>> GetByDivisionAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        return await _db.Database
            .SqlQueryRaw<PositionDto>(
                "EXEC SIS_Position_GetByDivision @DivisionId = @DivisionId", divisionIdParam)
            .ToListAsync();
    }

    // NULL = SP tidak menyentuh pemetaan sama sekali (caller lama); daftar kosong = dikosongkan.
    private static object DivisionIdsJson(List<int>? divisionIds) =>
        divisionIds is null ? DBNull.Value : JsonSerializer.Serialize(divisionIds);
}

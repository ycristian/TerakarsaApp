using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Packs;

namespace TerakarsaApp.API.Services;

public class PackService
{
    private readonly AppDbContext _db;
    private readonly string _publicBaseUrl;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public PackService(AppDbContext db, IOptions<AppOptions> appOptions)
    {
        _db = db;
        _publicBaseUrl = appOptions.Value.PublicBaseUrl;
    }

    private class PackCreateResultRow
    {
        public int NewId { get; set; }
        public int NewPackNo { get; set; }
        public string NewSerial { get; set; } = string.Empty;
        public int? NewPrintJobId { get; set; }
    }

    public async Task<List<PackStockAvailableDto>> GetStockAvailableAsync(int projectId)
    {
        var projectIdParam = new SqlParameter("@ProjectId", projectId);
        return await _db.Database
            .SqlQueryRaw<PackStockAvailableDto>("EXEC SIS_Pack_StockAvailable @ProjectId = @ProjectId", projectIdParam)
            .ToListAsync();
    }

    // SIS_Pack_ListByProject mengembalikan 2 result set (ringkasan pack + items) -- EF Core
    // SqlQueryRaw hanya mendukung satu result set, jadi di sini pakai SqlCommand mentah
    // sama seperti BundleService.GetScanInfoAsync.
    public async Task<ProjectPackingDto> GetProjectPackingAsync(int projectId)
    {
        var result = new ProjectPackingDto { ProjectId = projectId, PublicBaseUrl = _publicBaseUrl };
        result.Stock = await GetStockAvailableAsync(projectId);

        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Pack_ListByProject";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@ProjectId", projectId));

            using var reader = await cmd.ExecuteReaderAsync();

            while (await reader.ReadAsync())
            {
                result.Packs.Add(new PackListItemDto
                {
                    Id = reader.GetInt32(reader.GetOrdinal("Id")),
                    PackNo = reader.GetInt32(reader.GetOrdinal("PackNo")),
                    Serial = reader.GetString(reader.GetOrdinal("Serial")),
                    ArticleCount = reader.GetInt32(reader.GetOrdinal("ArticleCount")),
                    TotalPlan = reader.GetInt32(reader.GetOrdinal("TotalPlan")),
                    TotalActual = reader.GetInt32(reader.GetOrdinal("TotalActual")),
                    IsConfirmed = reader.GetInt32(reader.GetOrdinal("IsConfirmed")) == 1,
                    LabelStatus = reader.IsDBNull(reader.GetOrdinal("LabelStatus")) ? null : reader.GetString(reader.GetOrdinal("LabelStatus")),
                    PrintedAt = reader.IsDBNull(reader.GetOrdinal("PrintedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("PrintedAt")),
                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt"))
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Items.Add(new PackItemDto
                {
                    PackItemId = reader.GetInt32(reader.GetOrdinal("PackItemId")),
                    PackId = reader.GetInt32(reader.GetOrdinal("PackId")),
                    ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                    ArticleSizeId = reader.GetInt32(reader.GetOrdinal("ArticleSizeId")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    Style = reader.IsDBNull(reader.GetOrdinal("Style")) ? null : reader.GetString(reader.GetOrdinal("Style")),
                    Color = reader.IsDBNull(reader.GetOrdinal("Color")) ? null : reader.GetString(reader.GetOrdinal("Color")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    QtyPlan = reader.GetInt32(reader.GetOrdinal("QtyPlan")),
                    QtyActual = reader.IsDBNull(reader.GetOrdinal("QtyActual")) ? null : reader.GetInt32(reader.GetOrdinal("QtyActual"))
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<(bool Success, string Error, PackCreateResult Result)> CreateAsync(PackCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var projectIdParam = new SqlParameter("@ProjectId", request.ProjectId);
        var itemsJsonParam = new SqlParameter("@ItemsJson", JsonSerializer.Serialize(request.Items, JsonOptions));
        var publicBaseUrlParam = new SqlParameter("@PublicBaseUrl", (object?)_publicBaseUrl ?? DBNull.Value);
        var skipPrintJobParam = new SqlParameter("@SkipPrintJob", !request.AutoPrint);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<PackCreateResultRow>(
                    "EXEC SIS_Pack_Manage @Action = @Action, @ProjectId = @ProjectId, @ItemsJson = @ItemsJson, @PublicBaseUrl = @PublicBaseUrl, @SkipPrintJob = @SkipPrintJob, @UserId = @UserId",
                    actionParam, projectIdParam, itemsJsonParam, publicBaseUrlParam, skipPrintJobParam, userIdParam)
                .ToListAsync();

            var row = result.First();
            return (true, string.Empty, new PackCreateResult { Id = row.NewId, PackNo = row.NewPackNo, Serial = row.NewSerial, PrintJobId = row.NewPrintJobId });
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, new PackCreateResult());
        }
    }

    public async Task<(bool Success, string Error)> UpdatePlanAsync(int id, PackUpdatePlanRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE_PLAN");
        var idParam = new SqlParameter("@Id", id);
        var itemsJsonParam = new SqlParameter("@ItemsJson", JsonSerializer.Serialize(request.Items, JsonOptions));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Pack_Manage @Action = @Action, @Id = @Id, @ItemsJson = @ItemsJson, @UserId = @UserId",
                actionParam, idParam, itemsJsonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> ConfirmAsync(int id, PackConfirmRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CONFIRM");
        var idParam = new SqlParameter("@Id", id);
        var itemsJsonParam = new SqlParameter("@ItemsJson", JsonSerializer.Serialize(request.Items, JsonOptions));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Pack_Manage @Action = @Action, @Id = @Id, @ItemsJson = @ItemsJson, @UserId = @UserId",
                actionParam, idParam, itemsJsonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteAsync(int id, string reason, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var reasonParam = new SqlParameter("@DeleteReason", reason);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Pack_Manage @Action = @Action, @Id = @Id, @DeleteReason = @DeleteReason, @UserId = @UserId",
                actionParam, idParam, reasonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error, int PrintJobId)> ReprintAsync(int packId, int userId)
    {
        var packIdParam = new SqlParameter("@PackId", packId);
        var publicBaseUrlParam = new SqlParameter("@PublicBaseUrl", (object?)_publicBaseUrl ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_Pack_ReprintLabel @PackId = @PackId, @PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId",
                    packIdParam, publicBaseUrlParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    // SIS_Pack_ScanInfo mengembalikan 2 result set (info + items) -- pola sama dengan
    // BundleService.GetScanInfoAsync.
    public async Task<PackScanInfoDto?> GetScanInfoAsync(string serial)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Pack_ScanInfo";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@Serial", serial));

            using var reader = await cmd.ExecuteReaderAsync();

            if (!await reader.ReadAsync()) return null;

            var pack = new PackScanPackDto
            {
                PackId = reader.GetInt32(reader.GetOrdinal("PackId")),
                PackNo = reader.GetInt32(reader.GetOrdinal("PackNo")),
                Serial = reader.GetString(reader.GetOrdinal("Serial")),
                ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                TotalPacks = reader.GetInt32(reader.GetOrdinal("TotalPacks")),
                TotalQty = reader.GetInt32(reader.GetOrdinal("TotalQty")),
                IsConfirmed = reader.GetBoolean(reader.GetOrdinal("IsConfirmed")),
                CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt"))
            };

            await reader.NextResultAsync();
            var items = new List<PackScanItemDto>();
            while (await reader.ReadAsync())
            {
                items.Add(new PackScanItemDto
                {
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    Style = reader.IsDBNull(reader.GetOrdinal("Style")) ? null : reader.GetString(reader.GetOrdinal("Style")),
                    Color = reader.IsDBNull(reader.GetOrdinal("Color")) ? null : reader.GetString(reader.GetOrdinal("Color")),
                    SizeName = reader.GetString(reader.GetOrdinal("SizeName")),
                    QtyPlan = reader.GetInt32(reader.GetOrdinal("QtyPlan")),
                    QtyActual = reader.IsDBNull(reader.GetOrdinal("QtyActual")) ? null : reader.GetInt32(reader.GetOrdinal("QtyActual"))
                });
            }

            return new PackScanInfoDto { Pack = pack, Items = items };
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }
}

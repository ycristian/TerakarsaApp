using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Services;

public class ArticleService
{
    private readonly AppDbContext _db;

    public ArticleService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<ArticleListItemDto>> GetByProjectAsync(int projectId)
    {
        var projectIdParam = new SqlParameter("@ProjectId", projectId);

        return await _db.Database
            .SqlQueryRaw<ArticleListItemDto>("EXEC SIS_Article_GetByProject @ProjectId = @ProjectId", projectIdParam)
            .ToListAsync();
    }

    public async Task<List<ArticleSizeSummaryDto>> GetSizesByProjectAsync(int projectId)
    {
        var projectIdParam = new SqlParameter("@ProjectId", projectId);

        return await _db.Database
            .SqlQueryRaw<ArticleSizeSummaryDto>("EXEC SIS_ArticleSize_GetByProject @ProjectId = @ProjectId", projectIdParam)
            .ToListAsync();
    }

    // EF Core builds an ad-hoc keyless model for SqlQueryRaw<T>; a List<T> property like
    // ArticleDto.Sizes is seen as an unsupported navigation, so the header projection
    // must go through this flat row type instead of ArticleDto directly.
    private class ArticleRow
    {
        public int Id { get; set; }
        public int ProjectId { get; set; }
        public int SizePackId { get; set; }
        public string SizePackName { get; set; } = string.Empty;
        public string ArticleName { get; set; } = string.Empty;
        public string? Style { get; set; }
        public string? Color { get; set; }
        public DateTime CreatedAt { get; set; }
        public int CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public int? UpdatedBy { get; set; }
    }

    public async Task<ArticleDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var header = await _db.Database
            .SqlQueryRaw<ArticleRow>("EXEC SIS_Article_GetById @Id = @Id", idParam)
            .ToListAsync();

        var row = header.FirstOrDefault();
        if (row is null) return null;

        var dto = new ArticleDto
        {
            Id = row.Id,
            ProjectId = row.ProjectId,
            SizePackId = row.SizePackId,
            SizePackName = row.SizePackName,
            ArticleName = row.ArticleName,
            Style = row.Style,
            Color = row.Color,
            CreatedAt = row.CreatedAt,
            CreatedBy = row.CreatedBy,
            UpdatedAt = row.UpdatedAt,
            UpdatedBy = row.UpdatedBy
        };

        var articleIdParam = new SqlParameter("@ArticleId", id);
        dto.Sizes = await _db.Database
            .SqlQueryRaw<ArticleSizeDto>("EXEC SIS_ArticleSize_GetByArticle @ArticleId = @ArticleId", articleIdParam)
            .ToListAsync();

        return dto;
    }

    public async Task<(bool Success, string Error, int Id)> CreateAsync(ArticleCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var projectIdParam = new SqlParameter("@ProjectId", request.ProjectId);
        var sizePackIdParam = new SqlParameter("@SizePackId", request.SizePackId);
        var nameParam = new SqlParameter("@ArticleName", request.ArticleName);
        var styleParam = new SqlParameter("@Style", (object?)request.Style ?? DBNull.Value);
        var colorParam = new SqlParameter("@Color", (object?)request.Color ?? DBNull.Value);
        var sizesParam = new SqlParameter("@Sizes", JsonSerializer.Serialize(request.Sizes));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_Article_Manage @Action = @Action, @ProjectId = @ProjectId, @SizePackId = @SizePackId, @ArticleName = @ArticleName, @Style = @Style, @Color = @Color, @Sizes = @Sizes, @UserId = @UserId",
                    actionParam, projectIdParam, sizePackIdParam, nameParam, styleParam, colorParam, sizesParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ArticleUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var sizePackIdParam = new SqlParameter("@SizePackId", request.SizePackId);
        var nameParam = new SqlParameter("@ArticleName", request.ArticleName);
        var styleParam = new SqlParameter("@Style", (object?)request.Style ?? DBNull.Value);
        var colorParam = new SqlParameter("@Color", (object?)request.Color ?? DBNull.Value);
        var sizesParam = new SqlParameter("@Sizes", JsonSerializer.Serialize(request.Sizes));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Article_Manage @Action = @Action, @Id = @Id, @SizePackId = @SizePackId, @ArticleName = @ArticleName, @Style = @Style, @Color = @Color, @Sizes = @Sizes, @UserId = @UserId",
                actionParam, idParam, sizePackIdParam, nameParam, styleParam, colorParam, sizesParam, userIdParam);
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
            "EXEC SIS_Article_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

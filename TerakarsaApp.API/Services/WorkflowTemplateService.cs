using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.WorkflowTemplates;

namespace TerakarsaApp.API.Services;

public class WorkflowTemplateService
{
    private readonly AppDbContext _db;

    public WorkflowTemplateService(AppDbContext db)
    {
        _db = db;
    }

    // EF Core builds an ad-hoc keyless model for SqlQueryRaw<T>; a List<T> property like
    // WorkflowTemplateDto.Steps is seen as an unsupported navigation, so the header projection
    // must go through this flat row type instead of WorkflowTemplateDto directly.
    private class WorkflowTemplateRow
    {
        public int Id { get; set; }
        public string WorkflowCode { get; set; } = string.Empty;
        public string WorkflowName { get; set; } = string.Empty;
        public int StepCount { get; set; }
        public DateTime CreatedAt { get; set; }
        public int CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public int? UpdatedBy { get; set; }
    }

    private static WorkflowTemplateDto ToDto(WorkflowTemplateRow row) => new()
    {
        Id = row.Id,
        WorkflowCode = row.WorkflowCode,
        WorkflowName = row.WorkflowName,
        StepCount = row.StepCount,
        CreatedAt = row.CreatedAt,
        CreatedBy = row.CreatedBy,
        UpdatedAt = row.UpdatedAt,
        UpdatedBy = row.UpdatedBy
    };

    public async Task<WorkflowTemplatePagedResult> GetPagedAsync(WorkflowTemplatePagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var rows = await _db.Database
            .SqlQueryRaw<WorkflowTemplateRow>(
                "EXEC SIS_WorkflowTemplate_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_WorkflowTemplate_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new WorkflowTemplatePagedResult
        {
            Items = rows.Select(ToDto).ToList(),
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<List<WorkflowTemplateDto>> GetActiveAsync()
    {
        var result = await GetPagedAsync(new WorkflowTemplatePagedRequest
        {
            PageNumber = 1,
            PageSize = 1000,
            SortColumn = "WorkflowName",
            SortDirection = "asc"
        });
        return result.Items;
    }

    public async Task<WorkflowTemplateDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var header = await _db.Database
            .SqlQueryRaw<WorkflowTemplateRow>("EXEC SIS_WorkflowTemplate_GetById @Id = @Id", idParam)
            .ToListAsync();

        var row = header.FirstOrDefault();
        if (row is null) return null;

        var dto = ToDto(row);

        var templateIdParam = new SqlParameter("@WorkflowTemplateId", id);
        dto.Steps = await _db.Database
            .SqlQueryRaw<WorkflowTemplateStepDto>("EXEC SIS_WorkflowTemplateStep_GetByTemplate @WorkflowTemplateId = @WorkflowTemplateId", templateIdParam)
            .ToListAsync();

        return dto;
    }

    public async Task<(bool Success, string Error, int Id)> CreateAsync(WorkflowTemplateCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var codeParam = new SqlParameter("@WorkflowCode", request.WorkflowCode);
        var nameParam = new SqlParameter("@WorkflowName", request.WorkflowName);
        var stepsParam = new SqlParameter("@Steps", JsonSerializer.Serialize(request.Steps));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_WorkflowTemplate_Manage @Action = @Action, @WorkflowCode = @WorkflowCode, @WorkflowName = @WorkflowName, @Steps = @Steps, @UserId = @UserId",
                    actionParam, codeParam, nameParam, stepsParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(WorkflowTemplateUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@WorkflowCode", request.WorkflowCode);
        var nameParam = new SqlParameter("@WorkflowName", request.WorkflowName);
        var stepsParam = new SqlParameter("@Steps", JsonSerializer.Serialize(request.Steps));
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_WorkflowTemplate_Manage @Action = @Action, @Id = @Id, @WorkflowCode = @WorkflowCode, @WorkflowName = @WorkflowName, @Steps = @Steps, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, stepsParam, userIdParam);
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
            "EXEC SIS_WorkflowTemplate_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }
}

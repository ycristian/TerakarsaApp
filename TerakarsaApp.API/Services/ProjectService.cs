using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Services;

public class ProjectService
{
    private readonly AppDbContext _db;

    public ProjectService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ProjectPagedResult> GetPagedAsync(ProjectPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var statusParam = new SqlParameter("@Status", request.Status ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<ProjectDto>(
                "EXEC SIS_Project_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @Status = @Status, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, statusParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var countStatusParam = new SqlParameter("@Status", request.Status ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Project_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @Status = @Status",
                countActionParam, countSearchParam, countStatusParam)
            .ToListAsync();

        return new ProjectPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<ProjectDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<ProjectDto>("EXEC SIS_Project_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error, int NewId)> CreateAsync(ProjectCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var customerIdParam = new SqlParameter("@CustomerId", request.CustomerId);
        var mdParam = new SqlParameter("@ProjectMd", request.ProjectMd ?? (object)DBNull.Value);
        var picParam = new SqlParameter("@ProjectPic", request.ProjectPic ?? (object)DBNull.Value);
        var nameParam = new SqlParameter("@ProjectName", request.ProjectName);
        var noPoParam = new SqlParameter("@NoPo", request.NoPo ?? (object)DBNull.Value);
        var materialNameParam = new SqlParameter("@MaterialName", request.MaterialName ?? (object)DBNull.Value);
        var orderDateParam = new SqlParameter("@OrderDate", request.OrderDate ?? (object)DBNull.Value);
        var startDateParam = new SqlParameter("@StartDate", request.StartDate ?? (object)DBNull.Value);
        var deadlineParam = new SqlParameter("@Deadline", request.Deadline ?? (object)DBNull.Value);
        var deliveryDateParam = new SqlParameter("@DeliveryDate", request.DeliveryDate ?? (object)DBNull.Value);
        var remarksParam = new SqlParameter("@Remarks", request.Remarks ?? (object)DBNull.Value);
        var isUrgentParam = new SqlParameter("@IsUrgent", request.IsUrgent);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    "EXEC SIS_Project_Manage @Action = @Action, @CustomerId = @CustomerId, @ProjectMd = @ProjectMd, @ProjectPic = @ProjectPic, @ProjectName = @ProjectName, @NoPo = @NoPo, @MaterialName = @MaterialName, @OrderDate = @OrderDate, @StartDate = @StartDate, @Deadline = @Deadline, @DeliveryDate = @DeliveryDate, @Remarks = @Remarks, @IsUrgent = @IsUrgent, @UserId = @UserId",
                    actionParam, customerIdParam, mdParam, picParam, nameParam, noPoParam, materialNameParam, orderDateParam, startDateParam, deadlineParam, deliveryDateParam, remarksParam, isUrgentParam, userIdParam)
                .ToListAsync();
            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(ProjectUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var customerIdParam = new SqlParameter("@CustomerId", request.CustomerId);
        var mdParam = new SqlParameter("@ProjectMd", request.ProjectMd ?? (object)DBNull.Value);
        var picParam = new SqlParameter("@ProjectPic", request.ProjectPic ?? (object)DBNull.Value);
        var nameParam = new SqlParameter("@ProjectName", request.ProjectName);
        var noPoParam = new SqlParameter("@NoPo", request.NoPo ?? (object)DBNull.Value);
        var materialNameParam = new SqlParameter("@MaterialName", request.MaterialName ?? (object)DBNull.Value);
        var orderDateParam = new SqlParameter("@OrderDate", request.OrderDate ?? (object)DBNull.Value);
        var startDateParam = new SqlParameter("@StartDate", request.StartDate ?? (object)DBNull.Value);
        var deadlineParam = new SqlParameter("@Deadline", request.Deadline ?? (object)DBNull.Value);
        var deliveryDateParam = new SqlParameter("@DeliveryDate", request.DeliveryDate ?? (object)DBNull.Value);
        var remarksParam = new SqlParameter("@Remarks", request.Remarks ?? (object)DBNull.Value);
        var isUrgentParam = new SqlParameter("@IsUrgent", request.IsUrgent);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Project_Manage @Action = @Action, @Id = @Id, @CustomerId = @CustomerId, @ProjectMd = @ProjectMd, @ProjectPic = @ProjectPic, @ProjectName = @ProjectName, @NoPo = @NoPo, @MaterialName = @MaterialName, @OrderDate = @OrderDate, @StartDate = @StartDate, @Deadline = @Deadline, @DeliveryDate = @DeliveryDate, @Remarks = @Remarks, @IsUrgent = @IsUrgent, @UserId = @UserId",
                actionParam, idParam, customerIdParam, mdParam, picParam, nameParam, noPoParam, materialNameParam, orderDateParam, startDateParam, deadlineParam, deliveryDateParam, remarksParam, isUrgentParam, userIdParam);
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
            "EXEC SIS_Project_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }

    public async Task<(bool Success, string Error)> SetStatusAsync(ProjectSetStatusRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "SET_STATUS");
        var idParam = new SqlParameter("@Id", request.Id);
        var manualStatusParam = new SqlParameter("@ManualStatus", request.ManualStatus ?? (object)DBNull.Value);
        var statusReasonParam = new SqlParameter("@StatusReason", request.StatusReason ?? (object)DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Project_Manage @Action = @Action, @Id = @Id, @ManualStatus = @ManualStatus, @StatusReason = @StatusReason, @UserId = @UserId",
                actionParam, idParam, manualStatusParam, statusReasonParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}

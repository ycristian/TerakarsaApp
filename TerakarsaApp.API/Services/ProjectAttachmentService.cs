using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Services;

public class ProjectAttachmentRow
{
    public int Id { get; set; }
    public int ProjectId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public int FileSizeKb { get; set; }
    public string FileType { get; set; } = string.Empty;
    public string? Description { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
}

public class ProjectAttachmentService
{
    private static readonly string[] AllowedExtensions = { "jpg", "jpeg", "png", "pdf", "xlsx" };
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;
    private static readonly FileExtensionContentTypeProvider ContentTypeProvider = new();

    private readonly AppDbContext _db;
    private readonly IFileStorageService _fileStorage;

    public ProjectAttachmentService(AppDbContext db, IFileStorageService fileStorage)
    {
        _db = db;
        _fileStorage = fileStorage;
    }

    public async Task<List<ProjectAttachmentDto>> GetByProjectAsync(int projectId)
    {
        var rows = await GetRowsByProjectAsync(projectId);
        return rows.Select(r => new ProjectAttachmentDto
        {
            Id = r.Id,
            ProjectId = r.ProjectId,
            FileName = r.FileName,
            FileType = r.FileType,
            FileSizeKb = r.FileSizeKb,
            Description = r.Description,
            CreatedAt = r.CreatedAt,
            CreatedBy = r.CreatedBy
        }).ToList();
    }

    public async Task<(bool Success, string Error)> UploadAsync(int projectId, IFormFile? file, string? description, int userId)
    {
        if (file is null || file.Length == 0)
            return (false, "File wajib diunggah.");

        if (file.Length > MaxFileSizeBytes)
            return (false, "Ukuran file maksimal 10 MB.");

        var extension = Path.GetExtension(file.FileName).TrimStart('.').ToLowerInvariant();
        if (!AllowedExtensions.Contains(extension))
            return (false, "Tipe file hanya boleh jpg, png, pdf, atau xlsx.");

        var fileType = extension == "jpeg" ? "jpg" : extension;
        var (relativePath, sizeKb) = await _fileStorage.SaveAsync(file, $"projects/{projectId}");

        var actionParam = new SqlParameter("@Action", "CREATE");
        var projectIdParam = new SqlParameter("@ProjectId", projectId);
        var fileNameParam = new SqlParameter("@FileName", file.FileName);
        var filePathParam = new SqlParameter("@FilePath", relativePath);
        var fileSizeKbParam = new SqlParameter("@FileSizeKb", sizeKb);
        var fileTypeParam = new SqlParameter("@FileType", fileType);
        var descriptionParam = new SqlParameter("@Description", (object?)description ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_ProjectAttachment_Manage @Action = @Action, @ProjectId = @ProjectId, @FileName = @FileName, @FilePath = @FilePath, @FileSizeKb = @FileSizeKb, @FileType = @FileType, @Description = @Description, @UserId = @UserId",
                actionParam, projectIdParam, fileNameParam, filePathParam, fileSizeKbParam, fileTypeParam, descriptionParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(Stream Stream, string ContentType, string FileName)?> GetFileForDownloadAsync(int projectId, int attachmentId)
    {
        var rows = await GetRowsByProjectAsync(projectId);
        var row = rows.FirstOrDefault(r => r.Id == attachmentId);
        if (row is null) return null;

        if (!ContentTypeProvider.TryGetContentType(row.FileName, out var contentType))
            contentType = "application/octet-stream";

        var stream = _fileStorage.OpenRead(row.FilePath);
        return (stream, contentType, row.FileName);
    }

    public async Task DeleteAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_ProjectAttachment_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }

    private async Task<List<ProjectAttachmentRow>> GetRowsByProjectAsync(int projectId)
    {
        var actionParam = new SqlParameter("@Action", "GETBYPROJECT");
        var projectIdParam = new SqlParameter("@ProjectId", projectId);

        return await _db.Database
            .SqlQueryRaw<ProjectAttachmentRow>(
                "EXEC SIS_ProjectAttachment_Manage @Action = @Action, @ProjectId = @ProjectId",
                actionParam, projectIdParam)
            .ToListAsync();
    }
}

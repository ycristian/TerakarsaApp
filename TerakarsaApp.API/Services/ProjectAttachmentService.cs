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
    private static readonly string[] PhotoExtensions = { "jpg", "jpeg", "png" };
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;
    private static readonly FileExtensionContentTypeProvider ContentTypeProvider = new();

    private readonly AppDbContext _db;
    private readonly IFileStorageService _fileStorage;
    private readonly ImageCompressionService _imageCompression;
    private readonly ProjectService _projectService;

    public ProjectAttachmentService(AppDbContext db, IFileStorageService fileStorage, ImageCompressionService imageCompression,
        ProjectService projectService)
    {
        _db = db;
        _fileStorage = fileStorage;
        _imageCompression = imageCompression;
        _projectService = projectService;
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

    public async Task<List<ProjectAttachmentUploadResultDto>> UploadManyAsync(int projectId, IReadOnlyList<IFormFile> files, string? description, int userId)
    {
        var project = await _projectService.GetByIdAsync(projectId);
        var photoNamePrefix = FileNamingHelper.Sanitize(project?.ProjectName ?? "project");
        var photoSequence = (await GetRowsByProjectAsync(projectId)).Count(r => PhotoExtensions.Contains(r.FileType.ToLowerInvariant())) + 1;

        var results = new List<ProjectAttachmentUploadResultDto>();
        foreach (var file in files)
        {
            var isPhoto = PhotoExtensions.Contains(Path.GetExtension(file.FileName).TrimStart('.').ToLowerInvariant());
            var result = await UploadOneAsync(projectId, file, description, userId, isPhoto ? photoNamePrefix : null, photoSequence);
            if (result.Success && isPhoto) photoSequence++;
            results.Add(result);
        }
        return results;
    }

    // Lampiran bertipe foto (jpg/png) diberi nama "NamaProject (n)" supaya tidak ambigu antar
    // project bernama sama; lampiran dokumen (pdf/xlsx) tetap pakai nama file asli.
    private async Task<ProjectAttachmentUploadResultDto> UploadOneAsync(int projectId, IFormFile file, string? description, int userId, string? photoNamePrefix, int photoSequence)
    {
        var result = new ProjectAttachmentUploadResultDto { FileName = file.FileName };

        if (file.Length == 0)
        {
            result.Error = "File kosong.";
            return result;
        }

        if (file.Length > MaxFileSizeBytes)
        {
            result.Error = "Ukuran file maksimal 10 MB.";
            return result;
        }

        var extension = Path.GetExtension(file.FileName).TrimStart('.').ToLowerInvariant();
        if (!AllowedExtensions.Contains(extension))
        {
            result.Error = "Tipe file hanya boleh jpg, png, pdf, atau xlsx.";
            return result;
        }

        CompressResult compressed;
        try
        {
            using var inputStream = file.OpenReadStream();
            compressed = await _imageCompression.CompressAsync(inputStream, extension);
        }
        catch (InvalidOperationException ex)
        {
            result.Error = ex.Message;
            return result;
        }

        using (compressed.Stream)
        {
            var fileType = compressed.FileExtension;
            var finalFileName = photoNamePrefix is not null
                ? $"{photoNamePrefix} ({photoSequence}).{fileType}"
                : $"{Path.GetFileNameWithoutExtension(file.FileName)}.{fileType}";

            var relativePath = await _fileStorage.SaveAsync(compressed.Stream, finalFileName, $"projects/{projectId}");

            var actionParam = new SqlParameter("@Action", "CREATE");
            var projectIdParam = new SqlParameter("@ProjectId", projectId);
            var fileNameParam = new SqlParameter("@FileName", finalFileName);
            var filePathParam = new SqlParameter("@FilePath", relativePath);
            var fileSizeKbParam = new SqlParameter("@FileSizeKb", compressed.SizeKb);
            var fileTypeParam = new SqlParameter("@FileType", fileType);
            var descriptionParam = new SqlParameter("@Description", (object?)description ?? DBNull.Value);
            var userIdParam = new SqlParameter("@UserId", userId);

            try
            {
                await _db.Database.ExecuteSqlRawAsync(
                    "EXEC SIS_ProjectAttachment_Manage @Action = @Action, @ProjectId = @ProjectId, @FileName = @FileName, @FilePath = @FilePath, @FileSizeKb = @FileSizeKb, @FileType = @FileType, @Description = @Description, @UserId = @UserId",
                    actionParam, projectIdParam, fileNameParam, filePathParam, fileSizeKbParam, fileTypeParam, descriptionParam, userIdParam);
                result.Success = true;
            }
            catch (SqlException ex)
            {
                result.Error = ex.Message;
            }
        }

        return result;
    }

    public async Task<(Stream Stream, string ContentType, string FileName)?> GetFirstPhotoForDownloadAsync(int projectId)
    {
        var rows = await GetRowsByProjectAsync(projectId);
        var row = rows.FirstOrDefault(r => PhotoExtensions.Contains(r.FileType.ToLowerInvariant()));
        if (row is null) return null;

        if (!ContentTypeProvider.TryGetContentType(row.FileName, out var contentType))
            contentType = "application/octet-stream";

        var stream = _fileStorage.OpenRead(row.FilePath);
        return (stream, contentType, row.FileName);
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

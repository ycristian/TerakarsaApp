using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Services;

public class ArticlePhotoRow
{
    public int Id { get; set; }
    public int ArticleId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public int FileSizeKb { get; set; }
    public bool IsPrimary { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
}

public class ArticlePhotoService
{
    private static readonly string[] AllowedExtensions = { "jpg", "jpeg", "png" };
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;
    // Kualitas JPEG thumbnail kartu WIP -- lebih rendah dari foto asli (80) karena hanya
    // dilihat 64x64 di tablet.
    private const int ThumbnailQuality = 70;
    private static readonly FileExtensionContentTypeProvider ContentTypeProvider = new();

    private readonly AppDbContext _db;
    private readonly IFileStorageService _fileStorage;
    private readonly ImageCompressionService _imageCompression;
    private readonly ArticleService _articleService;
    private readonly ProjectService _projectService;

    public ArticlePhotoService(AppDbContext db, IFileStorageService fileStorage, ImageCompressionService imageCompression,
        ArticleService articleService, ProjectService projectService)
    {
        _db = db;
        _fileStorage = fileStorage;
        _imageCompression = imageCompression;
        _articleService = articleService;
        _projectService = projectService;
    }

    public async Task<List<ArticlePhotoDto>> GetByArticleAsync(int articleId)
    {
        var rows = await GetRowsByArticleAsync(articleId);
        return rows.Select(r => new ArticlePhotoDto
        {
            Id = r.Id,
            ArticleId = r.ArticleId,
            FileName = r.FileName,
            FileSizeKb = r.FileSizeKb,
            IsPrimary = r.IsPrimary,
            CreatedAt = r.CreatedAt,
            CreatedBy = r.CreatedBy
        }).ToList();
    }

    public async Task<List<ArticlePhotoUploadResultDto>> UploadManyAsync(int articleId, IReadOnlyList<IFormFile> files, int userId)
    {
        var namePrefix = await BuildFileNamePrefixAsync(articleId);
        var sequence = (await GetRowsByArticleAsync(articleId)).Count + 1;

        var results = new List<ArticlePhotoUploadResultDto>();
        foreach (var file in files)
        {
            var result = await UploadOneAsync(articleId, file, userId, namePrefix, sequence);
            if (result.Success) sequence++;
            results.Add(result);
        }
        return results;
    }

    // Nama file foto disamakan dengan "NamaProject - NamaArtikel (n)" supaya tidak
    // ambigu ketika ada artikel dengan nama sama di project berbeda (Prompt: foto preview + naming).
    private async Task<string> BuildFileNamePrefixAsync(int articleId)
    {
        var article = await _articleService.GetByIdAsync(articleId);
        if (article is null) return "artikel";

        var project = await _projectService.GetByIdAsync(article.ProjectId);
        var prefix = project is not null ? $"{project.ProjectName} - {article.ArticleName}" : article.ArticleName;
        return FileNamingHelper.Sanitize(prefix);
    }

    private async Task<ArticlePhotoUploadResultDto> UploadOneAsync(int articleId, IFormFile file, int userId, string namePrefix, int sequence)
    {
        var result = new ArticlePhotoUploadResultDto { FileName = file.FileName };

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
            result.Error = "Tipe file hanya boleh jpg atau png.";
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
            var finalFileName = $"{namePrefix} ({sequence}).{compressed.FileExtension}";

            var relativePath = await _fileStorage.SaveAsync(compressed.Stream, finalFileName, $"articles/{articleId}");

            var actionParam = new SqlParameter("@Action", "CREATE");
            var articleIdParam = new SqlParameter("@ArticleId", articleId);
            var fileNameParam = new SqlParameter("@FileName", finalFileName);
            var filePathParam = new SqlParameter("@FilePath", relativePath);
            var fileSizeKbParam = new SqlParameter("@FileSizeKb", compressed.SizeKb);
            var userIdParam = new SqlParameter("@UserId", userId);

            try
            {
                await _db.Database.ExecuteSqlRawAsync(
                    "EXEC SIS_ArticlePhoto_Manage @Action = @Action, @ArticleId = @ArticleId, @FileName = @FileName, @FilePath = @FilePath, @FileSizeKb = @FileSizeKb, @UserId = @UserId",
                    actionParam, articleIdParam, fileNameParam, filePathParam, fileSizeKbParam, userIdParam);
                result.Success = true;
            }
            catch (SqlException ex)
            {
                result.Error = ex.Message;
            }
        }

        return result;
    }

    public async Task<(Stream Stream, string ContentType, string FileName)?> GetPrimaryPhotoForDownloadAsync(int articleId)
    {
        var rows = await GetRowsByArticleAsync(articleId);
        var row = rows.FirstOrDefault(r => r.IsPrimary) ?? rows.FirstOrDefault();
        if (row is null) return null;

        return OpenForDownload(row);
    }

    public async Task<(Stream Stream, string ContentType, string FileName)?> GetFileForDownloadAsync(int articleId, int photoId)
    {
        var rows = await GetRowsByArticleAsync(articleId);
        var row = rows.FirstOrDefault(r => r.Id == photoId);
        if (row is null) return null;

        return OpenForDownload(row);
    }

    public async Task<(Stream Stream, string ContentType, string FileName)?> GetFirstPhotoForProjectForDownloadAsync(int projectId)
    {
        var actionParam = new SqlParameter("@Action", "GETFIRSTFORPROJECT");
        var projectIdParam = new SqlParameter("@ProjectId", projectId);

        var rows = await _db.Database
            .SqlQueryRaw<ArticlePhotoRow>(
                "EXEC SIS_ArticlePhoto_Manage @Action = @Action, @ProjectId = @ProjectId",
                actionParam, projectIdParam)
            .ToListAsync();

        var row = rows.FirstOrDefault();
        if (row is null) return null;

        return OpenForDownload(row);
    }

    private (Stream Stream, string ContentType, string FileName)? OpenForDownload(ArticlePhotoRow row)
    {
        if (!_fileStorage.FileExists(row.FilePath)) return null;

        if (!ContentTypeProvider.TryGetContentType(row.FileName, out var contentType))
            contentType = "application/octet-stream";

        var stream = _fileStorage.OpenRead(row.FilePath);
        return (stream, contentType, row.FileName);
    }

    // Thumbnail kartu WIP /station: foto asli 1920px (rata-rata ~80 KB) jauh terlalu besar
    // untuk kotak 64x64. Versi kecil dibuat SEKALI lalu disimpan di subfolder "thumbs" di
    // samping file aslinya, jadi permintaan berikutnya cuma baca file -- tanpa decode ulang.
    // ETag dikembalikan supaya pemanggil bisa menyuruh browser menyimpan hasilnya; itu yang
    // membuat reload /station tidak mengunduh ulang foto sama sekali.
    public async Task<(Stream Stream, string ContentType, string ETag)?> GetPrimaryThumbnailAsync(int articleId, int maxWidth)
    {
        var row = await GetPrimaryRowAsync(articleId);
        if (row is null || !_fileStorage.FileExists(row.FilePath)) return null;

        // Foto utama yang diganti selalu baris baru = Id baru = ETag baru, jadi tidak perlu
        // ada pembersihan thumbnail lama -- yang basi cukup berhenti dirujuk.
        var etag = $"\"ap{row.Id}-w{maxWidth}\"";
        var thumbPath = BuildThumbPath(row.FilePath, maxWidth);

        if (_fileStorage.FileExists(thumbPath))
            return (_fileStorage.OpenRead(thumbPath), "image/jpeg", etag);

        CompressResult compressed;
        using (var source = _fileStorage.OpenRead(row.FilePath))
        {
            compressed = await _imageCompression.CompressAsync(
                source, Path.GetExtension(row.FilePath), maxWidth, ThumbnailQuality);
        }

        // Simpan untuk permintaan berikutnya. Kalau gagal (share jaringan terkunci, atau
        // request lain sedang menulis file yang sama) thumbnail tetap dikirim dari memori --
        // yang rugi cuma request ini, bukan operator.
        try
        {
            await _fileStorage.SaveAtAsync(compressed.Stream, thumbPath);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        compressed.Stream.Position = 0;
        return (compressed.Stream, "image/jpeg", etag);
    }

    // Foto utama ukuran penuh + ETag -- dipakai pratinjau layar penuh, yang hanya terambil
    // kalau operator mengetuk thumbnail.
    public async Task<(Stream Stream, string ContentType, string ETag)?> GetPrimaryOriginalAsync(int articleId)
    {
        var row = await GetPrimaryRowAsync(articleId);
        if (row is null || !_fileStorage.FileExists(row.FilePath)) return null;

        if (!ContentTypeProvider.TryGetContentType(row.FileName, out var contentType))
            contentType = "application/octet-stream";

        return (_fileStorage.OpenRead(row.FilePath), contentType, $"\"ap{row.Id}-full\"");
    }

    private async Task<ArticlePhotoRow?> GetPrimaryRowAsync(int articleId)
    {
        var rows = await GetRowsByArticleAsync(articleId);
        return rows.FirstOrDefault(r => r.IsPrimary) ?? rows.FirstOrDefault();
    }

    private static string BuildThumbPath(string filePath, int maxWidth)
    {
        var normalized = filePath.Replace('\\', '/');
        var dir = Path.GetDirectoryName(normalized)?.Replace('\\', '/') ?? string.Empty;
        var thumbName = $"{Path.GetFileNameWithoutExtension(normalized)}_w{maxWidth}.jpg";
        return string.IsNullOrEmpty(dir) ? $"thumbs/{thumbName}" : $"{dir}/thumbs/{thumbName}";
    }

    public async Task SetPrimaryAsync(int photoId)
    {
        var actionParam = new SqlParameter("@Action", "SETPRIMARY");
        var idParam = new SqlParameter("@Id", photoId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_ArticlePhoto_Manage @Action = @Action, @Id = @Id",
            actionParam, idParam);
    }

    public async Task DeleteAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_ArticlePhoto_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }

    private async Task<List<ArticlePhotoRow>> GetRowsByArticleAsync(int articleId)
    {
        var actionParam = new SqlParameter("@Action", "GETBYARTICLE");
        var articleIdParam = new SqlParameter("@ArticleId", articleId);

        return await _db.Database
            .SqlQueryRaw<ArticlePhotoRow>(
                "EXEC SIS_ArticlePhoto_Manage @Action = @Action, @ArticleId = @ArticleId",
                actionParam, articleIdParam)
            .ToListAsync();
    }
}

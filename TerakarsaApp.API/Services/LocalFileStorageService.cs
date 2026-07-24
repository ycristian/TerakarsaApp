namespace TerakarsaApp.API.Services;

public class LocalFileStorageService : IFileStorageService
{
    private readonly string _basePath;

    public LocalFileStorageService(IConfiguration configuration)
    {
        _basePath = configuration["FileStorage:BasePath"]
            ?? throw new InvalidOperationException("FileStorage:BasePath belum dikonfigurasi.");
    }

    public async Task<string> SaveAsync(Stream content, string fileNameWithExtension, string subfolder)
    {
        var folder = Path.Combine(_basePath, subfolder);
        Directory.CreateDirectory(folder);

        var extension = Path.GetExtension(fileNameWithExtension);
        var diskFileName = $"{Guid.NewGuid()}{extension}";
        var fullPath = Path.Combine(folder, diskFileName);

        content.Position = 0;
        using (var stream = new FileStream(fullPath, FileMode.Create))
        {
            await content.CopyToAsync(stream);
        }

        return Path.Combine(subfolder, diskFileName).Replace('\\', '/');
    }

    public Stream OpenRead(string relativePath)
    {
        var fullPath = Path.Combine(_basePath, relativePath);
        return new FileStream(fullPath, FileMode.Open, FileAccess.Read);
    }

    public bool FileExists(string relativePath)
    {
        var fullPath = Path.Combine(_basePath, relativePath);
        return File.Exists(fullPath);
    }
}

namespace TerakarsaApp.API.Services;

public class LocalFileStorageService : IFileStorageService
{
    private readonly string _basePath;

    public LocalFileStorageService(IConfiguration configuration)
    {
        _basePath = configuration["FileStorage:BasePath"]
            ?? throw new InvalidOperationException("FileStorage:BasePath belum dikonfigurasi.");
    }

    public async Task<(string RelativePath, long SizeKb)> SaveAsync(IFormFile file, string subfolder)
    {
        var folder = Path.Combine(_basePath, subfolder);
        Directory.CreateDirectory(folder);

        var diskFileName = $"{Guid.NewGuid()}{Path.GetExtension(file.FileName)}";
        var fullPath = Path.Combine(folder, diskFileName);

        using (var stream = new FileStream(fullPath, FileMode.Create))
        {
            await file.CopyToAsync(stream);
        }

        var relativePath = Path.Combine(subfolder, diskFileName).Replace('\\', '/');
        var sizeKb = (long)Math.Ceiling(file.Length / 1024.0);
        return (relativePath, sizeKb);
    }

    public Stream OpenRead(string relativePath)
    {
        var fullPath = Path.Combine(_basePath, relativePath);
        return new FileStream(fullPath, FileMode.Open, FileAccess.Read);
    }
}

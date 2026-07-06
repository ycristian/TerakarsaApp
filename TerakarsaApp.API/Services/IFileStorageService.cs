namespace TerakarsaApp.API.Services;

public interface IFileStorageService
{
    Task<(string RelativePath, long SizeKb)> SaveAsync(IFormFile file, string subfolder);

    Stream OpenRead(string relativePath);
}

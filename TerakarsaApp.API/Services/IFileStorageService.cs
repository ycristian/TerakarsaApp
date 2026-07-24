namespace TerakarsaApp.API.Services;

public interface IFileStorageService
{
    Task<string> SaveAsync(Stream content, string fileNameWithExtension, string subfolder);

    Stream OpenRead(string relativePath);

    bool FileExists(string relativePath);
}

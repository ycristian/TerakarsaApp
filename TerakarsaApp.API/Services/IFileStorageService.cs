namespace TerakarsaApp.API.Services;

public interface IFileStorageService
{
    Task<string> SaveAsync(Stream content, string fileNameWithExtension, string subfolder);

    Stream OpenRead(string relativePath);

    bool FileExists(string relativePath);

    // Prompt 71: foto SKU benang hanya satu per SKU -- file lama dihapus saat diganti.
    void Delete(string relativePath);
}

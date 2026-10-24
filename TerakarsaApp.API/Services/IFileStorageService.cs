namespace TerakarsaApp.API.Services;

public interface IFileStorageService
{
    Task<string> SaveAsync(Stream content, string fileNameWithExtension, string subfolder);

    // Simpan ke path yang SUDAH ditentukan pemanggil (bukan nama GUID baru seperti
    // SaveAsync). Dipakai berkas turunan yang namanya harus bisa ditebak ulang, mis.
    // thumbnail foto artikel.
    Task SaveAtAsync(Stream content, string relativePath);

    Stream OpenRead(string relativePath);

    bool FileExists(string relativePath);

    // Prompt 71: foto SKU benang hanya satu per SKU -- file lama dihapus saat diganti.
    void Delete(string relativePath);
}

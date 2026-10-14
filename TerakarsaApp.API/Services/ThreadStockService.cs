using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.API.Services;

// Prompt 71: master module Stok Benang (schema inv) -- jenis benang, merk, lokasi (rak),
// SKU + fotonya. SELURUH validasi bisnis ada di inv.SIS_Thread*_Manage; service hanya
// meneruskan parameter dan menerjemahkan SqlException jadi pesan untuk UI.
//
// Saldo stok TIDAK pernah ditulis dari sini: inv.thread_stocks hanya boleh diubah SP
// movement (Prompt 72).
public class ThreadStockService
{
    // Foto SKU dipakai sebagai thumbnail di HP -- 800px/JPEG 80 cukup, jauh lebih kecil
    // dari foto artikel produksi (1920px).
    private const int PhotoMaxWidth = 800;
    private const int PhotoQuality = 80;
    private const long MaxPhotoBytes = 10 * 1024 * 1024;
    private static readonly string[] AllowedPhotoExtensions = { "jpg", "jpeg", "png" };
    public const string PhotoFolder = "thread";

    private readonly AppDbContext _db;
    private readonly IFileStorageService _fileStorage;
    private readonly ImageCompressionService _imageCompression;

    public ThreadStockService(AppDbContext db, IFileStorageService fileStorage,
        ImageCompressionService imageCompression)
    {
        _db = db;
        _fileStorage = fileStorage;
        _imageCompression = imageCompression;
    }

    // ==================== JENIS BENANG ====================

    public Task<List<ThreadTypeDto>> GetTypesAsync() =>
        _db.Database.SqlQueryRaw<ThreadTypeDto>("EXEC inv.SIS_ThreadType_List").ToListAsync();

    public async Task<(bool Success, string Error, int Id)> SaveTypeAsync(ThreadTypeSaveRequest request, int userId)
    {
        var action = request.ThreadTypeId.HasValue ? "UPDATE" : "CREATE";

        return await ManageAsync(
            @"EXEC inv.SIS_ThreadType_Manage @Action = @Action, @Id = @Id, @Code = @Code,
                @Name = @Name, @SortOrder = @SortOrder, @UserId = @UserId",
            action == "CREATE",
            new SqlParameter("@Action", action),
            new SqlParameter("@Id", request.ThreadTypeId ?? (object)DBNull.Value),
            new SqlParameter("@Code", request.Code ?? string.Empty),
            new SqlParameter("@Name", request.Name ?? string.Empty),
            new SqlParameter("@SortOrder", request.SortOrder),
            new SqlParameter("@UserId", userId));
    }

    public async Task<(bool Success, string Error)> DeleteTypeAsync(int id, int userId)
    {
        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadType_Manage @Action = 'DELETE', @Id = @Id, @UserId = @UserId",
            false,
            new SqlParameter("@Id", id),
            new SqlParameter("@UserId", userId));

        return (success, error);
    }

    // ==================== MERK ====================

    public Task<List<ThreadBrandDto>> GetBrandsAsync() =>
        _db.Database.SqlQueryRaw<ThreadBrandDto>("EXEC inv.SIS_ThreadBrand_List").ToListAsync();

    // CREATE dipanggil juga inline dari form SKU -- id merk baru ikut dikembalikan.
    public async Task<(bool Success, string Error, int Id)> SaveBrandAsync(ThreadBrandSaveRequest request, int userId)
    {
        var action = request.ThreadBrandId.HasValue ? "UPDATE" : "CREATE";

        return await ManageAsync(
            "EXEC inv.SIS_ThreadBrand_Manage @Action = @Action, @Id = @Id, @Name = @Name, @UserId = @UserId",
            action == "CREATE",
            new SqlParameter("@Action", action),
            new SqlParameter("@Id", request.ThreadBrandId ?? (object)DBNull.Value),
            new SqlParameter("@Name", request.Name ?? string.Empty),
            new SqlParameter("@UserId", userId));
    }

    public async Task<(bool Success, string Error)> DeleteBrandAsync(int id, int userId)
    {
        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadBrand_Manage @Action = 'DELETE', @Id = @Id, @UserId = @UserId",
            false,
            new SqlParameter("@Id", id),
            new SqlParameter("@UserId", userId));

        return (success, error);
    }

    // ==================== LOKASI (RAK) ====================

    public Task<List<ThreadLocationDto>> GetLocationsAsync(bool hanyaAktif = false) =>
        _db.Database.SqlQueryRaw<ThreadLocationDto>(
                "EXEC inv.SIS_ThreadLocation_List @HanyaAktif = @HanyaAktif",
                new SqlParameter("@HanyaAktif", hanyaAktif))
            .ToListAsync();

    public async Task<(bool Success, string Error, int Id)> SaveLocationAsync(ThreadLocationSaveRequest request, int userId)
    {
        var action = request.ThreadLocationId.HasValue ? "UPDATE" : "CREATE";

        return await ManageAsync(
            @"EXEC inv.SIS_ThreadLocation_Manage @Action = @Action, @Id = @Id, @Code = @Code,
                @Name = @Name, @SortOrder = @SortOrder, @UserId = @UserId",
            action == "CREATE",
            new SqlParameter("@Action", action),
            new SqlParameter("@Id", request.ThreadLocationId ?? (object)DBNull.Value),
            new SqlParameter("@Code", request.Code ?? string.Empty),
            new SqlParameter("@Name", (object?)request.Name ?? DBNull.Value),
            new SqlParameter("@SortOrder", request.SortOrder),
            new SqlParameter("@UserId", userId));
    }

    public async Task<(bool Success, string Error)> SetLocationActiveAsync(int id, bool isActive, int userId)
    {
        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadLocation_Manage @Action = 'SETACTIVE', @Id = @Id, @IsActive = @IsActive, @UserId = @UserId",
            false,
            new SqlParameter("@Id", id),
            new SqlParameter("@IsActive", isActive),
            new SqlParameter("@UserId", userId));

        return (success, error);
    }

    public async Task<(bool Success, string Error)> DeleteLocationAsync(int id, int userId)
    {
        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadLocation_Manage @Action = 'DELETE', @Id = @Id, @UserId = @UserId",
            false,
            new SqlParameter("@Id", id),
            new SqlParameter("@UserId", userId));

        return (success, error);
    }

    // ==================== SKU ====================

    public async Task<ThreadItemListResult> GetItemsAsync(string? search, int? typeId, int? locationId,
        bool hanyaAktif, string? sortColumn, string? sortDirection, int pageNumber, int pageSize)
    {
        var items = await _db.Database
            .SqlQueryRaw<ThreadItemDto>(
                @"EXEC inv.SIS_ThreadItem_List @Search = @Search, @TypeId = @TypeId,
                    @LocationId = @LocationId, @HanyaAktif = @HanyaAktif,
                    @SortColumn = @SortColumn, @SortDirection = @SortDirection,
                    @PageNumber = @PageNumber, @PageSize = @PageSize",
                new SqlParameter("@Search", string.IsNullOrWhiteSpace(search) ? DBNull.Value : search),
                new SqlParameter("@TypeId", typeId ?? (object)DBNull.Value),
                new SqlParameter("@LocationId", locationId ?? (object)DBNull.Value),
                new SqlParameter("@HanyaAktif", hanyaAktif),
                new SqlParameter("@SortColumn", (object?)sortColumn ?? DBNull.Value),
                new SqlParameter("@SortDirection", sortDirection ?? "asc"),
                new SqlParameter("@PageNumber", pageNumber),
                new SqlParameter("@PageSize", pageSize))
            .ToListAsync();

        return new ThreadItemListResult
        {
            Items = items,
            TotalCount = items.FirstOrDefault()?.TotalCount ?? 0
        };
    }

    // inv.SIS_ThreadItem_GetById punya 3 result set; EF hanya bisa membaca satu per
    // pemanggilan, jadi dipanggil 3x dengan @Bagian (lihat komentar di SP).
    public async Task<ThreadItemDetailDto?> GetItemByIdAsync(int id)
    {
        var item = (await _db.Database
            .SqlQueryRaw<ThreadItemDto>(
                "EXEC inv.SIS_ThreadItem_GetById @Id = @Id, @Bagian = 'ITEM'",
                new SqlParameter("@Id", id))
            .ToListAsync()).FirstOrDefault();

        if (item is null) return null;

        var locations = await _db.Database
            .SqlQueryRaw<ThreadItemStockDto>(
                "EXEC inv.SIS_ThreadItem_GetById @Id = @Id, @Bagian = 'LOKASI'",
                new SqlParameter("@Id", id))
            .ToListAsync();

        var splits = await _db.Database
            .SqlQueryRaw<ThreadSplitConeDto>(
                "EXEC inv.SIS_ThreadItem_GetById @Id = @Id, @Bagian = 'SPLIT'",
                new SqlParameter("@Id", id))
            .ToListAsync();

        return new ThreadItemDetailDto { Item = item, Locations = locations, SplitCones = splits };
    }

    // Hasil scan QR label SKU (`TB:<sku_code>`). Prompt 72 memakai ini untuk Ambil.
    public async Task<ThreadItemDto?> GetItemBySkuAsync(string skuCode)
    {
        var rows = await _db.Database
            .SqlQueryRaw<ThreadItemDto>(
                "EXEC inv.SIS_ThreadItem_GetBySku @SkuCode = @SkuCode",
                new SqlParameter("@SkuCode", skuCode ?? string.Empty))
            .ToListAsync();

        return rows.FirstOrDefault();
    }

    public async Task<(bool Success, string Error, int Id)> SaveItemAsync(ThreadItemSaveRequest request, int userId)
    {
        var action = request.ThreadItemId.HasValue ? "UPDATE" : "CREATE";

        return await ManageAsync(
            @"EXEC inv.SIS_ThreadItem_Manage @Action = @Action, @Id = @Id, @TypeId = @TypeId,
                @BrandId = @BrandId, @ColorName = @ColorName, @ColorCode = @ColorCode,
                @ConeSize = @ConeSize, @UserId = @UserId",
            action == "CREATE",
            new SqlParameter("@Action", action),
            new SqlParameter("@Id", request.ThreadItemId ?? (object)DBNull.Value),
            new SqlParameter("@TypeId", request.ThreadTypeId),
            new SqlParameter("@BrandId", request.ThreadBrandId),
            new SqlParameter("@ColorName", request.ColorName ?? string.Empty),
            new SqlParameter("@ColorCode", request.ColorCode ?? string.Empty),
            new SqlParameter("@ConeSize", request.ConeSize ?? string.Empty),
            new SqlParameter("@UserId", userId));
    }

    public async Task<(bool Success, string Error)> SetItemActiveAsync(int id, bool isActive, int userId)
    {
        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadItem_Manage @Action = 'SETACTIVE', @Id = @Id, @IsActive = @IsActive, @UserId = @UserId",
            false,
            new SqlParameter("@Id", id),
            new SqlParameter("@IsActive", isActive),
            new SqlParameter("@UserId", userId));

        return (success, error);
    }

    public async Task<(bool Success, string Error)> DeleteItemAsync(int id, int userId)
    {
        var detail = await GetItemByIdAsync(id);

        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadItem_Manage @Action = 'DELETE', @Id = @Id, @UserId = @UserId",
            false,
            new SqlParameter("@Id", id),
            new SqlParameter("@UserId", userId));

        if (success && !string.IsNullOrWhiteSpace(detail?.Item?.PhotoPath))
            _fileStorage.Delete(detail!.Item!.PhotoPath!);

        return (success, error);
    }

    // ==================== FOTO SKU ====================

    public async Task<(bool Success, string Error, string? PhotoPath)> UploadPhotoAsync(
        int itemId, IFormFile file, int userId)
    {
        if (file is null || file.Length == 0)
            return (false, "File kosong.", null);

        if (file.Length > MaxPhotoBytes)
            return (false, "Ukuran file maksimal 10 MB.", null);

        var extension = Path.GetExtension(file.FileName).TrimStart('.').ToLowerInvariant();
        if (!AllowedPhotoExtensions.Contains(extension))
            return (false, "Tipe file hanya boleh jpg atau png.", null);

        var detail = await GetItemByIdAsync(itemId);
        if (detail?.Item is null)
            return (false, "SKU tidak ditemukan.", null);

        CompressResult compressed;
        try
        {
            using var inputStream = file.OpenReadStream();
            compressed = await _imageCompression.CompressAsync(inputStream, extension, PhotoMaxWidth, PhotoQuality);
        }
        catch (InvalidOperationException ex)
        {
            return (false, ex.Message, null);
        }

        string relativePath;
        using (compressed.Stream)
        {
            // Nama file di disk = GUID (dibuat LocalFileStorageService); nama asli tidak
            // dipakai karena satu SKU hanya punya satu foto dan tidak pernah di-download.
            relativePath = await _fileStorage.SaveAsync(
                compressed.Stream, $"sku.{compressed.FileExtension}", PhotoFolder);
        }

        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadItem_Manage @Action = 'SETPHOTO', @Id = @Id, @PhotoPath = @PhotoPath, @UserId = @UserId",
            false,
            new SqlParameter("@Id", itemId),
            new SqlParameter("@PhotoPath", relativePath),
            new SqlParameter("@UserId", userId));

        if (!success)
        {
            _fileStorage.Delete(relativePath);
            return (false, error, null);
        }

        var oldPath = detail.Item.PhotoPath;
        if (!string.IsNullOrWhiteSpace(oldPath) && oldPath != relativePath)
            _fileStorage.Delete(oldPath!);

        return (true, string.Empty, relativePath);
    }

    public async Task<(bool Success, string Error)> DeletePhotoAsync(int itemId, int userId)
    {
        var detail = await GetItemByIdAsync(itemId);
        if (detail?.Item is null) return (false, "SKU tidak ditemukan.");

        var (success, error, _) = await ManageAsync(
            "EXEC inv.SIS_ThreadItem_Manage @Action = 'SETPHOTO', @Id = @Id, @PhotoPath = NULL, @UserId = @UserId",
            false,
            new SqlParameter("@Id", itemId),
            new SqlParameter("@UserId", userId));

        if (success && !string.IsNullOrWhiteSpace(detail.Item.PhotoPath))
            _fileStorage.Delete(detail.Item.PhotoPath!);

        return (success, error);
    }

    // Foto dibaca lewat nama file GUID-nya saja (tanpa sub-path) supaya tidak bisa
    // dipakai menjelajah folder lain di FileStorage.
    public (Stream Stream, string ContentType)? OpenPhoto(string fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName)) return null;
        if (fileName.Contains('/') || fileName.Contains('\\') || fileName.Contains("..")) return null;

        var extension = Path.GetExtension(fileName).TrimStart('.').ToLowerInvariant();
        if (extension is not ("jpg" or "jpeg" or "png")) return null;

        if (!Guid.TryParse(Path.GetFileNameWithoutExtension(fileName), out _)) return null;

        var relativePath = $"{PhotoFolder}/{fileName}";
        if (!_fileStorage.FileExists(relativePath)) return null;

        var contentType = extension == "png" ? "image/png" : "image/jpeg";
        return (_fileStorage.OpenRead(relativePath), contentType);
    }

    // ==================== LABEL (Prompt 73) ====================

    // Label TIDAK pernah dibuat otomatis setelah RETURN -- selalu lewat tombol,
    // supaya admin gudang menempel label setelah yakin kones & beratnya benar.
    public async Task<(bool Success, string Error, int PrintJobId)> EnqueueLabelAsync(
        string kind, int refId, int copies, int userId)
    {
        return await ManageAsync(
            "EXEC inv.SIS_ThreadLabel_Enqueue @Kind = @Kind, @RefId = @RefId, @Copies = @Copies, @UserId = @UserId",
            true,
            new SqlParameter("@Kind", kind),
            new SqlParameter("@RefId", refId),
            new SqlParameter("@Copies", copies),
            new SqlParameter("@UserId", userId));
    }

    public Task<List<ThreadLabelJobDto>> GetLabelStatusAsync(string kind, int refId, int top) =>
        _db.Database.SqlQueryRaw<ThreadLabelJobDto>(
                "EXEC inv.SIS_ThreadLabel_Status @Kind = @Kind, @RefId = @RefId, @Top = @Top",
                new SqlParameter("@Kind", kind),
                new SqlParameter("@RefId", refId),
                new SqlParameter("@Top", top))
            .ToListAsync();

    // ==================== bantuan ====================

    // returnsId = true untuk Action CREATE: SP mengembalikan id baru di kolom Value.
    private async Task<(bool Success, string Error, int Id)> ManageAsync(
        string sql, bool returnsId, params SqlParameter[] parameters)
    {
        try
        {
            if (returnsId)
            {
                var ids = await _db.Database.SqlQueryRaw<int>(sql, parameters).ToListAsync();
                return (true, string.Empty, ids.FirstOrDefault());
            }

            await _db.Database.ExecuteSqlRawAsync(sql, parameters);
            return (true, string.Empty, 0);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }
}

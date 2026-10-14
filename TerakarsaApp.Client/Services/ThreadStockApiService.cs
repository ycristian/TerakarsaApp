using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Components.Forms;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.Client.Services;

// Prompt 71: master module Stok Benang (api/gudang/benang). JWT biasa -- module
// INV_THREAD dicek di server.
public class ThreadStockApiService
{
    private const long MaxPhotoBytes = 10 * 1024 * 1024;

    private readonly HttpClient _http;

    public ThreadStockApiService(HttpClient http)
    {
        _http = http;
    }

    // ==================== JENIS BENANG ====================

    public async Task<List<ThreadTypeDto>> GetTypesAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/types");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadTypeDto>>() ?? new();
    }

    public async Task<(bool Success, string Error, int Id)> SaveTypeAsync(ThreadTypeSaveRequest request)
    {
        var response = request.ThreadTypeId.HasValue
            ? await _http.PutAsJsonAsync($"api/gudang/benang/types/{request.ThreadTypeId.Value}", request)
            : await _http.PostAsJsonAsync("api/gudang/benang/types", request);

        return await ReadIdResultAsync(response);
    }

    public async Task<(bool Success, string Error)> DeleteTypeAsync(int id) =>
        await ReadResultAsync(await _http.DeleteAsync($"api/gudang/benang/types/{id}"));

    // ==================== MERK ====================

    public async Task<List<ThreadBrandDto>> GetBrandsAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/brands");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadBrandDto>>() ?? new();
    }

    public async Task<(bool Success, string Error, int Id)> SaveBrandAsync(ThreadBrandSaveRequest request)
    {
        var response = request.ThreadBrandId.HasValue
            ? await _http.PutAsJsonAsync($"api/gudang/benang/brands/{request.ThreadBrandId.Value}", request)
            : await _http.PostAsJsonAsync("api/gudang/benang/brands", request);

        return await ReadIdResultAsync(response);
    }

    public async Task<(bool Success, string Error)> DeleteBrandAsync(int id) =>
        await ReadResultAsync(await _http.DeleteAsync($"api/gudang/benang/brands/{id}"));

    // ==================== LOKASI (RAK) ====================

    public async Task<List<ThreadLocationDto>> GetLocationsAsync(bool hanyaAktif = false)
    {
        var response = await _http.GetAsync(
            $"api/gudang/benang/locations?hanyaAktif={hanyaAktif.ToString().ToLowerInvariant()}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadLocationDto>>() ?? new();
    }

    public async Task<(bool Success, string Error, int Id)> SaveLocationAsync(ThreadLocationSaveRequest request)
    {
        var response = request.ThreadLocationId.HasValue
            ? await _http.PutAsJsonAsync($"api/gudang/benang/locations/{request.ThreadLocationId.Value}", request)
            : await _http.PostAsJsonAsync("api/gudang/benang/locations", request);

        return await ReadIdResultAsync(response);
    }

    public async Task<(bool Success, string Error)> SetLocationActiveAsync(int id, bool isActive) =>
        await ReadResultAsync(await _http.PutAsJsonAsync(
            $"api/gudang/benang/locations/{id}/setactive", new ThreadSetActiveRequest { IsActive = isActive }));

    public async Task<(bool Success, string Error)> DeleteLocationAsync(int id) =>
        await ReadResultAsync(await _http.DeleteAsync($"api/gudang/benang/locations/{id}"));

    // ==================== SKU ====================

    public async Task<ThreadItemListResult> GetItemsAsync(string? search = null, int? typeId = null,
        int? locationId = null, bool hanyaAktif = false, string? sortColumn = null,
        string? sortDirection = "asc", int pageNumber = 1, int pageSize = 50)
    {
        var url = $"api/gudang/benang/items?pageNumber={pageNumber}&pageSize={pageSize}" +
                  $"&hanyaAktif={hanyaAktif.ToString().ToLowerInvariant()}" +
                  $"&sortDirection={sortDirection}";

        if (!string.IsNullOrWhiteSpace(search)) url += $"&search={Uri.EscapeDataString(search)}";
        if (typeId.HasValue) url += $"&typeId={typeId.Value}";
        if (locationId.HasValue) url += $"&locationId={locationId.Value}";
        if (!string.IsNullOrWhiteSpace(sortColumn)) url += $"&sortColumn={sortColumn}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<ThreadItemListResult>() ?? new();
    }

    public async Task<ThreadItemDetailDto?> GetItemAsync(int id)
    {
        var response = await _http.GetAsync($"api/gudang/benang/items/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ThreadItemDetailDto>();
    }

    public async Task<ThreadItemDto?> GetItemBySkuAsync(string skuCode)
    {
        var response = await _http.GetAsync($"api/gudang/benang/items/by-sku/{Uri.EscapeDataString(skuCode)}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ThreadItemDto>();
    }

    public async Task<(bool Success, string Error, int Id)> SaveItemAsync(ThreadItemSaveRequest request)
    {
        var response = request.ThreadItemId.HasValue
            ? await _http.PutAsJsonAsync($"api/gudang/benang/items/{request.ThreadItemId.Value}", request)
            : await _http.PostAsJsonAsync("api/gudang/benang/items", request);

        return await ReadIdResultAsync(response);
    }

    public async Task<(bool Success, string Error)> SetItemActiveAsync(int id, bool isActive) =>
        await ReadResultAsync(await _http.PutAsJsonAsync(
            $"api/gudang/benang/items/{id}/setactive", new ThreadSetActiveRequest { IsActive = isActive }));

    public async Task<(bool Success, string Error)> DeleteItemAsync(int id) =>
        await ReadResultAsync(await _http.DeleteAsync($"api/gudang/benang/items/{id}"));

    // ==================== FOTO ====================

    public async Task<(bool Success, string Error, string? PhotoPath)> UploadPhotoAsync(int itemId, IBrowserFile file)
    {
        using var content = new MultipartFormDataContent();
        await using var stream = file.OpenReadStream(MaxPhotoBytes);

        var fileContent = new StreamContent(stream);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(
            string.IsNullOrWhiteSpace(file.ContentType) ? "application/octet-stream" : file.ContentType);
        content.Add(fileContent, "file", file.Name);

        var response = await _http.PostAsync($"api/gudang/benang/items/{itemId}/photo", content);
        var body = (await response.Content.ReadAsStringAsync()).Trim().Trim('"');

        if (response.IsSuccessStatusCode) return (true, string.Empty, body);
        return (false, string.IsNullOrWhiteSpace(body) ? "Gagal mengunggah foto." : body, null);
    }

    public async Task<(bool Success, string Error)> DeletePhotoAsync(int itemId) =>
        await ReadResultAsync(await _http.DeleteAsync($"api/gudang/benang/items/{itemId}/photo"));

    // URL <img src> foto SKU. photo_path tersimpan sebagai "thread/<guid>.jpg";
    // endpoint penyajinya tanpa login (lihat ThreadPhotoController).
    public string? PhotoUrl(string? photoPath)
    {
        if (string.IsNullOrWhiteSpace(photoPath)) return null;

        var fileName = photoPath.Split('/', '\\').Last();
        return $"{_http.BaseAddress}api/gudang/benang/photo/{fileName}";
    }

    // ==================== MOVEMENT (Prompt 72) ====================

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> ReceiveAsync(ThreadReceiveRequest request)
        => PostMovementAsync("receive", request);

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> IssueAsync(ThreadIssueRequest request)
        => PostMovementAsync("issue", request);

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> ReturnAsync(ThreadReturnRequest request)
        => PostMovementAsync("return", request);

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> IssueSplitAsync(ThreadIssueSplitRequest request)
        => PostMovementAsync("issue-split", request);

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> ReturnSplitAsync(ThreadReturnSplitRequest request)
        => PostMovementAsync("return-split", request);

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> MoveAsync(ThreadMoveRequest request)
        => PostMovementAsync("move", request);

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> MoveSplitAsync(ThreadMoveSplitRequest request)
        => PostMovementAsync("move-split", request);

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> EmptyAsync(ThreadEmptyRequest request)
        => PostMovementAsync("empty", request);

    public async Task<ThreadScanResultDto> ScanAsync(string code)
    {
        var response = await _http.GetAsync($"api/gudang/benang/scan/{Uri.EscapeDataString(code)}");
        if (!response.IsSuccessStatusCode) return new ThreadScanResultDto { RawCode = code };
        return await response.Content.ReadFromJsonAsync<ThreadScanResultDto>()
               ?? new ThreadScanResultDto { RawCode = code };
    }

    public async Task<List<ThreadItemStockDto>> GetStocksAsync(int itemId, bool hanyaAda = true)
    {
        var response = await _http.GetAsync(
            $"api/gudang/benang/items/{itemId}/stocks?hanyaAda={hanyaAda.ToString().ToLowerInvariant()}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadItemStockDto>>() ?? new();
    }

    public async Task<List<ThreadMovementDto>> GetMovementsAsync(int itemId, int top = 20)
    {
        var response = await _http.GetAsync($"api/gudang/benang/items/{itemId}/movements?top={top}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadMovementDto>>() ?? new();
    }

    public async Task<ThreadSplitConeDto?> GetSplitConeAsync(string coneCode)
    {
        var response = await _http.GetAsync($"api/gudang/benang/split-cones/{Uri.EscapeDataString(coneCode)}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ThreadSplitConeDto>();
    }

    public async Task<ThreadSplitConeDto?> GetSplitConeByIdAsync(int splitConeId)
    {
        var response = await _http.GetAsync($"api/gudang/benang/split-cones/id/{splitConeId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<ThreadSplitConeDto>();
    }

    public async Task<List<ThreadResourceLookupDto>> GetResourcesAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/lookup/resources");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadResourceLookupDto>>() ?? new();
    }

    public async Task<List<ThreadProjectLookupDto>> GetProjectsAsync()
    {
        var response = await _http.GetAsync("api/gudang/benang/lookup/projects");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<ThreadProjectLookupDto>>() ?? new();
    }

    private async Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> PostMovementAsync<T>(
        string jalur, T request)
    {
        var response = await _http.PostAsJsonAsync($"api/gudang/benang/movements/{jalur}", request);

        if (response.IsSuccessStatusCode)
        {
            var hasil = await response.Content.ReadFromJsonAsync<ThreadMovementResultDto>();
            return (true, string.Empty, hasil);
        }

        var (_, error) = await ReadResultAsync(response);
        return (false, error, null);
    }

    // ==================== bantuan ====================

    private static async Task<(bool Success, string Error)> ReadResultAsync(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = (await response.Content.ReadAsStringAsync()).Trim().Trim('"');
        return (false, string.IsNullOrWhiteSpace(error) ? "Terjadi kesalahan di server." : error);
    }

    private static async Task<(bool Success, string Error, int Id)> ReadIdResultAsync(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode)
        {
            var body = (await response.Content.ReadAsStringAsync()).Trim();
            int.TryParse(body, out var id);
            return (true, string.Empty, id);
        }

        var (_, error) = await ReadResultAsync(response);
        return (false, error, 0);
    }
}

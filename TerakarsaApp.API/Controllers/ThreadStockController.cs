using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.API.Controllers;

// Prompt 71: master module Stok Benang (schema inv). Dipakai admin gudang lewat HP
// dengan LOGIN (bukan perangkat/station) -- created_by selalu user yang login.
[ApiController]
[Route("api/gudang/benang")]
[Authorize]
[RequireModule("INV_THREAD")]
public class ThreadStockController : ControllerBase
{
    private readonly ThreadStockService _threadService;

    public ThreadStockController(ThreadStockService threadService)
    {
        _threadService = threadService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    // ==================== JENIS BENANG ====================

    [HttpGet("types")]
    public async Task<IActionResult> GetTypes() => Ok(await _threadService.GetTypesAsync());

    [HttpPost("types")]
    public Task<IActionResult> CreateType([FromBody] ThreadTypeSaveRequest request)
        => SaveTypeAsync(request, null);

    [HttpPut("types/{id:int}")]
    public Task<IActionResult> UpdateType(int id, [FromBody] ThreadTypeSaveRequest request)
        => SaveTypeAsync(request, id);

    private async Task<IActionResult> SaveTypeAsync(ThreadTypeSaveRequest request, int? id)
    {
        request.ThreadTypeId = id;
        var (success, error, newId) = await _threadService.SaveTypeAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(newId);
    }

    [HttpDelete("types/{id:int}")]
    public async Task<IActionResult> DeleteType(int id)
    {
        var (success, error) = await _threadService.DeleteTypeAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // ==================== MERK ====================

    [HttpGet("brands")]
    public async Task<IActionResult> GetBrands() => Ok(await _threadService.GetBrandsAsync());

    // Dipanggil juga inline dari form SKU ("tambah merk baru") -- id merk baru dikembalikan.
    [HttpPost("brands")]
    public Task<IActionResult> CreateBrand([FromBody] ThreadBrandSaveRequest request)
        => SaveBrandAsync(request, null);

    [HttpPut("brands/{id:int}")]
    public Task<IActionResult> UpdateBrand(int id, [FromBody] ThreadBrandSaveRequest request)
        => SaveBrandAsync(request, id);

    private async Task<IActionResult> SaveBrandAsync(ThreadBrandSaveRequest request, int? id)
    {
        request.ThreadBrandId = id;
        var (success, error, newId) = await _threadService.SaveBrandAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(newId);
    }

    [HttpDelete("brands/{id:int}")]
    public async Task<IActionResult> DeleteBrand(int id)
    {
        var (success, error) = await _threadService.DeleteBrandAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // ==================== LOKASI (RAK) ====================

    [HttpGet("locations")]
    public async Task<IActionResult> GetLocations([FromQuery] bool hanyaAktif = false)
        => Ok(await _threadService.GetLocationsAsync(hanyaAktif));

    [HttpPost("locations")]
    public Task<IActionResult> CreateLocation([FromBody] ThreadLocationSaveRequest request)
        => SaveLocationAsync(request, null);

    [HttpPut("locations/{id:int}")]
    public Task<IActionResult> UpdateLocation(int id, [FromBody] ThreadLocationSaveRequest request)
        => SaveLocationAsync(request, id);

    private async Task<IActionResult> SaveLocationAsync(ThreadLocationSaveRequest request, int? id)
    {
        request.ThreadLocationId = id;
        var (success, error, newId) = await _threadService.SaveLocationAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(newId);
    }

    [HttpPut("locations/{id:int}/setactive")]
    public async Task<IActionResult> SetLocationActive(int id, [FromBody] ThreadSetActiveRequest request)
    {
        var (success, error) = await _threadService.SetLocationActiveAsync(id, request.IsActive, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("locations/{id:int}")]
    public async Task<IActionResult> DeleteLocation(int id)
    {
        var (success, error) = await _threadService.DeleteLocationAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // ==================== SKU ====================

    [HttpGet("items")]
    public async Task<IActionResult> GetItems(
        [FromQuery] string? search = null,
        [FromQuery] int? typeId = null,
        [FromQuery] int? locationId = null,
        [FromQuery] bool hanyaAktif = false,
        [FromQuery] string? sortColumn = null,
        [FromQuery] string? sortDirection = "asc",
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 50)
    {
        if (pageNumber < 1) pageNumber = 1;
        if (pageSize is < 1 or > 500) pageSize = 50;

        return Ok(await _threadService.GetItemsAsync(
            search, typeId, locationId, hanyaAktif, sortColumn, sortDirection, pageNumber, pageSize));
    }

    [HttpGet("items/{id:int}")]
    public async Task<IActionResult> GetItem(int id)
    {
        var detail = await _threadService.GetItemByIdAsync(id);
        if (detail is null) return NotFound();
        return Ok(detail);
    }

    // Hasil scan QR label SKU: isi QR `TB:<sku_code>` (awalan TB: ikut diterima SP).
    [HttpGet("items/by-sku/{skuCode}")]
    public async Task<IActionResult> GetItemBySku(string skuCode)
    {
        var item = await _threadService.GetItemBySkuAsync(skuCode);
        if (item is null) return NotFound();
        return Ok(item);
    }

    [HttpPost("items")]
    public Task<IActionResult> CreateItem([FromBody] ThreadItemSaveRequest request)
        => SaveItemAsync(request, null);

    [HttpPut("items/{id:int}")]
    public Task<IActionResult> UpdateItem(int id, [FromBody] ThreadItemSaveRequest request)
        => SaveItemAsync(request, id);

    private async Task<IActionResult> SaveItemAsync(ThreadItemSaveRequest request, int? id)
    {
        request.ThreadItemId = id;
        var (success, error, newId) = await _threadService.SaveItemAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(newId);
    }

    [HttpPut("items/{id:int}/setactive")]
    public async Task<IActionResult> SetItemActive(int id, [FromBody] ThreadSetActiveRequest request)
    {
        var (success, error) = await _threadService.SetItemActiveAsync(id, request.IsActive, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("items/{id:int}")]
    public async Task<IActionResult> DeleteItem(int id)
    {
        var (success, error) = await _threadService.DeleteItemAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // ==================== FOTO SKU ====================

    // Satu foto per SKU: upload baru menggantikan yang lama (file lama dihapus).
    [HttpPost("items/{id:int}/photo")]
    public async Task<IActionResult> UploadPhoto(int id, [FromForm] IFormFile? file)
    {
        if (file is null) return BadRequest("File wajib diunggah.");

        var (success, error, photoPath) = await _threadService.UploadPhotoAsync(id, file, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(photoPath);
    }

    [HttpDelete("items/{id:int}/photo")]
    public async Task<IActionResult> DeletePhoto(int id)
    {
        var (success, error) = await _threadService.DeletePhotoAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // GET foto: lihat ThreadPhotoController (tanpa [Authorize] -- <img src> tidak bisa
    // mengirim header Authorization).
}

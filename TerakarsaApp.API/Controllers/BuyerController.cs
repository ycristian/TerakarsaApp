using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Buyers;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("MASTER_BUYER")]
public class BuyerController : ControllerBase
{
    private readonly BuyerService _buyerService;

    public BuyerController(BuyerService buyerService)
    {
        _buyerService = buyerService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] BuyerPagedRequest request)
    {
        var result = await _buyerService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive()
    {
        var result = await _buyerService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var buyer = await _buyerService.GetByIdAsync(id);
        if (buyer is null) return NotFound();
        return Ok(buyer);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] BuyerCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.BuyerCode))
            return BadRequest("Kode buyer wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.BuyerName))
            return BadRequest("Nama buyer wajib diisi.");

        var (success, error) = await _buyerService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] BuyerUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.BuyerCode))
            return BadRequest("Kode buyer wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.BuyerName))
            return BadRequest("Nama buyer wajib diisi.");

        var (success, error) = await _buyerService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _buyerService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

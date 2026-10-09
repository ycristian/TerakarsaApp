using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

// Prompt 61: order aktif module PDH TNI AD -- dipakai TniOrderState di client
// untuk header & subjudul semua halaman /tni/...
[ApiController]
[Route("api/tni/order")]
// TANPA LOGIN: otorisasi perangkat lewat header X-Tni-Token (seperti stasiun).
[RequireTniDeviceToken]
public class TniOrderController : ControllerBase
{
    private readonly TniOrderService _orderService;

    public TniOrderController(TniOrderService orderService)
    {
        _orderService = orderService;
    }

    [HttpGet("aktif")]
    public async Task<IActionResult> GetAktif()
    {
        var order = await _orderService.GetAktifAsync();
        if (order is null) return NotFound("Belum ada order PDH TNI AD yang aktif.");
        return Ok(order);
    }
}

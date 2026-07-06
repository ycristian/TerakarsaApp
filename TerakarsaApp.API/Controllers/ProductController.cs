using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Products;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("products")]
public class ProductController : ControllerBase
{
    private readonly ProductService _productService;

    public ProductController(ProductService productService)
    {
        _productService = productService;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var products = await _productService.GetAllAsync();
        return Ok(products);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var product = await _productService.GetByIdAsync(id);
        if (product is null) return NotFound();
        return Ok(product);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] ProductCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || request.Name.Length < 3)
            return BadRequest("Nama produk minimal 3 karakter.");

        if (request.Price <= 0)
            return BadRequest("Harga harus lebih dari 0.");

        if (request.Stock < 0)
            return BadRequest("Stok tidak boleh negatif.");

        await _productService.CreateAsync(request);
        return Ok();
    }

    [HttpPut]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Update([FromBody] ProductUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || request.Name.Length < 3)
            return BadRequest("Nama produk minimal 3 karakter.");

        if (request.Price <= 0)
            return BadRequest("Harga harus lebih dari 0.");

        if (request.Stock < 0)
            return BadRequest("Stok tidak boleh negatif.");

        await _productService.UpdateAsync(request);
        return Ok();
    }

    [HttpDelete("{id}")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> Delete(int id)
    {
        await _productService.DeleteAsync(id);
        return Ok();
    }

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] ProductPagedRequest request)
    {
        var result = await _productService.GetPagedAsync(request);
        return Ok(result);
    }
}
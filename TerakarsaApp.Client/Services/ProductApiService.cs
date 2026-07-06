using System.Net.Http.Json;
using TerakarsaApp.Shared.Products;

namespace TerakarsaApp.Client.Services;

public class ProductApiService
{
    private readonly HttpClient _http;

    public ProductApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ProductDto>> GetAllAsync()
    {
        var response = await _http.GetAsync("api/product");
        if (!response.IsSuccessStatusCode) return new List<ProductDto>();
        var result = await response.Content.ReadFromJsonAsync<List<ProductDto>>();
        return result ?? new List<ProductDto>();
    }

    public async Task<bool> CreateAsync(ProductCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/product", request);
        return response.IsSuccessStatusCode;
    }

    public async Task<bool> UpdateAsync(ProductUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/product", request);
        return response.IsSuccessStatusCode;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/product/{id}");
        return response.IsSuccessStatusCode;
    }
    public async Task<ProductPagedResult> GetPagedAsync(ProductPagedRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/product/paged", request);
        if (!response.IsSuccessStatusCode) return new ProductPagedResult();
        var result = await response.Content.ReadFromJsonAsync<ProductPagedResult>();
        return result ?? new ProductPagedResult();
    }
}
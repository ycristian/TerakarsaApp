using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/article-photos")]
[Authorize]
[RequireModule("ORDER_PROJECT")]
public class ArticlePhotoController : ControllerBase
{
    private readonly ArticlePhotoService _photoService;

    public ArticlePhotoController(ArticlePhotoService photoService)
    {
        _photoService = photoService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("by-article/{articleId}")]
    public async Task<IActionResult> GetByArticle(int articleId)
    {
        var result = await _photoService.GetByArticleAsync(articleId);
        return Ok(result);
    }

    [HttpPost]
    public async Task<IActionResult> Upload([FromForm] int articleId, [FromForm] List<IFormFile> files)
    {
        if (files is null || files.Count == 0)
            return BadRequest("File wajib diunggah.");

        var results = await _photoService.UploadManyAsync(articleId, files, CurrentUserId);
        return Ok(results);
    }

    [HttpGet("{articleId}/primary")]
    public async Task<IActionResult> GetPrimary(int articleId)
    {
        var result = await _photoService.GetPrimaryPhotoForDownloadAsync(articleId);
        if (result is null) return NotFound();

        var (stream, contentType, fileName) = result.Value;
        return File(stream, contentType, fileName);
    }

    [HttpGet("{articleId}/{photoId}/download")]
    public async Task<IActionResult> Download(int articleId, int photoId)
    {
        var result = await _photoService.GetFileForDownloadAsync(articleId, photoId);
        if (result is null) return NotFound();

        var (stream, contentType, fileName) = result.Value;
        return File(stream, contentType, fileName);
    }

    [HttpPut("{id}/set-primary")]
    public async Task<IActionResult> SetPrimary(int id)
    {
        await _photoService.SetPrimaryAsync(id);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _photoService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

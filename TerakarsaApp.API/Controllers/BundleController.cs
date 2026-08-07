using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Projects;

namespace TerakarsaApp.API.Controllers;

// Kelola bundle punya pintu masuk mandiri (module BUNDLE_MANAGE, halaman /bundles), tidak
// lagi menumpang privilege PROJECT (ORDER_PROJECT). Endpoint bundle-picker/* di bawah
// memakai ulang ProjectService/ArticleService/ArticlePhotoService (tanpa mengubah
// ProjectController/ArticleController/ArticlePhotoController sama sekali) supaya user
// dengan BUNDLE_MANAGE saja tetap bisa memilih project/artikel tanpa perlu ORDER_PROJECT.
[ApiController]
[Route("api")]
[Authorize]
[RequireModule("BUNDLE_MANAGE")]
public class BundleController : ControllerBase
{
    private readonly BundleService _bundleService;
    private readonly ProjectService _projectService;
    private readonly ArticleService _articleService;
    private readonly ArticlePhotoService _articlePhotoService;

    public BundleController(
        BundleService bundleService,
        ProjectService projectService,
        ArticleService articleService,
        ArticlePhotoService articlePhotoService)
    {
        _bundleService = bundleService;
        _projectService = projectService;
        _articleService = articleService;
        _articlePhotoService = articlePhotoService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("articles/{articleId:int}/bundles")]
    public async Task<IActionResult> GetByArticle(int articleId)
    {
        var result = await _bundleService.GetByArticleAsync(articleId);
        return Ok(result);
    }

    [HttpPost("bundles")]
    public async Task<IActionResult> Create([FromBody] BundleCreateRequest request)
    {
        if (!User.IsInRole("Admin"))
            return Forbid();

        if (request.ArticleSizeId <= 0)
            return BadRequest("Ukuran wajib dipilih.");

        if (request.Qty <= 0)
            return BadRequest("Qty bundle harus lebih dari 0.");

        var (success, error, result) = await _bundleService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    [HttpPut("bundles/{id:int}")]
    public async Task<IActionResult> Update(int id, [FromBody] BundleUpdateRequest request)
    {
        if (request.Qty <= 0)
            return BadRequest("Qty bundle harus lebih dari 0.");

        request.Id = id;
        var (success, error) = await _bundleService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("bundles/{id:int}")]
    public async Task<IActionResult> Delete(int id, [FromQuery] string? reason)
    {
        if (string.IsNullOrWhiteSpace(reason))
            return BadRequest("Alasan hapus wajib diisi.");

        var (success, error) = await _bundleService.DeleteAsync(id, reason, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("bundles/{id:int}/reprint")]
    public async Task<IActionResult> Reprint(int id, [FromQuery] int copies = 1)
    {
        if (!User.IsInRole("Admin"))
            return Forbid();

        if (copies < 1) return BadRequest("Jumlah label harus minimal 1.");

        var (success, error, printJobId) = await _bundleService.ReprintAsync(id, copies, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    // --- Pintu masuk halaman /bundles: pilih project -> artikel, atau cari lintas project ---

    [HttpGet("bundle-picker/projects")]
    public async Task<IActionResult> GetProjects()
    {
        var result = await _projectService.GetPagedAsync(new ProjectPagedRequest
        {
            PageNumber = 1,
            PageSize = 500,
            SortColumn = "CreatedAt",
            SortDirection = "desc"
        });
        return Ok(result.Items);
    }

    [HttpGet("bundle-picker/projects/{projectId:int}/articles")]
    public async Task<IActionResult> GetArticlesByProject(int projectId)
    {
        var result = await _articleService.GetByProjectAsync(projectId);
        return Ok(result);
    }

    [HttpGet("bundle-picker/articles/search")]
    public async Task<IActionResult> SearchArticles([FromQuery] string keyword)
    {
        if (string.IsNullOrWhiteSpace(keyword) || keyword.Trim().Length < 3)
            return Ok(new List<ArticleSearchDto>());

        var result = await _articleService.SearchAsync(keyword.Trim());
        return Ok(result);
    }

    [HttpGet("bundle-picker/articles/{articleId:int}/thumbnail")]
    public async Task<IActionResult> GetArticleThumbnail(int articleId)
    {
        var result = await _articlePhotoService.GetPrimaryPhotoForDownloadAsync(articleId);
        if (result is null) return NotFound();

        var (stream, contentType, fileName) = result.Value;
        return File(stream, contentType, fileName);
    }
}

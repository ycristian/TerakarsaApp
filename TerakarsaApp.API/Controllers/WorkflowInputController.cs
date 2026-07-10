using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Projects;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.API.Controllers;

// Pintu masuk mandiri Prompt 12c: input log step non-bundle (mis. Cutting) lewat UI login,
// module WORKFLOW_INPUT, tidak menumpang ORDER_PROJECT/MASTER_RESOURCE. Endpoint picker
// project/artikel/thumbnail/resource di bawah reuse ProjectService/ArticleService/
// ArticlePhotoService/ResourceService langsung (tanpa mengubah controller aslinya), sama
// persis pola bundle-picker/* di BundleController (lihat memo Prompt 11b). List + hapus log
// yang sudah ada tetap lewat WorkflowLogController (sekarang RequireModule ganda).
[ApiController]
[Route("api")]
[Authorize]
[RequireModule("WORKFLOW_INPUT")]
public class WorkflowInputController : ControllerBase
{
    private readonly ProjectService _projectService;
    private readonly ArticleService _articleService;
    private readonly ArticlePhotoService _articlePhotoService;
    private readonly ArticleWorkflowService _articleWorkflowService;
    private readonly ResourceService _resourceService;
    private readonly WorkflowLogService _workflowLogService;

    public WorkflowInputController(
        ProjectService projectService,
        ArticleService articleService,
        ArticlePhotoService articlePhotoService,
        ArticleWorkflowService articleWorkflowService,
        ResourceService resourceService,
        WorkflowLogService workflowLogService)
    {
        _projectService = projectService;
        _articleService = articleService;
        _articlePhotoService = articlePhotoService;
        _articleWorkflowService = articleWorkflowService;
        _resourceService = resourceService;
        _workflowLogService = workflowLogService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    // --- Pemilih artikel (pola sama dengan bundle-picker/*, lihat ArticlePicker.razor) ---

    [HttpGet("workflow-input/projects")]
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

    [HttpGet("workflow-input/projects/{projectId:int}")]
    public async Task<IActionResult> GetProject(int projectId)
    {
        var result = await _projectService.GetByIdAsync(projectId);
        if (result is null) return NotFound();
        return Ok(result);
    }

    [HttpGet("workflow-input/projects/{projectId:int}/articles")]
    public async Task<IActionResult> GetArticlesByProject(int projectId)
    {
        var result = await _articleService.GetByProjectAsync(projectId);
        return Ok(result);
    }

    [HttpGet("workflow-input/articles/search")]
    public async Task<IActionResult> SearchArticles([FromQuery] string keyword)
    {
        if (string.IsNullOrWhiteSpace(keyword) || keyword.Trim().Length < 3)
            return Ok(new List<ArticleSearchDto>());

        var result = await _articleService.SearchAsync(keyword.Trim());
        return Ok(result);
    }

    [HttpGet("workflow-input/articles/{articleId:int}")]
    public async Task<IActionResult> GetArticle(int articleId)
    {
        var result = await _articleService.GetByIdAsync(articleId);
        if (result is null) return NotFound();
        return Ok(result);
    }

    [HttpGet("workflow-input/articles/{articleId:int}/thumbnail")]
    public async Task<IActionResult> GetArticleThumbnail(int articleId)
    {
        var result = await _articlePhotoService.GetPrimaryPhotoForDownloadAsync(articleId);
        if (result is null) return NotFound();

        var (stream, contentType, fileName) = result.Value;
        return File(stream, contentType, fileName);
    }

    [HttpGet("workflow-input/resources/active-by-division/{divisionId:int}")]
    public async Task<IActionResult> GetResourcesByDivision(int divisionId)
    {
        var result = await _resourceService.GetActiveByDivisionAsync(divisionId);
        return Ok(result);
    }

    // --- Step non-bundle + pencatatan ---

    [HttpGet("articles/{articleId:int}/nonbundle-steps")]
    public async Task<IActionResult> GetNonBundleSteps(int articleId)
    {
        var result = await _articleWorkflowService.GetNonBundleStepsAsync(articleId);
        return Ok(result);
    }

    [HttpPost("workflow-input/logs")]
    public async Task<IActionResult> CreateLog([FromBody] WorkflowInputCreateRequest request)
    {
        if (request.ArticleSizeId <= 0)
            return BadRequest("Size wajib dipilih.");

        if (request.QtyOk < 0 || request.QtyRejectPrint < 0 || request.QtyRejectFabric < 0
            || request.QtyRejectSewing < 0)
            return BadRequest("Qty tidak boleh negatif.");

        var (success, error) = await _workflowLogService.CreateAsync(new WorkflowLogCreateInput
        {
            ArticleWorkflowId = request.ArticleWorkflowId,
            BundleId = null,
            ArticleSizeId = request.ArticleSizeId,
            ResourceId = request.ResourceId,
            QtyOk = request.QtyOk,
            QtyRejectPrint = request.QtyRejectPrint,
            QtyRejectFabric = request.QtyRejectFabric,
            QtyRejectSewing = request.QtyRejectSewing,
            Remark = request.Remark,
            ActingDivisionId = null,
            ConfirmExceed = request.ConfirmExceed
        }, CurrentUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }
}

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.WorkflowTemplates;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class WorkflowTemplateController : ControllerBase
{
    private readonly WorkflowTemplateService _workflowTemplateService;

    public WorkflowTemplateController(WorkflowTemplateService workflowTemplateService)
    {
        _workflowTemplateService = workflowTemplateService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    [RequireModule("MASTER_WORKFLOW")]
    public async Task<IActionResult> GetPaged([FromBody] WorkflowTemplatePagedRequest request)
    {
        var result = await _workflowTemplateService.GetPagedAsync(request);
        return Ok(result);
    }

    // ORDER_PROJECT juga boleh -- dipakai ArticleEdit.razor untuk dropdown "Terapkan Template"
    // saat menyusun workflow artikel, tanpa perlu privilege MASTER_WORKFLOW penuh.
    [HttpGet("active")]
    [RequireModule("MASTER_WORKFLOW", "ORDER_PROJECT")]
    public async Task<IActionResult> GetActive()
    {
        var result = await _workflowTemplateService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id}")]
    [RequireModule("MASTER_WORKFLOW")]
    public async Task<IActionResult> GetById(int id)
    {
        var workflowTemplate = await _workflowTemplateService.GetByIdAsync(id);
        if (workflowTemplate is null) return NotFound();
        return Ok(workflowTemplate);
    }

    [HttpPost]
    [RequireModule("MASTER_WORKFLOW")]
    public async Task<IActionResult> Create([FromBody] WorkflowTemplateCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.WorkflowCode))
            return BadRequest("Kode workflow wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.WorkflowName))
            return BadRequest("Nama workflow wajib diisi.");

        if (request.Steps is null || request.Steps.Count == 0)
            return BadRequest("Minimal 1 baris step wajib diisi.");

        if (request.Steps.Any(s => string.IsNullOrWhiteSpace(s.StepName) || s.DivisionId <= 0))
            return BadRequest("Nama step dan divisi wajib diisi untuk setiap baris.");

        var (success, error, id) = await _workflowTemplateService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok(new WorkflowTemplateCreateResult { Id = id });
    }

    [HttpPut]
    [RequireModule("MASTER_WORKFLOW")]
    public async Task<IActionResult> Update([FromBody] WorkflowTemplateUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.WorkflowCode))
            return BadRequest("Kode workflow wajib diisi.");

        if (string.IsNullOrWhiteSpace(request.WorkflowName))
            return BadRequest("Nama workflow wajib diisi.");

        if (request.Steps is null || request.Steps.Count == 0)
            return BadRequest("Minimal 1 baris step wajib diisi.");

        if (request.Steps.Any(s => string.IsNullOrWhiteSpace(s.StepName) || s.DivisionId <= 0))
            return BadRequest("Nama step dan divisi wajib diisi untuk setiap baris.");

        var (success, error) = await _workflowTemplateService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    [RequireModule("MASTER_WORKFLOW")]
    public async Task<IActionResult> Delete(int id)
    {
        await _workflowTemplateService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

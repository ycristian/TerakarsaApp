using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.API.Controllers;

// Riwayat log workflow (read-only + hapus) untuk halaman Edit Article (ORDER_PROJECT).
// Prompt 23: module WORKFLOW_INPUT + halaman /workflow-input dihapus -- pencatatan step
// non-bundle sekarang lewat StationDeviceController (token stasiun), sama seperti bundle.
[ApiController]
[Route("api")]
[Authorize]
[RequireModule("ORDER_PROJECT")]
public class WorkflowLogController : ControllerBase
{
    private readonly WorkflowLogService _workflowLogService;

    public WorkflowLogController(WorkflowLogService workflowLogService)
    {
        _workflowLogService = workflowLogService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("articles/{articleId:int}/workflow-logs")]
    public async Task<IActionResult> GetByArticle(int articleId)
    {
        var result = await _workflowLogService.ListByArticleAsync(articleId);
        return Ok(result);
    }

    [HttpDelete("workflow-logs/{id:int}")]
    public async Task<IActionResult> Delete(int id, [FromBody] WorkflowLogDeleteRequest request)
    {
        if (!User.IsInRole("Admin"))
            return Forbid();

        if (string.IsNullOrWhiteSpace(request.DeleteReason))
            return BadRequest("Alasan hapus wajib diisi.");

        var (success, error) = await _workflowLogService.DeleteAsync(id, request.DeleteReason, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}

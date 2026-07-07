using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/project-attachments")]
[Authorize]
[RequireModule("ORDER_PROJECT")]
public class ProjectAttachmentController : ControllerBase
{
    private readonly ProjectAttachmentService _attachmentService;

    public ProjectAttachmentController(ProjectAttachmentService attachmentService)
    {
        _attachmentService = attachmentService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet("by-project/{projectId}")]
    public async Task<IActionResult> GetByProject(int projectId)
    {
        var result = await _attachmentService.GetByProjectAsync(projectId);
        return Ok(result);
    }

    [HttpPost]
    public async Task<IActionResult> Upload([FromForm] int projectId, [FromForm] List<IFormFile> files, [FromForm] string? description)
    {
        if (files is null || files.Count == 0)
            return BadRequest("File wajib diunggah.");

        var results = await _attachmentService.UploadManyAsync(projectId, files, description, CurrentUserId);
        return Ok(results);
    }

    [HttpGet("{projectId}/first-photo")]
    public async Task<IActionResult> GetFirstPhoto(int projectId)
    {
        var result = await _attachmentService.GetFirstPhotoForDownloadAsync(projectId);
        if (result is null) return NotFound();

        var (stream, contentType, fileName) = result.Value;
        return File(stream, contentType, fileName);
    }

    [HttpGet("{projectId}/{attachmentId}/download")]
    public async Task<IActionResult> Download(int projectId, int attachmentId)
    {
        var result = await _attachmentService.GetFileForDownloadAsync(projectId, attachmentId);
        if (result is null) return NotFound();

        var (stream, contentType, fileName) = result.Value;
        return File(stream, contentType, fileName);
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _attachmentService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }
}

namespace TerakarsaApp.Shared.Projects;

public class ProjectAttachmentDto
{
    public int Id { get; set; }
    public int ProjectId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FileType { get; set; } = string.Empty;
    public int FileSizeKb { get; set; }
    public string? Description { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
}

public class ProjectAttachmentUploadResultDto
{
    public string FileName { get; set; } = string.Empty;
    public bool Success { get; set; }
    public string? Error { get; set; }
}

namespace TerakarsaApp.Shared.Projects;

public class ArticlePhotoDto
{
    public int Id { get; set; }
    public int ArticleId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public int FileSizeKb { get; set; }
    public bool IsPrimary { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
}

public class ArticlePhotoUploadResultDto
{
    public string FileName { get; set; } = string.Empty;
    public bool Success { get; set; }
    public string? Error { get; set; }
}

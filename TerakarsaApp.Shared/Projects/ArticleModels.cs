namespace TerakarsaApp.Shared.Projects;

public class ArticleSizeDto
{
    public int Id { get; set; }
    public int SizePackDetailId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int Qty { get; set; }
    public int BundleQty { get; set; }
}

public class ArticleSizeSummaryDto
{
    public int ArticleId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int Qty { get; set; }
}

public class ArticleListItemDto
{
    public int Id { get; set; }
    public int ProjectId { get; set; }
    public int SizePackId { get; set; }
    public string SizePackName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public int TotalQty { get; set; }
    public int PhotoCount { get; set; }
    public int BundleCount { get; set; }
}

public class ArticleSearchDto
{
    public int Id { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string ProjectName { get; set; } = string.Empty;
}

public class ArticleDto
{
    public int Id { get; set; }
    public int ProjectId { get; set; }
    public int SizePackId { get; set; }
    public string SizePackName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
    public List<ArticleSizeDto> Sizes { get; set; } = new();
}

public class ArticleSizeRequest
{
    public int SizePackDetailId { get; set; }
    public int Qty { get; set; }
    public int BundleQty { get; set; }
}

public class ArticleCreateRequest
{
    public int ProjectId { get; set; }
    public int SizePackId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public List<ArticleSizeRequest> Sizes { get; set; } = new();
}

public class ArticleUpdateRequest
{
    public int Id { get; set; }
    public int SizePackId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public List<ArticleSizeRequest> Sizes { get; set; } = new();
}

public class ArticleCreateResult
{
    public int Id { get; set; }
}

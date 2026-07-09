namespace TerakarsaApp.Shared.Bundles;

public class BundleDto
{
    public int Id { get; set; }
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SizeSortOrder { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int BundleNo { get; set; }
    public int Qty { get; set; }
    public int SortOrder { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public string? ResourcePersonName { get; set; }
    public string? LabelStatus { get; set; }
    public DateTime? PrintedAt { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class BundleSizeSummaryDto
{
    public int ArticleSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int QtyOrder { get; set; }
    public int BundleQty { get; set; }
    public int BundleCount { get; set; }
    public int TotalBundleQty { get; set; }
    public bool HasFirstBundleStep { get; set; }
    public bool IsFirstBundleStepReceived { get; set; }
    public int? FirstBundleStepDivisionId { get; set; }
}

public class ArticleBundlesDto
{
    public int ArticleId { get; set; }
    public List<BundleSizeSummaryDto> Summary { get; set; } = new();
    public List<BundleDto> Bundles { get; set; } = new();
}

public class BundleCreateRequest
{
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public int Qty { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourcePersonName { get; set; }
}

public class BundleUpdateRequest
{
    public int Id { get; set; }
    public int Qty { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourcePersonName { get; set; }
}

public class BundleCreateResult
{
    public int Id { get; set; }
    public int PrintJobId { get; set; }
    public int BundleNo { get; set; }
}

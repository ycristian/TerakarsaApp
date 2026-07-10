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

// --- Prompt 12: scan QR bundle (/station panel scan + halaman publik /b/{serial}) ---

public class BundleScanBundleDto
{
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? Line { get; set; }
    public string? LastStepName { get; set; }
    public string? LastStatus { get; set; }
    public string? LastDivisionName { get; set; }
}

public class BundleScanTimelineDto
{
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? SizeName { get; set; }
    public string? DivisionName { get; set; }
    public string? ResourceName { get; set; }
    public int QtyOk { get; set; }
    public string? TargetDivisionName { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ReceivedAt { get; set; }
    public string? ReceivedByResourceName { get; set; }
    public string? ReceivedRemark { get; set; }
}

public class BundleScanActionDto
{
    public string AllowedAction { get; set; } = "NONE";
    public int? ActionArticleWorkflowId { get; set; }
    public int? ActionWorkflowLogId { get; set; }
    public string? Message { get; set; }
    public bool IsLastStep { get; set; }
    public int? NextDivisionId { get; set; }
    public string? NextDivisionName { get; set; }

    // Terisi hanya kalau AllowedAction = "EDIT" -- nilai baris yang mau direvisi
    // (baris yang dibuat divisi pemanggil sendiri, belum diterima tujuan), dipakai
    // untuk mengisi awal form popup edit di BundleScanCard.
    public int? ActionQtyOk { get; set; }
    public int? ActionQtyRejectPrint { get; set; }
    public int? ActionQtyRejectFabric { get; set; }
    public int? ActionQtyRejectSewing { get; set; }
    public int? ActionQtyRework { get; set; }
    public string? ActionRemark { get; set; }
}

public class BundleScanInfoDto
{
    public BundleScanBundleDto Bundle { get; set; } = new();
    public List<BundleScanTimelineDto> Timeline { get; set; } = new();
    public BundleScanActionDto Action { get; set; } = new();
}

public class ArticleWipSizeBreakdownDto
{
    public string SizeName { get; set; } = string.Empty;
    public int QtyOk { get; set; }
}

public class ArticleWipStepDto
{
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? DivisionName { get; set; }
    public bool RequiresBundle { get; set; }
    public int ReceivedBundleCount { get; set; }
    public int CompletedBundleCount { get; set; }
    public int TotalBundleCount { get; set; }
    public int TotalQtyOkCompleted { get; set; }
    public int EntryCount { get; set; }
    public List<ArticleWipSizeBreakdownDto> SizeBreakdown { get; set; } = new();
}

public class PublicBundleDetailDto
{
    public BundleScanInfoDto ScanInfo { get; set; } = new();
    public List<ArticleWipStepDto> Wip { get; set; } = new();
}

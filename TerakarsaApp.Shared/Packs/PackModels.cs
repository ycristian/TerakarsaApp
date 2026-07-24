namespace TerakarsaApp.Shared.Packs;

// Stok siap pack per artikel+size dalam satu project (SIS_Pack_StockAvailable). Termasuk
// baris qty_available = 0 supaya operator lihat semuanya.
public class PackStockAvailableDto
{
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public int ArticleSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int QtyDone { get; set; }
    public int QtyPacked { get; set; }
    public int QtyAvailable { get; set; }
}

public class PackListItemDto
{
    public int Id { get; set; }
    public int PackNo { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int ArticleCount { get; set; }
    public int TotalPlan { get; set; }
    public int TotalActual { get; set; }
    public bool IsConfirmed { get; set; }
    public string? LabelStatus { get; set; }
    public DateTime? PrintedAt { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class PackItemDto
{
    public int PackItemId { get; set; }
    public int PackId { get; set; }
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int QtyPlan { get; set; }
    public int? QtyActual { get; set; }
}

public class ProjectPackingDto
{
    public int ProjectId { get; set; }
    public List<PackStockAvailableDto> Stock { get; set; } = new();
    public List<PackListItemDto> Packs { get; set; } = new();
    public List<PackItemDto> Items { get; set; } = new();
    public string PublicBaseUrl { get; set; } = string.Empty;
}

public class PackItemInput
{
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public int QtyPlan { get; set; }
}

public class PackConfirmItemInput
{
    public int PackItemId { get; set; }
    public int QtyActual { get; set; }
}

public class PackCreateRequest
{
    public int ProjectId { get; set; }
    public List<PackItemInput> Items { get; set; } = new();
    public bool AutoPrint { get; set; } = true;
}

public class PackUpdatePlanRequest
{
    public List<PackItemInput> Items { get; set; } = new();
}

public class PackConfirmRequest
{
    public List<PackConfirmItemInput> Items { get; set; } = new();
}

public class PackCreateResult
{
    public int Id { get; set; }
    public int PackNo { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int? PrintJobId { get; set; }
}

// --- Scan QR karung (/station panel & halaman publik /pack/{serial}) ---

public class PackScanPackDto
{
    public int PackId { get; set; }
    public int PackNo { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string ProjectName { get; set; } = string.Empty;
    public int TotalPacks { get; set; }
    public int TotalQty { get; set; }
    public bool IsConfirmed { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class PackScanItemDto
{
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int QtyPlan { get; set; }
    public int? QtyActual { get; set; }
}

public class PackScanInfoDto
{
    public PackScanPackDto Pack { get; set; } = new();
    public List<PackScanItemDto> Items { get; set; } = new();
}

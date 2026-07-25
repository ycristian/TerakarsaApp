using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.Shared.SuperAdmin;

// Prompt 29: koreksi data langsung bundle & workflow log yang melewati guard normal --
// lihat sql/sp_SuperAdmin_Manage.sql (SIS_SuperAdmin_Manage/BundleSearch/BundleDetail).

public class SuperAdminBundleSearchResultDto
{
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int Qty { get; set; }
    public int LiveLogCount { get; set; }
}

public class SuperAdminBundleInfoDto
{
    public int BundleId { get; set; }
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public string Serial { get; set; } = string.Empty;
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public int Qty { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
}

public class SuperAdminBundleDetailDto
{
    public SuperAdminBundleInfoDto Bundle { get; set; } = new();
    public List<ArticleSizeOptionDto> SizeOptions { get; set; } = new();
    public List<WorkflowLogDto> Logs { get; set; } = new();
}

public class SuperAdminBundleUpdateRequest
{
    public int ArticleSizeId { get; set; }
    public int Qty { get; set; }
    public int BundleNo { get; set; }
    public string Serial { get; set; } = string.Empty;
}

public class SuperAdminLogUpdateRequest
{
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? Remark { get; set; }
}

public class SuperAdminDeleteRequest
{
    public string DeleteReason { get; set; } = string.Empty;
}

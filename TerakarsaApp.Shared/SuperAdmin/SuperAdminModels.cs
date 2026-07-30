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
    // Prompt 36: line/penjahit bundle -- dipakai modal "Edit Bundle" (/b/{serial},
    // /report-bundle Riwayat). LineDivisionId = divisi step ber-bundle pertama SETELAH
    // Bundling (dipakai fetch dropdown Line); LowerBound = total step itu utk bundle ini
    // (batas bawah qty, lihat SIS_SuperAdmin_Manage EDIT_BUNDLE).
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public int? LineDivisionId { get; set; }
    public int LowerBound { get; set; }
}

// Prompt 36: request modal "Edit Bundle" (Super Admin, /b/{serial} & /report-bundle Riwayat) --
// BEDA dengan SuperAdminBundleUpdateRequest (panel /super-admin, boleh ubah serial/bundle_no
// tanpa validasi arah bawah). Lihat SIS_SuperAdmin_Manage @Action = 'EDIT_BUNDLE'.
public class SuperAdminEditBundleRequest
{
    public int ArticleSizeId { get; set; }
    public int Qty { get; set; }
    public int? ResourceId { get; set; }
    public int? EmployeeId { get; set; }
}

// Prompt 36: request modal "Edit Log" per baris timeline. Lihat SIS_SuperAdmin_Manage
// @Action = 'EDIT_LOG'.
public class SuperAdminEditLogRequest
{
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public int? ResourceId { get; set; }
    public string? Remark { get; set; }
    // Arah atas, pola QTY_EXCEED| yang sudah ada (lihat SIS_WorkflowLog_Manage).
    public bool ConfirmExceed { get; set; }
}

// Prompt 36: detail 1 baris log untuk modal "Edit Log" -- lihat SIS_SuperAdmin_LogEditInfo.
public class SuperAdminLogEditInfoDto
{
    public int Id { get; set; }
    public string StepName { get; set; } = string.Empty;
    public string LogType { get; set; } = "NORMAL";
    public int DivisionId { get; set; }
    public int? ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? Remark { get; set; }
    // Qty masuk (arah atas) dan batas bawah/total step berikutnya (arah bawah, hard block) --
    // ditampilkan sebagai baris info "Masuk: X • Batas bawah: Y" di modal. LowerBound NULL
    // kalau step ini step ber-bundle terakhir (tidak ada pembanding).
    public int QtyMasuk { get; set; }
    public int? LowerBound { get; set; }
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

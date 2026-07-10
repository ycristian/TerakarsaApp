namespace TerakarsaApp.Shared.WorkflowLogs;

public class WorkflowLogDto
{
    public int Id { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int? BundleId { get; set; }
    public string? BundleSerial { get; set; }
    public int? ArticleSizeId { get; set; }
    public string? SizeName { get; set; }
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    public int? TargetDivisionId { get; set; }
    public string? TargetDivisionName { get; set; }
    public DateTime? ReceivedAt { get; set; }
    public string? ReceivedByResourceName { get; set; }
    public string? ReceivedRemark { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public string? CreatedByName { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public string? UpdatedByName { get; set; }
    public string? UpdatedByResourceName { get; set; }
}

public class WorkflowLogDeleteRequest
{
    public string DeleteReason { get; set; } = string.Empty;
}

public class ArticleSizeOptionDto
{
    public int Id { get; set; }
    public string SizeName { get; set; } = string.Empty;
}

public class StationPendingReceiveDto
{
    public int WorkflowLogId { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int QtyOk { get; set; }
    public DateTime SentAt { get; set; }
    public string FromDivisionName { get; set; } = string.Empty;
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? Serial { get; set; }
    public string? SizeName { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class StationPendingHandoverDto
{
    public int WorkflowLogId { get; set; }
    public int ArticleWorkflowId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? Serial { get; set; }
    public int? ArticleSizeId { get; set; }
    public string? SizeName { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    public string TargetDivisionName { get; set; } = string.Empty;
    public string? ResourceName { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public List<ArticleSizeOptionDto> Sizes { get; set; } = new();
}

public class StationLogUpdateRequest
{
    public int? ArticleSizeId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    // Pelaksana (operator sesi aktif) yang melakukan revisi ini -- Prompt 12d.
    public int ResourceId { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini (lihat SIS_WorkflowLog_Manage).
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini.
    public bool ConfirmShort { get; set; }
}

public class StationReceiveRequest
{
    public int WorkflowLogId { get; set; }
    public int ResourceId { get; set; }
    public string? Remark { get; set; }
}

// Prompt 15: 20 baris terakhir yang diterima divisi ini -- tab "Baru Diterima" di /station.
public class StationRecentReceivedDto
{
    public int WorkflowLogId { get; set; }
    public int? BundleNo { get; set; }
    public string? Serial { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? SizeName { get; set; }
    public string StepName { get; set; } = string.Empty;
    public string DivisionAsalName { get; set; } = string.Empty;
    public int QtyOk { get; set; }
    public DateTime ReceivedAt { get; set; }
    public string? ReceivedByResourceName { get; set; }
    public bool CanUnreceive { get; set; }
}

public class StationUnreceiveRequest
{
    public int ResourceId { get; set; }
}

public class StationCompleteRequest
{
    public int ArticleWorkflowId { get; set; }
    public int? BundleId { get; set; }
    public int? ArticleSizeId { get; set; }
    public int ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini (lihat SIS_WorkflowLog_Manage).
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini.
    public bool ConfirmShort { get; set; }
}

// Prompt 12c: input log step non-bundle (mis. Cutting) dari halaman /workflow-input,
// dicatat oleh supervisor/admin lewat login biasa (bukan lagi lewat stasiun).
public class WorkflowInputCreateRequest
{
    public int ArticleWorkflowId { get; set; }
    public int ArticleSizeId { get; set; }
    public int? ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    // Prompt 14: step non-bundle tidak divalidasi kuota, tapi field diteruskan ke SP untuk
    // konsistensi kontrak (selalu false di sini).
    public bool ConfirmExceed { get; set; }
}

// Prompt 14: info kuota qty step ber-bundle ("Masuk: X • Tercatat: Y • Sisa: Z"), dipakai
// form add/edit hasil SEBELUM submit. Lihat SIS_WorkflowLog_QuotaInfo.
public class WorkflowQuotaInfoDto
{
    public int QtyMasuk { get; set; }
    public int QtySudah { get; set; }
    public int Sisa { get; set; }
}

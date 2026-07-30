using System.Text.Json.Serialization;

namespace TerakarsaApp.Shared.PrintJobs;

public class PrintJobClaimRequest
{
    public int BatchSize { get; set; } = 5;
}

public class PrintJobClaimedDto
{
    public int PrintJobId { get; set; }
    public string JobType { get; set; } = string.Empty;
    public int RefId { get; set; }
    public string Payload { get; set; } = string.Empty;
    public int RetryCount { get; set; }
}

public class PrintJobReportRequest
{
    public int PrintJobId { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
}

// Bentuk payload JSON print_jobs untuk job_type BUNDLE_LABEL (lihat sql/sp_Bundle_Manage.sql,
// dirakit lewat FOR JSON PATH dengan nama kolom snake_case -- cocokkan lewat JsonPropertyName).
public class BundleLabelPayload
{
    [JsonPropertyName("serial")]
    public string Serial { get; set; } = string.Empty;

    [JsonPropertyName("bundle_no")]
    public int BundleNo { get; set; }

    [JsonPropertyName("bundle_letter")]
    public string? BundleLetter { get; set; }

    [JsonPropertyName("qr_content")]
    public string QrContent { get; set; } = string.Empty;

    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = string.Empty;

    [JsonPropertyName("no_po")]
    public string? NoPo { get; set; }

    [JsonPropertyName("material_name")]
    public string? MaterialName { get; set; }

    [JsonPropertyName("article_name")]
    public string ArticleName { get; set; } = string.Empty;

    [JsonPropertyName("style")]
    public string? Style { get; set; }

    [JsonPropertyName("color")]
    public string? Color { get; set; }

    [JsonPropertyName("size_pack_name")]
    public string? SizePackName { get; set; }

    [JsonPropertyName("size_name")]
    public string SizeName { get; set; } = string.Empty;

    [JsonPropertyName("qty")]
    public int Qty { get; set; }

    [JsonPropertyName("resource_name")]
    public string? ResourceName { get; set; }

    // Prompt 35: dulu resource_person_name (teks bebas) -- diganti employee_name (master
    // employees), penjahit kini identitas ber-FK, bukan teks bebas.
    [JsonPropertyName("employee_name")]
    public string? EmployeeName { get; set; }

    [JsonPropertyName("started_at")]
    public DateTime StartedAt { get; set; }

    // Prompt: remark cetak di bawah size_pack_name (bold) -- diambil dari
    // article_workflow_logs.remark terbaru, atau di-override untuk Print Label Cacat
    // (lihat SIS_Bundle_ReprintLabel @RemarkOverride).
    [JsonPropertyName("remark")]
    public string? Remark { get; set; }
}

// Bentuk payload JSON print_jobs untuk job_type PACK_LABEL (lihat sql/sp_Pack_Manage.sql,
// dirakit lewat FOR JSON PATH dengan nama kolom snake_case -- cocokkan lewat JsonPropertyName).
public class PackLabelPayload
{
    [JsonPropertyName("serial")]
    public string Serial { get; set; } = string.Empty;

    [JsonPropertyName("qr_content")]
    public string QrContent { get; set; } = string.Empty;

    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = string.Empty;

    [JsonPropertyName("pack_no")]
    public int PackNo { get; set; }

    [JsonPropertyName("total_qty")]
    public int TotalQty { get; set; }

    [JsonPropertyName("item_count")]
    public int ItemCount { get; set; }

    [JsonPropertyName("is_confirmed")]
    public bool IsConfirmed { get; set; }
}

// Bentuk payload JSON print_jobs untuk job_type REJECT_NOTE (lihat
// sql/sp_WorkflowLog_Manage.sql SIS_WorkflowLog_PrintReject, dirakit lewat FOR JSON PATH
// dengan nama kolom snake_case -- cocokkan lewat JsonPropertyName). Satu baris
// article_workflow_logs, bukan seluruh bundle -- tombol "Cetak Reject" di BundleScanCard/
// ReportBundle hanya muncul kalau baris itu punya reject > 0.
public class RejectNotePayload
{
    [JsonPropertyName("workflow_log_id")]
    public int WorkflowLogId { get; set; }

    [JsonPropertyName("bundle_serial")]
    public string? BundleSerial { get; set; }

    [JsonPropertyName("bundle_no")]
    public int? BundleNo { get; set; }

    [JsonPropertyName("bundle_letter")]
    public string? BundleLetter { get; set; }

    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = string.Empty;

    [JsonPropertyName("article_name")]
    public string ArticleName { get; set; } = string.Empty;

    [JsonPropertyName("size_name")]
    public string? SizeName { get; set; }

    [JsonPropertyName("step_name")]
    public string StepName { get; set; } = string.Empty;

    [JsonPropertyName("division_name")]
    public string? DivisionName { get; set; }

    [JsonPropertyName("qty_reject_print")]
    public int QtyRejectPrint { get; set; }

    [JsonPropertyName("qty_reject_fabric")]
    public int QtyRejectFabric { get; set; }

    [JsonPropertyName("qty_reject_sewing")]
    public int QtyRejectSewing { get; set; }

    [JsonPropertyName("qty_reject_rework")]
    public int QtyRejectRework { get; set; }

    [JsonPropertyName("qty_lost")]
    public int QtyLost { get; set; }

    [JsonPropertyName("remark")]
    public string? Remark { get; set; }

    [JsonPropertyName("resource_name")]
    public string? ResourceName { get; set; }

    [JsonPropertyName("created_at")]
    public DateTime CreatedAt { get; set; }
}

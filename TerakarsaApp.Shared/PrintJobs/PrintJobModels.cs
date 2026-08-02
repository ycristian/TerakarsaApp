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

// Bentuk payload JSON print_jobs untuk job_type KUPON_BORONGAN (Prompt 41, lihat
// sql/sp_WorkflowLog_Manage.sql -- dirakit lewat FOR JSON PATH saat received_at sebuah baris
// step ber-print_kupon terisi, baik RECEIVE manual maupun jalur auto-terima). QR di kupon
// dirakit worker dari WorkflowLogId (format "KUPON-{id}"), tidak ada field qr_content terpisah.
public class KuponBoronganPayload
{
    [JsonPropertyName("workflow_log_id")]
    public int WorkflowLogId { get; set; }

    [JsonPropertyName("serial")]
    public string? Serial { get; set; }

    [JsonPropertyName("bundle_no")]
    public int? BundleNo { get; set; }

    [JsonPropertyName("bundle_letter")]
    public string? BundleLetter { get; set; }

    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = string.Empty;

    [JsonPropertyName("article_name")]
    public string ArticleName { get; set; } = string.Empty;

    [JsonPropertyName("style")]
    public string? Style { get; set; }

    [JsonPropertyName("color")]
    public string? Color { get; set; }

    [JsonPropertyName("size_name")]
    public string? SizeName { get; set; }

    [JsonPropertyName("qty_ok")]
    public int QtyOk { get; set; }

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

    [JsonPropertyName("tailor_name")]
    public string? TailorName { get; set; }

    [JsonPropertyName("step_name")]
    public string StepName { get; set; } = string.Empty;

    [JsonPropertyName("division_name")]
    public string? DivisionName { get; set; }

    // Prompt: "line" penjahit -- resources.resource_name lewat employees.resource_id (pola sama
    // dengan SIS_Report_RekapPenjahit LineResourceName), bukan divisi/step.
    [JsonPropertyName("line_resource_name")]
    public string? LineResourceName { get; set; }

    [JsonPropertyName("received_at")]
    public DateTime? ReceivedAt { get; set; }

    [JsonPropertyName("created_at")]
    public DateTime CreatedAt { get; set; }

    [JsonPropertyName("updated_at")]
    public DateTime? UpdatedAt { get; set; }
}

// Bentuk payload JSON print_jobs untuk job_type REKAP_PRODUKSI (Prompt 42, menggantikan
// REKAP_PENJAHIT Prompt 41 -- lihat sql/sp_Report_RekapStruk.sql SIS_Report_RekapStrukPrint,
// dirakit lewat FOR JSON PATH bersarang saat tombol "Cetak Struk" ditekan di tab
// Rekap Produksi /station). Label sudah diformat SP sesuai Level (bundle letter+no / nama
// penjahit / nama resource) -- worker tinggal cetak apa adanya, tidak perlu tahu Level.
public class RekapProduksiLine
{
    [JsonPropertyName("event_date")]
    public DateTime? EventDate { get; set; }

    [JsonPropertyName("article_name")]
    public string ArticleName { get; set; } = string.Empty;

    [JsonPropertyName("size_name")]
    public string? SizeName { get; set; }

    [JsonPropertyName("label")]
    public string Label { get; set; } = string.Empty;

    [JsonPropertyName("qty")]
    public int Qty { get; set; }

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
}

// WIP line -- bentuk sama seperti RekapProduksiLine tapi tanpa EventDate/reject (snapshot,
// bukan hasil kerja), dipisah jadi kelas sendiri supaya JSON payload wip_lines tetap ringkas.
public class RekapProduksiWipLine
{
    [JsonPropertyName("article_name")]
    public string ArticleName { get; set; } = string.Empty;

    [JsonPropertyName("size_name")]
    public string? SizeName { get; set; }

    [JsonPropertyName("label")]
    public string Label { get; set; } = string.Empty;

    [JsonPropertyName("qty")]
    public int Qty { get; set; }
}

public class RekapProduksiPayload
{
    [JsonPropertyName("division_name")]
    public string DivisionName { get; set; } = string.Empty;

    [JsonPropertyName("resource_name")]
    public string? ResourceName { get; set; }

    [JsonPropertyName("employee_name")]
    public string? EmployeeName { get; set; }

    [JsonPropertyName("level")]
    public string Level { get; set; } = "DIVISION";

    [JsonPropertyName("period_start")]
    public DateTime PeriodStart { get; set; }

    [JsonPropertyName("period_end")]
    public DateTime PeriodEnd { get; set; }

    [JsonPropertyName("total_qty")]
    public int TotalQty { get; set; }

    [JsonPropertyName("lines")]
    public List<RekapProduksiLine> Lines { get; set; } = new();

    [JsonPropertyName("wip_lines")]
    public List<RekapProduksiWipLine> WipLines { get; set; } = new();
}

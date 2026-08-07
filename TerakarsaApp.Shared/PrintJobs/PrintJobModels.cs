using System.Text.Json.Serialization;

namespace TerakarsaApp.Shared.PrintJobs;

public class PrintJobClaimRequest
{
    public int BatchSize { get; set; } = 5;

    // Job_type yang printer-nya sedang ON di worker pemanggil (lihat PrinterLabelOn/
    // PrinterThermalOn) -- job_type lain tidak diklaim sama sekali, tetap PENDING.
    public List<string> JobTypes { get; set; } = new();

    // Ad hoc (lanjutan Prompt 48): sama dengan PrintWorkerOptions.DryRun di worker pemanggil --
    // kalau true, klaim dari print_jobs_dryrun (SIS_PrintJobDryRun_Claim), BUKAN print_jobs
    // live, supaya testing tidak pernah menyentuh antrian cetak nyata.
    public bool DryRun { get; set; }
}

public class PrintJobClaimedDto
{
    public int PrintJobId { get; set; }
    public string JobType { get; set; } = string.Empty;
    public int RefId { get; set; }
    public string Payload { get; set; } = string.Empty;
    public int RetryCount { get; set; }

    // Prompt 48: printer tujuan diresolusi SAAT KLAIM lewat print_job_routes -> print_devices
    // (menggantikan PrinterName tunggal di appsettings). RenderMode menentukan alur worker:
    // 'RAW_TSPL' = jalur lama tanpa perubahan (TsplBuilder); 'TOKEN' = panggil
    // GET api/print/render/{id} lalu terjemahkan lewat EscPosRenderer. CharsPerLine/
    // CharsPerLineSmall hanya relevan untuk RenderMode TOKEN (lebar font A/B ESC/POS).
    public string DeviceCode { get; set; } = string.Empty;
    public string PrinterName { get; set; } = string.Empty;
    public string RenderMode { get; set; } = string.Empty;
    public int CharsPerLine { get; set; }
    public int CharsPerLineSmall { get; set; }
}

public class PrintJobReportRequest
{
    public int PrintJobId { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }

    // Ad hoc (lanjutan Prompt 48): sama seperti PrintJobClaimRequest.DryRun -- lapor ke
    // SIS_PrintJobDryRun_Report (print_jobs_dryrun), bukan SIS_PrintJob_Report (live).
    public bool DryRun { get; set; }
}

// Bentuk respons GET api/print/render/{printJobId} (Prompt 48).
public class PrintRenderResponse
{
    [JsonPropertyName("tokenText")]
    public string? TokenText { get; set; }
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

    // Prompt 35: catatan bebas bundles.remarks -- dicetak di bawah nama artikel (kolom kiri),
    // TERPISAH dari Remark di bawah (article_workflow_logs.remark, kolom kanan).
    [JsonPropertyName("bundle_remarks")]
    public string? BundleRemarks { get; set; }

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

    // Prompt 44: catatan bebas bundles.remarks, dicetak "Note : ..." setelah baris reject/lost
    // kalau terisi (lihat EscPosBuilder.BuildKuponBorongan).
    [JsonPropertyName("bundle_remarks")]
    public string? BundleRemarks { get; set; }

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

// Fix: job_type REKAP_KARYAWAN -- tombol "Cetak Karyawan" terpisah dari "Cetak Struk"
// (RekapProduksiPayload di atas, tidak diubah), lihat SIS_Report_RekapKaryawanPrint di
// sql/sp_Report_RekapStruk.sql. Beda dari RekapProduksiPayload: satu HARI saja (bukan periode
// gajian mingguan), baris sudah dipecah per bundle (Selesai) / per PO (WIP) -- pengelompokan
// Line > Karyawan > PO(> Bundle utk Selesai) dilakukan di EscPosBuilder saat cetak, SP hanya
// mengembalikan baris flat sudah terurut.
public class RekapKaryawanDoneRow
{
    [JsonPropertyName("line_resource_name")]
    public string LineResourceName { get; set; } = string.Empty;

    [JsonPropertyName("employee_name")]
    public string EmployeeName { get; set; } = string.Empty;

    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = string.Empty;

    [JsonPropertyName("bundle_label")]
    public string BundleLabel { get; set; } = string.Empty;

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
}

// WIP berhenti di level PO (bukan per bundle) -- lihat catatan prompt.
public class RekapKaryawanWipRow
{
    [JsonPropertyName("line_resource_name")]
    public string LineResourceName { get; set; } = string.Empty;

    [JsonPropertyName("employee_name")]
    public string EmployeeName { get; set; } = string.Empty;

    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = string.Empty;

    [JsonPropertyName("qty_wip")]
    public int QtyWip { get; set; }
}

public class RekapKaryawanPayload
{
    [JsonPropertyName("division_name")]
    public string DivisionName { get; set; } = string.Empty;

    [JsonPropertyName("resource_name")]
    public string? ResourceName { get; set; }

    [JsonPropertyName("employee_name")]
    public string? EmployeeName { get; set; }

    [JsonPropertyName("date")]
    public DateTime Date { get; set; }

    [JsonPropertyName("done_rows")]
    public List<RekapKaryawanDoneRow> DoneRows { get; set; } = new();

    [JsonPropertyName("wip_rows")]
    public List<RekapKaryawanWipRow> WipRows { get; set; } = new();
}

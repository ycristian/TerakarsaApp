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
    // Prompt 24: dipakai memanggil bundling-summary (dropdown penjahit) saat Edit bundle.
    public int ArticleId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    // Prompt 24: true kalau baris ini log step Bundling implisit -- client menampilkan tombol
    // Edit (bukan Revisi) dan menyembunyikan Batal Serah untuk baris ini.
    public bool IsBundling { get; set; }
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
    public string? TargetDivisionName { get; set; }
    // Prompt 23: true kalau baris ini step TERAKHIR artikel (tidak ada tujuan serah, tidak
    // pernah "diterima" -- tampil di sini selama jendela revisi H+1). Client harus sembunyikan
    // field Divisi Tujuan/Penjahit & tombol Batal Serah, dan revisi lewat UPDATE biasa
    // (bukan REVISE_HANDOVER) untuk baris ini.
    public bool IsLastStep { get; set; }
    // Pelaksana BUNDLING (awl.resource_id) untuk baris IsBundling -- BUKAN penjahit, lihat
    // BundleResourceName di bawah untuk penjahit.
    public string? ResourceName { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public List<ArticleSizeOptionDto> Sizes { get; set; } = new();
    // Prompt 12e: opsi divisi tujuan utk form Revisi (REVISE_HANDOVER). Tidak dipakai untuk
    // baris IsLastStep.
    public List<DivisionOptionDto> TargetDivisionOptions { get; set; } = new();
    // Prompt 24: data penjahit bundle (bundles.resource_id/resource_person_name), dipakai
    // prefill modal Edit bundle -- hanya relevan untuk baris IsBundling.
    public int? BundleResourceId { get; set; }
    public string? BundleResourceName { get; set; }
    public string? BundleResourcePersonName { get; set; }
}

// Prompt 12e: tab "Dikerjakan" -- bundle sudah diterima divisi ini, belum ada baris step
// berikutnya. Lihat SIS_Station_InProgress. WorkflowLogId = baris yang diterima (dipakai
// Batal Terima/UNRECEIVE). NextArticleWorkflowId = step yang diselesaikan saat Serahkan
// (dikirim ke endpoint complete existing, action CREATE).
public class StationInProgressDto
{
    public int WorkflowLogId { get; set; }
    public int BundleId { get; set; }
    public string Serial { get; set; } = string.Empty;
    public int BundleNo { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    // Prompt 23: murni tambahan data (tidak mengubah alur kartu bundle) supaya pencarian teks
    // WAJIB di tab WIP bisa menyaring kartu bundle dan non-bundle dengan field yang sama.
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string? SizeName { get; set; }
    public int Qty { get; set; }
    public string? TailorName { get; set; }
    public DateTime ReceivedAt { get; set; }
    public int? NextArticleWorkflowId { get; set; }
    public string? NextStepName { get; set; }
    public string? NextDivisionName { get; set; }
    public bool IsLastStep { get; set; }
}

// Prompt 12e: strip 3 angka besar (Masuk/Dikerjakan/Dikirim) di atas /station.
public class StationCountsDto
{
    public int MasukCount { get; set; }
    public int DikerjakanCount { get; set; }
    public int DikirimCount { get; set; }
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

public class DivisionOptionDto
{
    public int Id { get; set; }
    public string DivisionName { get; set; } = string.Empty;
}

// Prompt 12e: tab "Batal Serah" -- hanya operator, tanpa alasan bebas (lihat
// SIS_WorkflowLog_Manage action CANCEL_HANDOVER).
public class StationCancelHandoverRequest
{
    public int ResourceId { get; set; }
}

// Prompt 12e: tab "Revisi" di Dikirim -- superset StationLogUpdateRequest, boleh juga
// mengubah divisi tujuan & penjahit (lihat SIS_WorkflowLog_Manage action REVISE_HANDOVER).
// SENGAJA tanpa ConfirmExceed/ConfirmShort -- di luar cakupan Prompt 12e.
public class StationReviseHandoverRequest
{
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    public int NewTargetDivisionId { get; set; }
    public int? NewResourceId { get; set; }
    // Pelaksana (operator sesi aktif) yang melakukan revisi ini -- Prompt 12d.
    public int ResourceId { get; set; }
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

// Prompt 14: info kuota qty step ber-bundle ("Masuk: X • Tercatat: Y • Sisa: Z"), dipakai
// form add/edit hasil SEBELUM submit. Lihat SIS_WorkflowLog_QuotaInfo.
public class WorkflowQuotaInfoDto
{
    public int QtyMasuk { get; set; }
    public int QtySudah { get; set; }
    public int Sisa { get; set; }
}

// Prompt 23: kartu permanen (artikel x step non-bundle) di tab WIP stasiun -- lihat
// SIS_Station_ActiveWork. Tampil terus selama project masih aktif, tidak hilang setelah
// Kirim Hasil (input non-bundle boleh nyicil berulang).
public class StationActiveWorkDto
{
    public int ArticleWorkflowId { get; set; }
    // Prompt 24: dipakai memanggil bundling-summary/bundles (create) untuk kartu "Buat Bundle".
    public int ArticleId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    // Prompt 24: true kalau kartu ini step Bundling implisit (kartu "Buat Bundle"), bukan
    // step non-bundle biasa (kartu "Kirim Hasil"). Sizes/BundleCount dkk saling eksklusif
    // tergantung flag ini.
    public bool IsBundling { get; set; }
    public bool IsLastStep { get; set; }
    public int? NextDivisionId { get; set; }
    public string? NextDivisionName { get; set; }
    public List<StationActiveWorkSizeDto> Sizes { get; set; } = new();
    // Prompt 24: ringkasan untuk kartu "Buat Bundle" (IsBundling = true) -- NULL kalau
    // IsBundling = false. Detail per size diambil terpisah lewat bundling-summary saat modal
    // Buat Bundle dibuka.
    public int? BundleCount { get; set; }
    public int? TotalBundleQty { get; set; }
    public int? TotalOrderQty { get; set; }
}

public class StationActiveWorkSizeDto
{
    public int Id { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int QtyOrder { get; set; }
    public int QtyRecorded { get; set; }
}

// Prompt 23: grid "Kirim Hasil" non-bundle dari kartu WIP stasiun -- satu baris per ukuran,
// satu Pelaksana (operator sesi, wajib)/Catatan untuk seluruh batch (pola sama dengan
// WorkflowInputBatch* Prompt 19, dipindah ke station setelah /workflow-input dihapus).
public class StationNonBundleBatchEntryRequest
{
    public int ArticleSizeId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
}

public class StationNonBundleBatchCreateRequest
{
    public int ArticleWorkflowId { get; set; }
    public int ResourceId { get; set; }
    public string? Remark { get; set; }
    public List<StationNonBundleBatchEntryRequest> Entries { get; set; } = new();
}

// Dikembalikan saat batch gagal di tengah jalan (satu transaksi, semua di-rollback) --
// ArticleSizeId menunjuk baris grid yang menyebabkan SP menolak, supaya UI bisa menandainya.
public class StationNonBundleBatchResult
{
    public string Error { get; set; } = string.Empty;
    public int? ArticleSizeId { get; set; }
}

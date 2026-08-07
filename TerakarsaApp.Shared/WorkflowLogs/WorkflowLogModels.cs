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
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string LogType { get; set; } = "NORMAL";
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
    public string? NoPo { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int QtyOk { get; set; }
    public DateTime SentAt { get; set; }
    public string FromDivisionName { get; set; } = string.Empty;
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string? Serial { get; set; }
    public string? SizeName { get; set; }
    public int? SizeSortOrder { get; set; }
    public DateTime? UpdatedAt { get; set; }
    // Prompt 28: badge "Penyesuaian" untuk item hasil ADJUST (qty_ok > 0) di tab Masuk.
    public bool IsAdjustment { get; set; }
    // Prompt 40: counterpart resource pengirim, valid terhadap divisi ini -- dipakai penerima
    // default saat "Terima" manual (tunggal maupun borongan), NULL bila tidak ada.
    public int? SuggestedReceiverResourceId { get; set; }
    public string? SuggestedReceiverResourceName { get; set; }
}

public class StationPendingHandoverDto
{
    public int WorkflowLogId { get; set; }
    public int ArticleWorkflowId { get; set; }
    // Prompt 24: dipakai memanggil bundling-summary (dropdown penjahit) saat Edit bundle.
    public int ArticleId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    // Prompt 24: true kalau baris ini log step Bundling implisit -- client menampilkan tombol
    // Edit (bukan Revisi) dan menyembunyikan Batal Serah untuk baris ini.
    public bool IsBundling { get; set; }
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string? Serial { get; set; }
    public int? ArticleSizeId { get; set; }
    public string? SizeName { get; set; }
    public int? SizeSortOrder { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? Remark { get; set; }
    public string? TargetDivisionName { get; set; }
    // Prompt 23: true kalau baris ini step TERAKHIR artikel (tidak ada tujuan serah, tidak
    // pernah "diterima" -- tampil di sini selama jendela revisi H+1). Client harus sembunyikan
    // field Divisi Tujuan/Penjahit & tombol Batal Serah, dan revisi lewat UPDATE biasa
    // (bukan REVISE_HANDOVER) untuk baris ini.
    public bool IsLastStep { get; set; }
    // Prompt 49: id mentah pelaksana baris ini (default terpilih di picker "Pelaksana" pada
    // modal Revisi). Untuk baris IsBundling, ini pelaksana BUNDLING -- BUKAN penjahit, lihat
    // BundleResourceId/BundleResourceName di bawah untuk penjahit.
    public int? ResourceId { get; set; }
    // Pelaksana BUNDLING (awl.resource_id) untuk baris IsBundling -- BUKAN penjahit, lihat
    // BundleResourceName di bawah untuk penjahit.
    public string? ResourceName { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    // Fix: terisi utk baris Bundling yang auto-diterima Line tujuan saat dibuat -- client
    // menukar tombol Edit (ReceivedAt null) jadi Hapus (ReceivedAt terisi, hanya dalam
    // jendela 1 jam sejak CreatedAt, lihat SIS_Station_PendingHandover).
    public DateTime? ReceivedAt { get; set; }
    public List<ArticleSizeOptionDto> Sizes { get; set; } = new();
    // Prompt 12e: opsi divisi tujuan utk form Revisi (REVISE_HANDOVER). Tidak dipakai untuk
    // baris IsLastStep.
    public List<DivisionOptionDto> TargetDivisionOptions { get; set; } = new();
    // Prompt 24: data penjahit bundle (bundles.resource_id/employee_id), dipakai
    // prefill modal Edit bundle -- hanya relevan untuk baris IsBundling.
    public int? BundleResourceId { get; set; }
    public string? BundleResourceName { get; set; }
    // Prompt 35: dulu BundleResourcePersonName -- direname & direpurpose jadi catatan bebas
    // bundle. Tidak ada editor-nya di station; klien wajib mengirim balik nilai ini apa
    // adanya saat submit Edit bundle (lihat StationBundleUpdateRequest.Remarks).
    public string? BundleRemarks { get; set; }
    // Prompt 32: penjahit dari master employees, diutamakan di atas BundleRemarks.
    public int? BundleEmployeeId { get; set; }
    public string? BundleEmployeeName { get; set; }
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
    public string? BundleLetter { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    // Prompt 23: murni tambahan data (tidak mengubah alur kartu bundle) supaya pencarian teks
    // WAJIB di tab WIP bisa menyaring kartu bundle dan non-bundle dengan field yang sama.
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string? SizeName { get; set; }
    public int Qty { get; set; }
    public string? TailorName { get; set; }
    // Prompt 32: penjahit dari master employees, diutamakan di atas TailorName (fallback lama).
    public string? EmployeeName { get; set; }
    // Fix: catatan bebas bundle (bundles.remarks, Prompt 35) -- dipakai pencarian teks tab WIP.
    public string? Remarks { get; set; }
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
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? Remark { get; set; }
    // Pelaksana (operator sesi aktif) yang melakukan revisi ini -- Prompt 12d.
    public int ResourceId { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini (lihat SIS_WorkflowLog_Manage).
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini.
    public bool ConfirmShort { get; set; }
    // Prompt 49: pelaksana PEKERJAAN baris ini (BEDA dari ResourceId di atas, yang operator
    // sesi/perevisi) -- dipilih lewat picker "Pelaksana" sekali pakai saat revisi. NULL =
    // resource_id baris tidak diubah. Stasiun terkunci: server mengabaikan nilai ini dan
    // memaksa default_resource_id (lihat StationDeviceController.EffectiveResourceId).
    public int? PelaksanaResourceId { get; set; }
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
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
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
    public string? BundleLetter { get; set; }
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
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? Remark { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini (lihat SIS_WorkflowLog_Manage).
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini.
    public bool ConfirmShort { get; set; }
    // Prompt 40: penerima manual dipilih operator pengirim -- HANYA dipakai server kalau step
    // tujuan auto_receive = 1 DAN counterpart pengirim tidak valid (lihat
    // BundleScanActionDto.ReceiverPickerRequired). Diteruskan apa adanya ke SP -- SP
    // satu-satunya penjaga, API tidak validasi ulang.
    public int? AutoReceiveResourceId { get; set; }
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
    public string? NoPo { get; set; }
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
    // Fix: sisa hasil Cutting yang sudah diterima divisi Bundling tapi belum dijadikan bundle,
    // PER SIZE (size dengan stock 0 tidak disertakan) -- lihat SIS_Station_ActiveWork.
    public List<StationBundleStockCuttingDto> StockCutting { get; set; } = new();
    // Fix: waktu aktivitas terakhir kartu ini (received_at step sebelumnya, atau input step ini
    // sendiri kalau sudah dicicil) -- dipakai default urutan tab WIP; NULL kalau belum tersentuh.
    public DateTime? WorkStartedAt { get; set; }
}

public class StationActiveWorkSizeDto
{
    public int Id { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int QtyOrder { get; set; }
    public int QtyRecorded { get; set; }
}

public class StationBundleStockCuttingDto
{
    public string SizeName { get; set; } = string.Empty;
    public int StockCutting { get; set; }
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
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
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

// Prompt 28: panel Penyesuaian di /b/{serial} -- mutasi qty reject/hilang -> reject/hilang
// lain ATAU Qty OK, total keenam nilai wajib 0 (lihat SIS_WorkflowLog_Manage @Action = 'ADJUST').
public class StationAdjustRequest
{
    public int ArticleWorkflowId { get; set; }
    public int BundleId { get; set; }
    public int ResourceId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public int? TargetDivisionId { get; set; }
    public string? Remark { get; set; }
}

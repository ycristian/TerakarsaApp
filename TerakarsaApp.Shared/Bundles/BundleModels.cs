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
    // Prompt 27: kode huruf bundle project (A-Z berputar), NULL utk project lama tanpa
    // huruf -- lihat TerakarsaApp.Client BundleDisplay untuk format tampilan "{huruf}-{no}".
    public string? BundleLetter { get; set; }
    public int Qty { get; set; }
    public int SortOrder { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    // Prompt 35: dulu ResourcePersonName (nama penjahit teks bebas) -- direname & direpurpose
    // jadi catatan bebas bundle, diisi/diedit lewat BundleManager.razor.
    public string? Remarks { get; set; }
    public string? LabelStatus { get; set; }
    public DateTime? PrintedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
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
    // Sisa hasil Cutting yang sudah diterima divisi Bundling tapi belum dijadikan bundle
    // (lihat SIS_Article_BundleSummary) -- dipakai station "Buat Bundle" sebagai saran qty.
    public int StockCutting { get; set; }
    public bool HasFirstBundleStep { get; set; }
    public bool IsFirstBundleStepReceived { get; set; }
    public int? FirstBundleStepDivisionId { get; set; }
    public int? BundlingDivisionId { get; set; }
}

public class ArticleBundlesDto
{
    public int ArticleId { get; set; }
    public List<BundleSizeSummaryDto> Summary { get; set; } = new();
    public List<BundleDto> Bundles { get; set; } = new();
    public string PublicBaseUrl { get; set; } = string.Empty;
}

public class BundleCreateRequest
{
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public int Qty { get; set; }
    public int? ResourceId { get; set; }
    // Prompt 32: penjahit dari master employees, menggantikan ResourcePersonName (teks bebas).
    public int? EmployeeId { get; set; }
    public int? BundlingResourceId { get; set; }
    // Prompt 35: catatan bebas bundle, diisi/diedit lewat BundleManager.razor.
    public string? Remarks { get; set; }
    // Fix: dulu AutoPrint (bool checkbox "Cetak label otomatis"), sekarang jumlah label yang
    // dicetak (default 1; admin /bundles tidak mengirim field ini sehingga tetap cetak 1x
    // seperti perilaku lama). 0 = tidak cetak.
    public int PrintCopies { get; set; } = 1;
}

// Prompt: "Print Label Cacat" -- muncul di BundleScanCard setelah Kirim Hasil dengan reject
// > 0. Copies = jumlah lembar label yang mau dicetak (bukan qty cacat); Remark = catatan Kirim
// Hasil + ringkasan qty cacat, dirakit di klien, dipakai override SIS_Bundle_ReprintLabel.
public class BundlePrintDefectLabelRequest
{
    public int Copies { get; set; } = 1;
    public string? Remark { get; set; }
}

public class BundleUpdateRequest
{
    public int Id { get; set; }
    public int Qty { get; set; }
    public int? ResourceId { get; set; }
    // Prompt 32: penjahit dari master employees, menggantikan ResourcePersonName (teks bebas).
    public int? EmployeeId { get; set; }
    public int? BundlingResourceId { get; set; }
    // Fix: opsional -- NULL berarti ukuran tidak diubah (dipakai admin /bundles yang belum
    // punya UI ganti ukuran); station selalu mengirim field ini lewat StationBundleUpdateRequest.
    public int? ArticleSizeId { get; set; }
    // Prompt 35: catatan bebas bundle -- SP menulis ulang nilai ini apa adanya tiap UPDATE
    // (editable di BundleManager.razor admin & modal Edit bundle station).
    public string? Remarks { get; set; }
}

public class BundleCreateResult
{
    public int Id { get; set; }
    // Fix: nullable -- NULL kalau PrintCopies = 0 (input "Jumlah Label" diisi 0 di station).
    public int? PrintJobId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
}

// Prompt 24: "Buat Bundle" dari kartu WIP station Bundling -- ResourceId = operator sesi
// (WAJIB, dikirim ke SP sebagai @BundlingResourceId); Tailor* = penjahit opsional (dikirim
// sebagai @ResourceId/@EmployeeId di SIS_Bundle_Manage) -- nama field beda dari
// BundleCreateRequest supaya semantik operator-sesi vs penjahit tidak tertukar.
// Prompt 32: TailorPersonName (teks bebas) diganti TailorEmployeeId (master employees),
// cascading di bawah TailorResourceId sama seperti BundleManager.razor.
public class StationBundleCreateRequest
{
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public int Qty { get; set; }
    public int ResourceId { get; set; }
    public int? TailorResourceId { get; set; }
    public int? TailorEmployeeId { get; set; }
    // Fix: dulu AutoPrint (bool checkbox), sekarang jumlah label yang dicetak (default 1,
    // input "Jumlah Label" di modal "Buat Bundle" station). 0 = tidak cetak.
    public int PrintCopies { get; set; } = 1;
    // Prompt 35: catatan bebas bundle, diisi opsional di modal "Buat Bundle" station.
    public string? Remarks { get; set; }
}

// Prompt 24: Edit bundle dari tab OUT station Bundling.
// Fix: ArticleSizeId ditambahkan supaya ukuran bisa diubah dari modal Edit yang sama.
public class StationBundleUpdateRequest
{
    public int Qty { get; set; }
    public int ArticleSizeId { get; set; }
    public int ResourceId { get; set; }
    public int? TailorResourceId { get; set; }
    public int? TailorEmployeeId { get; set; }
    // Prompt 35: catatan bebas bundle -- editable di modal Edit bundle station juga
    // (lihat BundleUpdateRequest.Remarks, SP menulis ulang nilai ini apa adanya tiap UPDATE).
    public string? Remarks { get; set; }
}

// --- Prompt 12: scan QR bundle (/station panel scan + halaman publik /b/{serial}) ---

public class BundleScanBundleDto
{
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
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
    // Prompt 32: penjahit dari master employees -- ditampilkan sebagai tambahan di atas Line
    // (yang tetap ResourceName, lihat SIS_Bundle_ScanInfo).
    public string? EmployeeName { get; set; }
    // Prompt 39/40: saran AUTO-LOGIN operator sesi stasiun -- kaskade 4 sumber
    // (LINE_BUNDLE/PENERIMA/COUNTERPART/RIWAYAT, lihat SIS_Bundle_ScanInfo), semua kandidat
    // sudah difilter hidup + aktif + milik divisi station pemanggil. NULL kalau tidak ada yang
    // cocok (termasuk @DivisionId NULL/pengunjung publik). Dipakai client BundleScanPublic
    // untuk mengganti operator sesi (station tidak terkunci) -- lihat SuggestedResourceSource.
    public int? SuggestedResourceId { get; set; }
    public string? SuggestedResourceName { get; set; }
    // "LINE_BUNDLE" | "PENERIMA" | "COUNTERPART" | "RIWAYAT" | null.
    public string? SuggestedResourceSource { get; set; }
}

public class BundleScanTimelineDto
{
    // Prompt 36: workflow_log_id -- dipakai tombol "Edit" per baris timeline (fitur Super
    // Admin di /b/{serial}).
    public int Id { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? SizeName { get; set; }
    public string? DivisionName { get; set; }
    public string? ResourceName { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    // Prompt 28: "NORMAL" atau "ADJUSTMENT" -- baris ADJUSTMENT tampil dengan badge
    // "Penyesuaian" + nilai bertanda (+/-) di timeline BundleScanCard.
    public string LogType { get; set; } = "NORMAL";
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
    public int? ActionQtyRejectRework { get; set; }
    public int? ActionQtyLost { get; set; }
    public string? ActionRemark { get; set; }

    // Prompt 28: true kalau divisi pemanggil punya minimal satu step ber-bundle bundle ini
    // dengan saldo reject/hilang > 0 -- independen dari AllowedAction di atas, dipakai
    // menampilkan tombol "Penyesuaian" di BundleScanCard. Detail saldo per step ada di
    // BundleScanInfoDto.AdjustSteps.
    public bool AllowedAdjust { get; set; }

    // --- Prompt 40: info penerima untuk form "Kirim Hasil", hanya terisi kalau AllowedAction
    // = "COMPLETE" dan ada step tujuan. NULL kalau tidak relevan (termasuk pengunjung publik). ---
    // auto_receive step tujuan.
    public bool? NextAutoReceive { get; set; }
    // Counterpart dari resource yang AKAN mencatat baris ini (operator sesi/Pelaksana saat
    // ini), valid terhadap NextDivisionId -- murni pratinjau, nilai final dihitung ulang
    // server saat submit. NULL bila tidak ada.
    public int? NextCounterpartResourceId { get; set; }
    public string? NextCounterpartResourceName { get; set; }
    // True HANYA kalau NextAutoReceive = true DAN counterpart NULL -- client WAJIB tampilkan
    // dropdown "Diterima Oleh" dan mewajibkan pilihan sebelum submit.
    public bool? ReceiverPickerRequired { get; set; }

    // Prompt 41 (lanjutan): true kalau step ActionArticleWorkflowId ber-print_kupon = 1 --
    // dipakai menampilkan tombol "Print Hasil" (cetak kupon manual, independen dari auto-print
    // saat diterima) selama AllowedAction = "EDIT" (baris baru dibuat, belum diterima tujuan).
    public bool PrintKupon { get; set; }
}

// Prompt 28: saldo reject/hilang per step ber-bundle milik divisi pemanggil untuk bundle ini
// -- dipakai prefill form Penyesuaian (pilih step kalau lebih dari satu, tampilkan saldo per
// kategori). Lihat SIS_Bundle_ScanInfo result set 4.
public class BundleAdjustStepSaldoDto
{
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int SaldoRejectPrint { get; set; }
    public int SaldoRejectFabric { get; set; }
    public int SaldoRejectSewing { get; set; }
    public int SaldoRejectRework { get; set; }
    public int SaldoLost { get; set; }
    // Divisi step ber-bundle berikutnya (terkunci, sama seperti alur COMPLETE) -- NULL kalau
    // step ini step ber-bundle terakhir artikel. Hanya relevan kalau Qty OK diisi > 0.
    public int? NextDivisionId { get; set; }
    public string? NextDivisionName { get; set; }
}

public class BundleScanInfoDto
{
    public BundleScanBundleDto Bundle { get; set; } = new();
    public List<BundleScanTimelineDto> Timeline { get; set; } = new();
    public BundleScanActionDto Action { get; set; } = new();
    public List<BundleAdjustStepSaldoDto> AdjustSteps { get; set; } = new();
}

public class ArticleWipStepDto
{
    public int ArticleWorkflowId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public bool RequiresBundle { get; set; }
    public int ReceivedPcs { get; set; }
    public int ReceivedBundleCount { get; set; }
    public int CompletedPcs { get; set; }
    public int CompletedBundleCount { get; set; }
    public int TotalBundlePcs { get; set; }
    public int TotalBundleCount { get; set; }
    public int QtyOrder { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
}

public class PublicBundleDetailDto
{
    public BundleScanInfoDto ScanInfo { get; set; } = new();
    public List<ArticleWipStepDto> Wip { get; set; } = new();
}

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
    public string? ResourcePersonName { get; set; }
    public string? LabelStatus { get; set; }
    public DateTime? PrintedAt { get; set; }
    public DateTime CreatedAt { get; set; }
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
    public string? ResourcePersonName { get; set; }
    public int? BundlingResourceId { get; set; }
    // Prompt 24: checkbox "Cetak label otomatis" di station (default true; admin /bundles
    // tidak mengirim field ini sehingga tetap berperilaku sama seperti sebelumnya).
    public bool AutoPrint { get; set; } = true;
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
    public string? ResourcePersonName { get; set; }
    public int? BundlingResourceId { get; set; }
    // Fix: opsional -- NULL berarti ukuran tidak diubah (dipakai admin /bundles yang belum
    // punya UI ganti ukuran); station selalu mengirim field ini lewat StationBundleUpdateRequest.
    public int? ArticleSizeId { get; set; }
}

public class BundleCreateResult
{
    public int Id { get; set; }
    // Prompt 24: nullable -- NULL kalau @SkipPrintJob = 1 (checkbox "Cetak label otomatis"
    // tidak dicentang di station).
    public int? PrintJobId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
}

// Prompt 24: "Buat Bundle" dari kartu WIP station Bundling -- ResourceId = operator sesi
// (WAJIB, dikirim ke SP sebagai @BundlingResourceId); Tailor* = penjahit opsional (dikirim
// sebagai @ResourceId/@ResourcePersonName di SIS_Bundle_Manage) -- nama field beda dari
// BundleCreateRequest supaya semantik operator-sesi vs penjahit tidak tertukar.
public class StationBundleCreateRequest
{
    public int ArticleId { get; set; }
    public int ArticleSizeId { get; set; }
    public int Qty { get; set; }
    public int ResourceId { get; set; }
    public int? TailorResourceId { get; set; }
    public string? TailorPersonName { get; set; }
    public bool AutoPrint { get; set; } = true;
}

// Prompt 24: Edit bundle dari tab OUT station Bundling.
// Fix: ArticleSizeId ditambahkan supaya ukuran bisa diubah dari modal Edit yang sama.
public class StationBundleUpdateRequest
{
    public int Qty { get; set; }
    public int ArticleSizeId { get; set; }
    public int ResourceId { get; set; }
    public int? TailorResourceId { get; set; }
    public string? TailorPersonName { get; set; }
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
}

public class BundleScanTimelineDto
{
    public string StepName { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public string? SizeName { get; set; }
    public string? DivisionName { get; set; }
    public string? ResourceName { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
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
    public string? ActionRemark { get; set; }
}

public class BundleScanInfoDto
{
    public BundleScanBundleDto Bundle { get; set; } = new();
    public List<BundleScanTimelineDto> Timeline { get; set; } = new();
    public BundleScanActionDto Action { get; set; } = new();
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

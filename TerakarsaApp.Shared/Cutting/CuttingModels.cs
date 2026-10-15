namespace TerakarsaApp.Shared.Cutting;

// Prompt 78-80 -- module Cutting (stok bundle dari hamparan).
// Istilah lapangan dipertahankan di nama DTO versi Inggris:
//   hamparan = spread, set = set, lembar per set = sheets per set,
//   rincian size = spread size, bundle = bundle (tabel bundles yang sudah ada).

// ==================== dropdown & hitungan ====================

public class CuttingArticleDto
{
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public int BundleTargetQty { get; set; }
    public int ProjectId { get; set; }
    public string? NoPo { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public int SpreadCount { get; set; }

    // Label dropdown "<PO> · <nama artikel>".
    public string Label => string.IsNullOrWhiteSpace(NoPo)
        ? ArticleName
        : $"{NoPo} · {ArticleName}";
}

public class CuttingSizeDto
{
    public int ArticleSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SizeSortOrder { get; set; }
    public int OrderQty { get; set; }
    public int NextFrom { get; set; }     // nomor pcs berikutnya (SIS_Cutting_NextNumber)
}

public class CuttingSuggestRequest
{
    public int Sheets { get; set; }
    public int Target { get; set; } = 50;
}

public class CuttingSuggestItemDto
{
    public int BundleSeq { get; set; }
    public int Qty { get; set; }
}

// ==================== simpan hamparan ====================

public class SpreadSizeInput
{
    public int ArticleSizeId { get; set; }
    public int SetCount { get; set; }
}

public class SpreadBundleInput
{
    public int ArticleSizeId { get; set; }
    public int SetNo { get; set; }
    public int Qty { get; set; }
}

public class SpreadCreateRequest
{
    public int ArticleId { get; set; }
    public string SpreadCode { get; set; } = string.Empty;
    public DateTime? SpreadDate { get; set; }
    public int SetCount { get; set; }
    public int SheetsPerSet { get; set; }
    public string? Note { get; set; }
    public List<SpreadSizeInput> Sizes { get; set; } = new();
    public List<SpreadBundleInput> Bundles { get; set; } = new();

    // true = "Simpan & cetak N stiker" (enqueue print job + MARK_PRINTED),
    // false = "Simpan draft".
    public bool Print { get; set; }
}

public class SpreadCreateResultDto
{
    public int SpreadId { get; set; }
    public int BundleCount { get; set; }
    public int JobCount { get; set; }
}

public class SpreadHeaderUpdateRequest
{
    public string SpreadCode { get; set; } = string.Empty;
    public DateTime? SpreadDate { get; set; }
    public string? Note { get; set; }
}

// ==================== daftar & detail ====================

public class SpreadListItemDto
{
    public int SpreadId { get; set; }
    public string SpreadCode { get; set; } = string.Empty;
    public DateTime SpreadDate { get; set; }
    public int SetCount { get; set; }
    public int SheetsPerSet { get; set; }
    public string Status { get; set; } = string.Empty;      // DRAFT | PRINTED
    public DateTime? PrintedAt { get; set; }
    public string? Note { get; set; }
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public int TotalBundles { get; set; }
    public int TotalPcs { get; set; }
    public int StockBundles { get; set; }
    public int TakenBundles { get; set; }
    public int NeedsReprintBundles { get; set; }
    public string? CreatedByName { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class SpreadDetailHeaderDto
{
    public int SpreadId { get; set; }
    public string SpreadCode { get; set; } = string.Empty;
    public DateTime SpreadDate { get; set; }
    public int SetCount { get; set; }
    public int SheetsPerSet { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTime? PrintedAt { get; set; }
    public string? Note { get; set; }
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public int BundleTargetQty { get; set; }
    public string? NoPo { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? CreatedByName { get; set; }
    public DateTime CreatedAt { get; set; }
    public int TotalBundles { get; set; }
    public int TotalPcs { get; set; }
    public int StockBundles { get; set; }
    public int StockPcs { get; set; }
    public int TakenBundles { get; set; }
}

public class SpreadDetailSizeDto
{
    public int SpreadSizeId { get; set; }
    public int ArticleSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SizeSortOrder { get; set; }
    public int SetCount { get; set; }
    public int NumberFrom { get; set; }
    public int NumberTo { get; set; }
}

public class SpreadDetailBundleDto
{
    public int BundleId { get; set; }
    public string CuttingCode { get; set; } = string.Empty;
    public string Serial { get; set; } = string.Empty;
    public int SpreadSizeId { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SizeSortOrder { get; set; }
    public int SetNo { get; set; }
    public int BundleSeq { get; set; }
    public int Qty { get; set; }
    public int NumberFrom { get; set; }
    public int NumberTo { get; set; }
    public string StockStatus { get; set; } = string.Empty;   // STOCK | TAKEN
    public bool NeedsReprint { get; set; }
    public DateTime? TakenAt { get; set; }
    public string? TakenByResourceName { get; set; }

    public bool IsTaken => StockStatus == "TAKEN";

    // "M-111 – M-165" seperti mockup Detail Hamparan.
    public string NumberRange => $"{SizeName}-{NumberFrom} – {SizeName}-{NumberTo}";
}

public class SpreadDetailDto
{
    public SpreadDetailHeaderDto Header { get; set; } = new();
    public List<SpreadDetailSizeDto> Sizes { get; set; } = new();
    public List<SpreadDetailBundleDto> Bundles { get; set; } = new();
}

// ==================== edit bundle dalam set ====================

public class SpreadBundleQtyInput
{
    public int BundleId { get; set; }
    public int Qty { get; set; }
}

// Dipakai ketiga action SIS_SpreadBundle_Manage: total qty per set harus tetap
// = sheets_per_set, jadi UI selalu mengirim qty baru SELURUH bundle di set itu.
public class SpreadBundleSaveRequest
{
    public List<SpreadBundleQtyInput> Bundles { get; set; } = new();
}

public class SpreadBundleAddRequest
{
    public int SpreadSizeId { get; set; }
    public int SetNo { get; set; }
    public int Qty { get; set; }
    public List<SpreadBundleQtyInput> Bundles { get; set; } = new();
}

public class SpreadBundleRemoveRequest
{
    public List<SpreadBundleQtyInput> Bundles { get; set; } = new();
}

// ==================== stok bundle (landing) ====================

public class CuttingStockTotalsDto
{
    public int StockBundles { get; set; }
    public int StockPcs { get; set; }
    public int TakenToday { get; set; }
    public int DraftSpreads { get; set; }
}

public class CuttingStockSizeDto
{
    public int ArticleId { get; set; }
    public string? NoPo { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public int BundleTargetQty { get; set; }
    public int SpreadCount { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int SizeSortOrder { get; set; }
    public int TotalBundles { get; set; }
    public int StockBundles { get; set; }
    public int TakenBundles { get; set; }
    public int StockPcs { get; set; }
}

public class CuttingStockSummaryDto
{
    public CuttingStockTotalsDto Totals { get; set; } = new();
    public List<CuttingStockSizeDto> Sizes { get; set; } = new();
}

public class CuttingTakenTodayDto
{
    public int BundleId { get; set; }
    public string CuttingCode { get; set; } = string.Empty;
    public string Serial { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string? NoPo { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public string? TakenByResourceName { get; set; }
    public DateTime TakenAt { get; set; }
}

// ==================== Prompt 80: Scan Stok Bundle di station ====================

// Satu bundle hasil scan QR / input kode manual, siap dikonfirmasi sebelum diambil.
public class CuttingBundleScanDto
{
    public int BundleId { get; set; }
    public string CuttingCode { get; set; } = string.Empty;
    public string Serial { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string ArticleName { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public int Qty { get; set; }
    public int SetNo { get; set; }
    public int NumberFrom { get; set; }
    public int NumberTo { get; set; }
    public string SpreadCode { get; set; } = string.Empty;
    public DateTime SpreadDate { get; set; }

    public string NumberRange => $"{SizeName}-{NumberFrom} s/d {SizeName}-{NumberTo}";
}

public class CuttingBundleTakeRequest
{
    public List<int> BundleIds { get; set; } = new();
    public int ResourceId { get; set; }          // Line/penjahit tujuan (pelaksana sesi station)
}

public class CuttingBundleTakeResultDto
{
    public int TakenCount { get; set; }
    public int TotalPcs { get; set; }
}

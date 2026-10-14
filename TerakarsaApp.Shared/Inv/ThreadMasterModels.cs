namespace TerakarsaApp.Shared.Inv;

// Prompt 71: DTO master module Stok Benang (schema inv) -- jenis benang, merk,
// lokasi (rak), dan SKU benang.
//
// CATATAN pemetaan EF: setiap property yang punya setter HARUS ada sebagai kolom
// di result set SP yang mengisi DTO ini. Helper tampilan dibuat get-only supaya
// tidak ikut dicari EF (pola sama dengan TerakarsaApp.Shared/Tni).

public class ThreadTypeDto
{
    public int ThreadTypeId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int ItemCount { get; set; }

    public bool BolehHapus => ItemCount == 0;
}

public class ThreadBrandDto
{
    public int ThreadBrandId { get; set; }
    public string Name { get; set; } = string.Empty;
    public int ItemCount { get; set; }

    public bool BolehHapus => ItemCount == 0;
}

public class ThreadLocationDto
{
    public int ThreadLocationId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string? Name { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; }

    // isi rak saat ini
    public int ItemCount { get; set; }        // jumlah SKU yang punya qty_whole > 0 di rak ini
    public int QtyWholeTotal { get; set; }
    public int SplitCount { get; set; }

    public bool Kosong => QtyWholeTotal == 0 && SplitCount == 0;
    public string Label => string.IsNullOrWhiteSpace(Name) ? Code : $"{Code} · {Name}";
}

// Satu baris daftar SKU. Dipakai juga untuk detail SKU dan hasil scan `TB:<sku_code>`
// -- inv.SIS_ThreadItem_GetById (@Bagian='ITEM') dan _GetBySku mengembalikan kolom
// yang sama persis dengan _List.
public class ThreadItemDto
{
    public int ThreadItemId { get; set; }
    public string SkuCode { get; set; } = string.Empty;
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public string ConeSize { get; set; } = string.Empty;   // KECIL | BESAR
    public string? PhotoPath { get; set; }
    public bool IsActive { get; set; }

    public int ThreadTypeId { get; set; }
    public string TypeCode { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public int ThreadBrandId { get; set; }
    public string BrandName { get; set; } = string.Empty;

    public int QtyWholeTotal { get; set; }
    public int SplitCountInStock { get; set; }
    public int SplitGramInStock { get; set; }
    public int SplitCountIssued { get; set; }
    public string? LocationCodes { get; set; }             // "A1 / B5 / X12"

    public int TotalCount { get; set; }                    // total hasil filter (paging)

    // -------- bantuan tampilan --------
    public string ConeSizeLabel => ConeSize == "KECIL" ? "Kones Kecil" : "Kones Besar";
    public string Judul => string.IsNullOrWhiteSpace(ColorCode) ? ColorName : $"{ColorName} · {ColorCode}";
    public string Keterangan => $"{TypeName} · {BrandName} · {ConeSizeLabel}";
    public bool AdaFoto => !string.IsNullOrWhiteSpace(PhotoPath);
}

// Stok whole SKU per rak (result set 2 inv.SIS_ThreadItem_GetById).
public class ThreadItemStockDto
{
    public int ThreadLocationId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string? Name { get; set; }
    public int QtyWhole { get; set; }
    public int SplitCount { get; set; }
}

// Kones split SKU (result set 3 inv.SIS_ThreadItem_GetById).
public class ThreadSplitConeDto
{
    public int ThreadSplitConeId { get; set; }
    public string ConeCode { get; set; } = string.Empty;
    public int ThreadItemId { get; set; }
    public int WeightGram { get; set; }
    public string Status { get; set; } = string.Empty;     // IN_STOCK | ISSUED | EMPTY
    public int? ThreadLocationId { get; set; }
    public string? LocationCode { get; set; }
    public int? IssuedToResourceId { get; set; }
    public string? IssuedToResourceName { get; set; }
    public int? IssuedProjectId { get; set; }
    public string? IssuedProjectName { get; set; }
    public DateTime CreatedAt { get; set; }

    public bool SedangDipakai => Status == "ISSUED";

    // "A1" untuk kones di rak, "Dipakai · Line 2" untuk kones yang ada di line.
    public string TempatLabel => SedangDipakai
        ? $"Dipakai · {IssuedToResourceName ?? "line"}"
        : LocationCode ?? "-";
}

// Gabungan 3 result set inv.SIS_ThreadItem_GetById (dirakit di API).
public class ThreadItemDetailDto
{
    public ThreadItemDto? Item { get; set; }
    public List<ThreadItemStockDto> Locations { get; set; } = new();
    public List<ThreadSplitConeDto> SplitCones { get; set; } = new();
}

public class ThreadItemListResult
{
    public List<ThreadItemDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
}

// -------------------- request --------------------

public class ThreadTypeSaveRequest
{
    public int? ThreadTypeId { get; set; }                 // null = baru
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int SortOrder { get; set; }
}

public class ThreadBrandSaveRequest
{
    public int? ThreadBrandId { get; set; }
    public string Name { get; set; } = string.Empty;
}

public class ThreadLocationSaveRequest
{
    public int? ThreadLocationId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string? Name { get; set; }
    public int SortOrder { get; set; }
}

public class ThreadItemSaveRequest
{
    public int? ThreadItemId { get; set; }                 // null = SKU baru (sku_code dibuat SP)
    public int ThreadTypeId { get; set; }
    public int ThreadBrandId { get; set; }
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public string ConeSize { get; set; } = "BESAR";        // KECIL | BESAR
}

public class ThreadSetActiveRequest
{
    public bool IsActive { get; set; }
}

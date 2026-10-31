namespace TerakarsaApp.Shared.ManualOutputs;

// Prompt 83: OUTPUT MANUAL -- output yang tidak lewat bundle, dicatat tiap divisi sendiri
// dari tab OUT stasiun. Tidak bergantung artikel, PO, maupun divisi lain.
//
// TIDAK ADA properti harga di seluruh file ini, dan memang tidak boleh ada: harga melekat
// ke lock item (lihat TerakarsaApp.Shared/Payroll/PayrollRekapModels.cs) dan PIC tidak
// pernah melihat atau mengisinya. Satu-satunya harga di sini adalah UnitPrice READ-ONLY di
// ManualOutputAdminRowDto, untuk dilihat admin.
//
// Lihat sql/sp_ManualOutput_Manage.sql & sql/sp_ManualOutput_Select.sql.

// ---- Baris untuk checklist lock di tab OUT stasiun (SIS_ManualOutput_StationList) ----
public class ManualOutputRowDto
{
    public int ManualOutputId { get; set; }
    public int ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int? ArticleId { get; set; }          // opsional -- boleh ditempel admin belakangan
    public string? ArticleName { get; set; }
    public string? NoPo { get; set; }
    public string WorkDescription { get; set; } = string.Empty;
    public string? SizeName { get; set; }
    public int Qty { get; set; }                 // boleh 0 atau MINUS (minus = potongan)
    public int RejectQty { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsLocked { get; set; }
    public string? LockPeriodCode { get; set; }  // periode gajian baris ini, dari lock
    public bool IsPotongan { get; set; }         // badge "Potongan" -- Qty < 0
}

// ---- Baris untuk halaman admin "Output Manual" (SIS_ManualOutput_List) ----
public class ManualOutputAdminRowDto
{
    public int ManualOutputId { get; set; }
    public int ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int DivisionId { get; set; }
    public string? DivisionName { get; set; }
    public int? ArticleId { get; set; }
    public string? ArticleName { get; set; }
    public string? NoPo { get; set; }
    public string? ProjectName { get; set; }
    public string WorkDescription { get; set; } = string.Empty;
    public string? SizeName { get; set; }
    public int Qty { get; set; }
    public int RejectQty { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? LockId { get; set; }
    public bool IsLocked { get; set; }
    public int? PayrollPeriodId { get; set; }
    public string? PeriodCode { get; set; }
    public bool IsPeriodFinalized { get; set; }
    public bool IsPotongan { get; set; }
    public int? LockItemId { get; set; }
    // READ-ONLY di halaman ini -- koreksi harga hanya di Rekap Gajian.
    public decimal? UnitPrice { get; set; }
}

// ---- Request ----

// Simpan dari stasiun. ResourceId TIDAK ada di sini: operator diambil dari sesi stasiun
// dan divisi dari stasiun itu (keduanya ditentukan server), sesuai Bagian 4.
public class ManualOutputSaveRequest
{
    public int? ManualOutputId { get; set; }     // null = baru
    public int? ArticleId { get; set; }          // opsional
    public string WorkDescription { get; set; } = string.Empty;
    public string? SizeName { get; set; }
    public int Qty { get; set; }
    public int RejectQty { get; set; }
    public string? Note { get; set; }            // WAJIB kalau Qty < 0 (ditegakkan SP)
}

// Aksi massal "Hubungkan ke Artikel" di halaman admin.
public class ManualOutputLinkArticleRequest
{
    public List<int> ManualOutputIds { get; set; } = new();
    public int ArticleId { get; set; }
}

public class ManualOutputLinkArticleResultDto
{
    public int LinkedCount { get; set; }
    // Jumlah baris SUDAH LOCK yang unit_price lock item-nya ikut terisi dari tarif artikel
    // yang baru ditempel. Harga yang sudah diisi admin tidak pernah ditimpa.
    public int PricedCount { get; set; }
}

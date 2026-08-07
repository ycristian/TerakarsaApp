namespace TerakarsaApp.Shared.Dashboards;

// Prompt 38: Dashboard Target Harian -- token kiosk (admin, JWT) + agregasi read-only
// (kiosk, X-Dashboard-Token). Lihat TerakarsaApp.API/Authorization/RequireDashboardTokenAttribute.

public class DashboardTokenDto
{
    public int Id { get; set; }
    public string TokenName { get; set; } = string.Empty;
    public string TokenPreview { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
    public int RefreshIntervalMinutes { get; set; } = 30;
    public DateTime? LastSeenAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class DashboardTokenCreateRequest
{
    public string TokenName { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
    public int RefreshIntervalMinutes { get; set; } = 30;
}

public class DashboardTokenUpdateRequest
{
    public int Id { get; set; }
    public string TokenName { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
    public int RefreshIntervalMinutes { get; set; } = 30;
}

public class DashboardTokenCreateResult
{
    public int Id { get; set; }
    public string Token { get; set; } = string.Empty;
    public string Link { get; set; } = string.Empty;
}

public class DashboardTokenLinkDto
{
    public string Link { get; set; } = string.Empty;
}

public class DashboardTokenPagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class DashboardTokenPagedResult
{
    public List<DashboardTokenDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

// Kiosk -- /api/dashboard/me, dipakai saat aktivasi & menentukan irama refresh.
public class DashboardMeDto
{
    public string TokenName { get; set; } = string.Empty;
    public int RefreshIntervalMinutes { get; set; } = 30;
}

// Hasil SIS_DashboardToken_GetByToken -- dipakai RequireDashboardTokenAttribute (internal API, bukan response client).
public class DashboardTokenAuthDto
{
    public int DashboardTokenId { get; set; }
    public string TokenName { get; set; } = string.Empty;
    public int RefreshIntervalMinutes { get; set; } = 30;
}

public class DashboardHeaderDto
{
    public DateTime PlanDate { get; set; }
    public DateTime ServerTime { get; set; }
    public int TotalDivision { get; set; }
    public int PlannedDivision { get; set; }
}

public class DashboardDivisionDto
{
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public string DashboardMode { get; set; } = "DIVISION";
    public bool HasPlan { get; set; }
    public bool IsHoliday { get; set; }
    public bool HasTarget { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public int? Headcount { get; set; }
    public int? TargetPerPerson { get; set; }
    public int? TargetTotal { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
    public int Wip { get; set; }
    public int WipBundles { get; set; }
    public int Transit { get; set; }
    public int? EffectiveMinutesTotal { get; set; }
    public int? EffectiveMinutesElapsed { get; set; }
    public double? ExpectedPercent { get; set; }
    public double? ActualPercent { get; set; }
    public int? DiffQty { get; set; }
    public double? DiffPercent { get; set; }
    public int? RemainingQty { get; set; }
    public double? OutputPerPersonPerHour { get; set; }
}

public class DashboardResourceDto
{
    public int DivisionId { get; set; }
    public int ResourceId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public bool HasPlan { get; set; }
    public bool IsHoliday { get; set; }
    public bool HasTarget { get; set; }
    public bool HasTimeOverride { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public int? Headcount { get; set; }
    public int? TargetPerPerson { get; set; }
    public int? TargetTotal { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
    public int Wip { get; set; }
    public int WipBundles { get; set; }
    public int? EffectiveMinutesTotal { get; set; }
    public int? EffectiveMinutesElapsed { get; set; }
    public double? ExpectedPercent { get; set; }
    public double? ActualPercent { get; set; }
    public int? DiffQty { get; set; }
    public double? DiffPercent { get; set; }
    public int? RemainingQty { get; set; }
    public double? OutputPerPersonPerHour { get; set; }
}

public class DashboardTargetHarianResult
{
    public DashboardHeaderDto Header { get; set; } = new();
    public List<DashboardDivisionDto> Divisions { get; set; } = new();
    public List<DashboardResourceDto> Resources { get; set; } = new();
}

// Prompt 45: modal drill-down per line -- lihat sql/sp_Report_LineDetail.sql.

// Tab "Per Penjahit". EmployeeId NULL = baris "Tanpa Penjahit" (bundle tanpa employee_id).
// Kontribusi % dan org/jam dihitung di client dari QtyOk/JamEfektifBerjalan, bukan dari SP.
public class LineEmployeeProgressDto
{
    public int? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
    public int Wip { get; set; }
    public int WipBundles { get; set; }
    public DateTime? LastReceivedAt { get; set; }
    public int? JamEfektifBerjalan { get; set; }
}

// Tab "WIP" (Prompt 45, dipersempit Prompt 52 -- sebelumnya "PO Berjalan", ikut status TRANSIT).
// Hanya berisi bundle DIKERJAKAN sekarang, kolom Status dibuang (lihat sql/sp_Report_LineDetail.sql).
// Pengelompokan (project+artikel) dan umur dihitung di client.
public class LineActiveBundleDto
{
    public int ProjectId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string? TailorName { get; set; }
    public string? EmployeeName { get; set; }
    public DateTime SejakAt { get; set; }
}

// Prompt 52: tab "Transit" (baru) -- satu baris per bundle yang MENUNGGU DITERIMA oleh divisi/
// resource ini (kepemilikan diselaraskan ke TUJUAN, bukan pengirim -- lihat
// SIS_Report_LineTransitBundles). AsalDivisionName/AsalResourceName = pengirim, dibutuhkan untuk
// menelusuri fisik barang. BelumDitentukanLine = true kalau resource pengirim tidak punya
// counterpart valid di divisi tujuan (destinasi line tidak bisa diprediksi dari data) -- SP tetap
// mengembalikan baris ini di SETIAP line divisi tujuan (mode resource) supaya tidak hilang dari
// pencarian; client mengelompokkannya ke grup penampung "Belum ditentukan line", bukan grup
// project+artikel biasa. Umur dihitung di client dari DiserahkanAt.
public class LineTransitBundleDto
{
    public int ProjectId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string? AsalDivisionName { get; set; }
    public string? AsalResourceName { get; set; }
    public DateTime DiserahkanAt { get; set; }
    public bool BelumDitentukanLine { get; set; }
}

// Prompt 46: tab "Selesai" -- satu baris per bundle yang SELESAI dikerjakan line ini (lihat
// SIS_Report_LineCompletedBundles). Qty = total qty bundle; QtyOk/QtyReject/QtyLost = qty hasil
// step ybs (basis reject 3 kategori, identik LineEmployeeProgressDto.QtyReject). ReceivedAt bisa
// NULL kalau bundle memang dibuat langsung di line ini. Lama dihitung di client dari
// ReceivedAt -> SelesaiAt.
public class LineCompletedBundleDto
{
    public int ProjectId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string SizeName { get; set; } = string.Empty;
    public int Qty { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
    public int QtyLost { get; set; }
    public string? TailorName { get; set; }
    public string? EmployeeName { get; set; }
    public DateTime? ReceivedAt { get; set; }
    public DateTime SelesaiAt { get; set; }
}

// Prompt 46 (revisi): tab "Reject" -- satu baris per bundle bermasalah pada periode yang sama
// dengan tab Selesai (lihat SIS_Report_LineRejectBundles). Kategori reject TIDAK digabung --
// QtyRejectPrint/Fabric/Sewing/Rework dikembalikan terpisah supaya client tidak menjumlahkannya
// jadi satu angka. "Rjk" (basis 3 kategori Print+Fabric+Sewing, TIDAK termasuk Rework) tetap
// dihitung DI CLIENT dari 3 field itu untuk persen/ambang & konsistensi dengan tab Selesai/Per
// Penjahit -- lihat verifikasi Prompt 46. TotalOutputPo = total output (basis 3 kategori+Hlg) PO
// (project+artikel) ini di line ini pada periode itu, dipakai client untuk "Rjk N dari M".
// TotalOutputLine = total output SELURUH line pada periode itu (nilai sama di semua baris),
// dipakai untuk persen baris TOTAL. TailorName sengaja tidak ada di sini -- tab ini sudah
// discope ke satu line/resource (judul modal), jadi nama line redundan di kolom Penjahit; Remark
// = article_workflow_logs.remark (catatan bebas pada baris log ybs, BUKAN bundles.remarks)
// ditambahkan sebagai gantinya.
public class LineRejectBundleDto
{
    public int ProjectId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public int BundleId { get; set; }
    public int BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string Serial { get; set; } = string.Empty;
    public string? SizeName { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? EmployeeName { get; set; }
    public string? Remark { get; set; }
    public string LogType { get; set; } = string.Empty;
    public DateTime WaktuAt { get; set; }
    public int TotalOutputPo { get; set; }
    public int TotalOutputLine { get; set; }
}

// Prompt 51: tab "Tren" (grafik harian + rekap mingguan) & "Per Jam". ResourceId di seluruh
// endpoint modal (termasuk DTO di atas) kini opsional -- NULL = mode divisi (agregat seluruh
// resource divisi tsb), lihat sql/sp_Report_LineDetail.sql.

// Tab "Tren", grafik harian. QtyTerima = qty diterima line/divisi ini dari step sebelumnya pada
// tanggal ybs (metrik baru, lihat komentar SIS_Report_LineTrendDaily); QtyOk basis identik
// dengan LineEmployeeProgressDto.QtyOk.
public class LineTrendDailyDto
{
    public DateTime Tanggal { get; set; }
    public int QtyTerima { get; set; }
    public int QtyOk { get; set; }
}

// Tab "Tren", rekap mingguan per periode gajian. Selisih/Rjk%/org-hari dihitung di client.
// JumlahOrang NULL bila PPIC tidak input headcount sama sekali pada periode itu (tampilkan "-").
public class LineTrendWeeklyDto
{
    public DateTime PeriodeMulai { get; set; }
    public DateTime PeriodeSelesai { get; set; }
    public string KodeMinggu { get; set; } = string.Empty;
    public int QtyTerima { get; set; }
    public int QtyOk { get; set; }
    public int QtyReject { get; set; }
    public int? JumlahOrang { get; set; }
    public int JumlahHariKerja { get; set; }
}

// Tab "Per Jam", satu baris per jam (result set 1 SIS_Report_LineHourly). Jam istirahat ->
// QtyTerima/QtyOk NULL (bukan 0) -- lihat Bagian 3 prompt 51.
public class LineHourlyDto
{
    public int Jam { get; set; }
    public bool IsIstirahat { get; set; }
    public int? QtyTerima { get; set; }
    public int? QtyOk { get; set; }
}

// Tab "Per Jam", result set 2 SIS_Report_LineHourly. TargetPulang = jam pulang PENUH sesuai
// jadwal (tidak dipotong jam berjalan, beda dari jam terakhir di daftar LineHourlyDto saat
// tanggal aktif = hari ini). TargetHarian/TargetPerJam NULL bila divisi tidak punya target hari
// itu -- client TIDAK boleh menampilkan 0 atau garis target karangan (lihat Bagian 3 prompt 51).
public class LineHourlyMetaDto
{
    public TimeSpan? JamMasuk { get; set; }
    public TimeSpan? TargetPulang { get; set; }
    public int? TargetHarian { get; set; }
    public double? TargetPerJam { get; set; }
}

public class LineHourlyResult
{
    public List<LineHourlyDto> Hours { get; set; } = new();
    public LineHourlyMetaDto Meta { get; set; } = new();
}

// Ambang penumpukan/mandek/reject modal drill-down line -- satu tempat, supaya gampang dipindah
// ke setting per divisi nanti (lihat Bagian 6 prompt 45 & Bagian 7 prompt 46).
public static class LineDetailThresholds
{
    public const int BundleStaleRedDays = 4;
    public const int BundleStaleYellowDays = 3;
    public const double WipOverloadMultiplier = 3.0;
    public const double RejectHighPercent = 3.0;
}

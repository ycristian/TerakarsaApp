namespace TerakarsaApp.Shared.Stations;

public class StationDto
{
    public int Id { get; set; }
    public string StationCode { get; set; } = string.Empty;
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    // Prompt 16: resource bawaan perangkat (1 device = 1 resource, opsional).
    public int? DefaultResourceId { get; set; }
    public string? DefaultResourceName { get; set; }
    public bool AllowResourceChange { get; set; } = true;
    // Prompt 25: stasiun ini boleh membuka modul packing (tab "Packing" di /station).
    public bool EnablePacking { get; set; }
    // Prompt 20: status pairing untuk admin -- station_token sendiri tidak pernah dikembalikan.
    public DateTime? PairedAt { get; set; }
    public DateTime? PairingCodeExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int? UpdatedBy { get; set; }
}

public class StationCreateRequest
{
    public string StationCode { get; set; } = string.Empty;
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public bool IsActive { get; set; } = true;
    public int? DefaultResourceId { get; set; }
    public bool AllowResourceChange { get; set; } = true;
    public bool EnablePacking { get; set; }
}

public class StationUpdateRequest
{
    public int Id { get; set; }
    public string StationCode { get; set; } = string.Empty;
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public bool IsActive { get; set; }
    public int? DefaultResourceId { get; set; }
    public bool AllowResourceChange { get; set; } = true;
    public bool EnablePacking { get; set; }
}

public class StationPagedRequest
{
    public string? Search { get; set; }
    public int PageNumber { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string? SortColumn { get; set; }
    public string SortDirection { get; set; } = "asc";
}

public class StationPagedResult
{
    public List<StationDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int PageNumber { get; set; }
    public int PageSize { get; set; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
}

// Dikembalikan sekali saja saat CREATE/CLAIM_PAIRING — token penuh tidak pernah
// muncul lagi setelah response ini (admin tidak lagi melihat token sama sekali,
// lihat [[prompt-20-station-pairing]]).
public class StationTokenResult
{
    public int Id { get; set; }
    public string Token { get; set; } = string.Empty;
}

// Prompt 20: hasil "Buat Kode Pairing" di Kelola Stasiun -- ditampilkan sekali di modal
// admin (kode besar + link siap salin), tidak disimpan di client selain untuk tampilan ini.
public class StationPairingResult
{
    public string Code { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public string Link { get; set; } = string.Empty;
}

// Prompt 20: body POST api/station-device/claim -- endpoint ANONIM, kode 5 karakter
// sekali pakai + kedaluwarsa 15 menit adalah satu-satunya lapisan keamanannya.
public class StationClaimRequest
{
    public string Code { get; set; } = string.Empty;
}

// Info stasiun untuk perangkat yang sudah membawa X-Station-Token (dipakai Prompt 9b).
public class StationMeDto
{
    public int StationId { get; set; }
    public string StationName { get; set; } = string.Empty;
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    // Prompt 16: resource bawaan perangkat -- lihat StationDevice.razor untuk 3 mode pakainya.
    public int? DefaultResourceId { get; set; }
    public string? DefaultResourceName { get; set; }
    public bool AllowResourceChange { get; set; } = true;
    // Prompt 25: gate tab "Packing" di /station.
    public bool EnablePacking { get; set; }
}

// Prompt 42: tab "Rekap Produksi" di /station (menggantikan Rekap Penjahit Prompt 41) -- lihat
// SIS_Report_RekapStruk di sql/sp_Report_RekapStruk.sql. Level = pilihan terdalam yang diisi
// di dropdown cascading Divisi -> Resource -> Penjahit ("DIVISION" | "RESOURCE" | "EMPLOYEE").
public class RekapStrukHeaderDto
{
    public string DivisionName { get; set; } = string.Empty;
    public string? ResourceName { get; set; }
    public string? EmployeeName { get; set; }
    public string Level { get; set; } = "DIVISION";
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public int TotalQty { get; set; }
}

// Baris Detail (harian, Result set 2) maupun WIP (snapshot, Result set 3) -- bentuknya sama
// ("granularitas sama seperti result set 2" per prompt), bedanya EventDate NULL utk WIP (bukan
// kejadian harian) dan kelima kolom reject/lost WIP selalu 0. Label sudah diformat SP sesuai
// Level (bundle letter+no / nama penjahit / nama resource) -- client tinggal cetak apa adanya.
public class RekapStrukRowDto
{
    public DateTime? EventDate { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? SizeName { get; set; }
    public string Label { get; set; } = string.Empty;
    public int Qty { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
}

public class RekapStrukResultDto
{
    public RekapStrukHeaderDto? Header { get; set; }
    public List<RekapStrukRowDto> Detail { get; set; } = new();
    public List<RekapStrukRowDto> Wip { get; set; } = new();
}

public class RekapStrukPrintRequest
{
    public string Level { get; set; } = "DIVISION";
    public int DivisionId { get; set; }
    public int? ResourceId { get; set; }
    public int? EmployeeId { get; set; }
    public DateTime Date { get; set; }
}

// Fix: tombol "Cetak Karyawan" -- terpisah dari RekapStrukPrintRequest (tidak ada @Level,
// @Date di sini SATU HARI, bukan periode gajian mingguan -- lihat SIS_Report_RekapKaryawanPrint).
public class RekapKaryawanPrintRequest
{
    public int DivisionId { get; set; }
    public int? ResourceId { get; set; }
    public int? EmployeeId { get; set; }
    public DateTime Date { get; set; }
}

// Ad hoc (2026-08-28): tombol "Cetak WIP" -- terpisah dari struk Rekap Produksi (job_type
// REKAP_WIP, lihat SIS_Report_WipPrint). Sama bentuk dgn RekapKaryawanPrintRequest (tanpa
// @Level, @Date SATU HARI/snapshot -- boleh tanggal lampau utk lihat WIP per akhir hari itu).
public class RekapWipPrintRequest
{
    public int DivisionId { get; set; }
    public int? ResourceId { get; set; }
    public int? EmployeeId { get; set; }
    public DateTime Date { get; set; }
}

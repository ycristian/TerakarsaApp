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
}

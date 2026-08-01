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

using TerakarsaApp.Shared.WorkSchedules;

namespace TerakarsaApp.Shared.DailyPlans;

// Prompt 37: Planning Harian PPIC -- jadwal, jumlah orang, target per tanggal per divisi
// (+ per resource bila DashboardMode = RESOURCE). Setting default (Prompt 36) hanya
// prefill; baris di sini adalah satu-satunya data yang dianggap "sudah direncanakan".

public class DailyPlanDivisionDto
{
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public string DashboardMode { get; set; } = "DIVISION";
    public int DefaultTargetPerPerson { get; set; }
    public bool IsSaved { get; set; }
    public int? DailyDivisionPlanId { get; set; }
    public bool IsHoliday { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public int? Headcount { get; set; }
    public int? TargetPerPerson { get; set; }
    public string? Remark { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public string? SavedByName { get; set; }
}

public class DailyPlanResourceDto
{
    public int DivisionId { get; set; }
    public int ResourceId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public int? Headcount { get; set; }
    public int? TargetPerPerson { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public string? Remark { get; set; }
    public bool IsSaved { get; set; }
}

public class DailyPlanGetByDateResult
{
    public List<DailyPlanDivisionDto> Divisions { get; set; } = new();
    public List<DailyPlanResourceDto> Resources { get; set; } = new();
    public List<WorkBreakDto> Breaks { get; set; } = new();
}

public class DailyPlanResourceSaveDto
{
    public int ResourceId { get; set; }
    public int Headcount { get; set; }
    public int TargetPerPerson { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public string? Remark { get; set; }
}

public class SaveDailyPlanRequest
{
    public DateTime PlanDate { get; set; }
    public bool IsHoliday { get; set; }
    public TimeSpan? StartTime { get; set; }
    public TimeSpan? EndTime { get; set; }
    public int? Headcount { get; set; }
    public int? TargetPerPerson { get; set; }
    public string? Remark { get; set; }
    public List<DailyPlanResourceSaveDto> Resources { get; set; } = new();
}

public class CopyDailyPlanRequest
{
    public DateTime SourceDate { get; set; }
    public DateTime TargetDate { get; set; }
}

public class CopyDailyPlanResult
{
    public int CopiedCount { get; set; }
}

public class DailyPlanDateSummaryDto
{
    public DateTime PlanDate { get; set; }
    public int TotalDivision { get; set; }
    public int SavedDivision { get; set; }
    public int HolidayDivision { get; set; }
}

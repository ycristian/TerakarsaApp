namespace TerakarsaApp.Shared.WorkSchedules;

// Prompt 36: fondasi dashboard target -- setting default jam kerja per divisi per hari
// dan jam istirahat. HANYA dipakai untuk prefill Planning Harian PPIC (Prompt 37) dan
// fallback tampilan; dashboard TV (Prompt 38) selalu memakai angka yang di-save PPIC.

public class WorkScheduleDayDto
{
    public int? Id { get; set; }
    public int DivisionId { get; set; }
    public int DayOfWeek { get; set; }          // 1 = Senin ... 7 = Minggu
    public bool IsWorkingDay { get; set; } = true;
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
}

public class WorkScheduleDivisionDto
{
    public int Id { get; set; }
    public string DivisionCode { get; set; } = string.Empty;
    public string DivisionName { get; set; } = string.Empty;
    public bool ShowInDashboard { get; set; } = true;
    public string DashboardMode { get; set; } = "DIVISION";
    public int DashboardSortOrder { get; set; }
    public int DefaultTargetPerPerson { get; set; }
    public List<WorkScheduleDayDto> Days { get; set; } = new();
}

public class WorkScheduleDaySaveDto
{
    public int DayOfWeek { get; set; }
    public bool IsWorkingDay { get; set; } = true;
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
}

public class SaveDivisionScheduleRequest
{
    public int DivisionId { get; set; }
    public List<WorkScheduleDaySaveDto> Days { get; set; } = new();
    public int DefaultTargetPerPerson { get; set; }
}

public class WorkBreakDto
{
    public int Id { get; set; }
    public string BreakName { get; set; } = string.Empty;
    public int? DayOfWeek { get; set; }         // null = berlaku semua hari
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public int SortOrder { get; set; }
}

public class WorkBreakCreateRequest
{
    public string BreakName { get; set; } = string.Empty;
    public int? DayOfWeek { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public int SortOrder { get; set; }
}

public class WorkBreakUpdateRequest
{
    public int Id { get; set; }
    public string BreakName { get; set; } = string.Empty;
    public int? DayOfWeek { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public int SortOrder { get; set; }
}

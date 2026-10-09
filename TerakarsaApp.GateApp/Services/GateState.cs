using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.GateApp.Services;

// Prompt 70: satu tempat status yang dibagi antara dua background service (CardSyncService,
// TapQueueService) dan UI Blazor. UI berlangganan OnChanged lalu StateHasChanged.
//
// Status online/offline SENGAJA diturunkan dari keberhasilan panggilan terakhir, bukan dari ping
// terpisah: yang penting bagi satpam adalah "apakah tap saya sampai", bukan apakah kabel nyambung.
public class GateState
{
    private readonly object _lock = new();

    public event Action? OnChanged;

    public bool IsOnline { get; private set; }
    public int PendingTapCount { get; private set; }

    // Selisih jam tablet terhadap server pada sync terakhir, dalam detik (positif = tablet maju).
    public double? ClockDriftSeconds { get; private set; }
    public bool ClockDriftWarning { get; private set; }

    public DateTime? LastSyncAt { get; private set; }
    public string? LastError { get; private set; }

    public List<GateCardDto> Cards { get; private set; } = new();
    public List<GateEmployeeDto> Employees { get; private set; } = new();
    public GateCountsDto Counts { get; private set; } = new();

    public void SetCache(List<GateCardDto> cards, List<GateEmployeeDto> employees)
    {
        lock (_lock)
        {
            Cards = cards;
            Employees = employees;
        }
        Notify();
    }

    public void SetCounts(GateCountsDto counts)
    {
        Counts = counts;
        Notify();
    }

    public void MarkOnline(DateTime? syncedAt = null)
    {
        IsOnline = true;
        LastError = null;
        if (syncedAt.HasValue) LastSyncAt = syncedAt;
        Notify();
    }

    public void MarkOffline(string? error)
    {
        IsOnline = false;
        LastError = error;
        Notify();
    }

    public void SetPendingCount(int count)
    {
        PendingTapCount = count;
        Notify();
    }

    public void SetClockDrift(double seconds, int warningThresholdSeconds)
    {
        ClockDriftSeconds = seconds;
        ClockDriftWarning = Math.Abs(seconds) > warningThresholdSeconds;
        Notify();
    }

    // Kartu dicari dari cache HANYA untuk menampilkan nama saat offline dan untuk mengenali
    // kartu satpam (is_gate_operator). Tidak pernah untuk menentukan masuk/pulang.
    public GateCardDto? FindCard(string cardUid)
    {
        var snapshot = Cards;
        return snapshot.FirstOrDefault(c => c.CardUid == cardUid);
    }

    private void Notify() => OnChanged?.Invoke();
}

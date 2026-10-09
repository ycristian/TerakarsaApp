using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.GateApp.Services;

// Prompt 70: kirim antrian tap tiap QueueFlushSeconds, BERURUTAN menurut tapped_at.
// Sukses -> baris ditandai sent. Gagal -> biarkan, coba lagi siklus berikutnya. Tidak pernah
// crash dan tidak pernah membuang baris antrian: baris yang hilang = absensi orang yang hilang.
public class TapQueueService : BackgroundService
{
    private const int BatchSize = 50;

    private readonly GateApiClient _api;
    private readonly GateLocalDb _db;
    private readonly GateState _state;
    private readonly GateWorkerOptions _options;
    private readonly ILogger<TapQueueService> _logger;

    private DateTime _lastPurgeAt = DateTime.MinValue;

    public TapQueueService(GateApiClient api, GateLocalDb db, GateState state,
        IOptions<GateWorkerOptions> options, ILogger<TapQueueService> logger)
    {
        _api = api;
        _db = db;
        _state = state;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            await FlushOnceAsync(stoppingToken);

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(Math.Max(3, _options.QueueFlushSeconds)), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    // Dipakai juga oleh tombol "sync paksa" di menu satpam.
    public async Task FlushOnceAsync(CancellationToken ct)
    {
        try
        {
            if (DateTime.Now - _lastPurgeAt > TimeSpan.FromHours(6))
            {
                _db.PurgeSentOlderThan(TimeSpan.FromDays(7));
                _lastPurgeAt = DateTime.Now;
            }

            var pending = _db.GetPendingTaps(BatchSize);
            _state.SetPendingCount(_db.GetPendingCount());
            if (pending.Count == 0) return;

            // Semua tap yang dikirim dari antrian adalah replay offline: server memakai ini untuk
            // memutuskan sendiri sesi panjang (layar konfirmasi tidak mungkin muncul saat offline).
            var requests = pending
                .Select(t => new GateTapRequest
                {
                    TapUid = t.TapUid,
                    CardUid = t.CardUid,
                    TappedAt = t.TappedAt,
                    ConfirmAction = t.ConfirmAction,
                    IsOfflineReplay = true,
                })
                .ToList();

            var results = await _api.PostTapsAsync(_options.GateCode, requests, ct);
            _state.MarkOnline();

            // Urutan response = urutan request (dijamin GateController). Baris yang dijawab
            // "GAGAL" sengaja TIDAK ditandai sent supaya dicoba lagi siklus berikutnya.
            for (var i = 0; i < requests.Count; i++)
            {
                var failed = i < results.Count && string.Equals(results[i].ResultCode, "GAGAL", StringComparison.Ordinal);
                if (failed)
                {
                    _logger.LogWarning("Tap {TapUid} ditolak server: {Message}", requests[i].TapUid, results[i].Message);
                    continue;
                }
                _db.MarkSent(requests[i].TapUid);
            }

            _state.SetPendingCount(_db.GetPendingCount());

            // Replay offline baru saja membuka/menutup sesi di server: segarkan angka layar
            // tunggu. Gagal di sini tidak berarti tap-nya gagal -- angka lama tetap tampil.
            try
            {
                _state.SetCounts(await _api.GetCountsAsync(_options.GateCode, ct));
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogWarning(ex, "Gagal memperbarui angka layar tunggu setelah kirim antrian.");
            }
        }
        catch (OperationCanceledException)
        {
            // shutdown
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Pengiriman antrian tap gagal, dicoba lagi siklus berikutnya.");
            _state.MarkOffline(ex.Message);
        }
    }
}

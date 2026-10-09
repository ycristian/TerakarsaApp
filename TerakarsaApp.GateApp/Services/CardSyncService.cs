using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace TerakarsaApp.GateApp.Services;

// Prompt 70: tarik master kartu + master karyawan tiap CardSyncSeconds, dan sekalian bandingkan
// jam server dengan jam lokal tablet.
//
// TIDAK PERNAH crash: kalau server mati, cache lama tetap dipakai dan indikator jadi offline.
// Cache yang basi jauh lebih baik daripada aplikasi gate yang berhenti -- tap tetap harus masuk
// antrian walau namanya tidak bisa ditampilkan.
public class CardSyncService : BackgroundService
{
    private readonly GateApiClient _api;
    private readonly GateLocalDb _db;
    private readonly GateState _state;
    private readonly GateWorkerOptions _options;
    private readonly ILogger<CardSyncService> _logger;

    public CardSyncService(GateApiClient api, GateLocalDb db, GateState state,
        IOptions<GateWorkerOptions> options, ILogger<CardSyncService> logger)
    {
        _api = api;
        _db = db;
        _state = state;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Cache lokal dimuat lebih dulu supaya layar sudah bisa menampilkan nama sebelum sync
        // pertama selesai (mis. tablet dinyalakan saat jaringan masih down).
        LoadFromCache();
        _state.SetPendingCount(_db.GetPendingCount());

        while (!stoppingToken.IsCancellationRequested)
        {
            await SyncOnceAsync(stoppingToken);

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(Math.Max(10, _options.CardSyncSeconds)), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    // Dipakai juga oleh tombol "sync paksa" di menu satpam.
    public async Task SyncOnceAsync(CancellationToken ct)
    {
        try
        {
            var localBefore = DateTime.Now;
            var sync = await _api.GetCardSyncAsync(ct);

            _db.ReplaceCache(sync);
            LoadFromCache();

            // Jam server dibandingkan dengan titik tengah request supaya latensi jaringan tidak
            // dihitung sebagai selisih jam.
            var localMid = localBefore.AddTicks((DateTime.Now - localBefore).Ticks / 2);
            _state.SetClockDrift((localMid - sync.ServerTime).TotalSeconds, _options.ClockDriftWarningSeconds);

            var counts = await _api.GetCountsAsync(_options.GateCode, ct);
            _state.SetCounts(counts);

            _state.MarkOnline(DateTime.Now);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Sinkronisasi kartu gagal, cache lama tetap dipakai.");
            _state.MarkOffline(ex.Message);
        }
    }

    // Hanya tiga angka layar tunggu (Hadir / Belum ambil / Perlu cek), dipanggil setelah setiap
    // tap yang diproses server -- tanpa ini angkanya baru berubah di sync berikutnya (default
    // 5 menit). Gagal = angka lama tetap tampil; status online/offline TIDAK diubah di sini,
    // itu urusan pengiriman tap dan sync kartu.
    public async Task RefreshCountsAsync(CancellationToken ct)
    {
        try
        {
            _state.SetCounts(await _api.GetCountsAsync(_options.GateCode, ct));
        }
        catch (OperationCanceledException)
        {
            // shutdown
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Gagal memperbarui angka layar tunggu.");
        }
    }

    private void LoadFromCache()
    {
        try
        {
            _state.SetCache(_db.GetCards(), _db.GetEmployees());
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Cache gate.db tidak terbaca.");
        }
    }
}

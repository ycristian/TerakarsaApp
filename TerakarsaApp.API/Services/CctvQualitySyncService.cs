using System.Collections.Concurrent;
using Microsoft.Extensions.Options;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Services;

// Prompt 97: sinkron kualitas rekaman (cctv.cameras.record_quality) ke source path MediaMTX.
// Database = sumber kebenaran; perubahan lewat API MediaMTX hanya di memori MediaMTX (hilang saat
// MediaMTX restart), karena itu dicek ulang berkala oleh CctvQualitySyncHostedService.
//
// Singleton: menyimpan status sinkron per path (memori, tidak ke DB) dan mengatur log supaya
// tidak membanjiri: satu peringatan saat MediaMTX mulai tak terjangkau, satu info saat kembali,
// dan peringatan per path hanya saat statusnya berubah.
//
// URL source (berisi user & kode RTSP) hanya dipegang di variabel lokal selama baca -> tukar -> PATCH;
// tidak pernah disimpan di field, di-log (kecuali disamarkan), atau dikirim ke browser.
public class CctvQualitySync
{
    private readonly ConcurrentDictionary<string, string> _status = new(StringComparer.OrdinalIgnoreCase);
    // Satu penerapan dalam satu waktu: simpan Edit Kamera & tick background tidak PATCH bersamaan
    // (yang kedua akan membaca source yang sudah benar -> tidak PATCH ulang).
    private readonly SemaphoreSlim _lock = new(1, 1);
    private readonly ILogger<CctvQualitySync> _logger;
    private bool _mtxDown;

    public CctvQualitySync(ILogger<CctvQualitySync> logger)
    {
        _logger = logger;
    }

    public bool IsMtxDown => _mtxDown;

    public string? GetStatus(string mtxPath) => _status.TryGetValue(mtxPath, out var s) ? s : null;

    // Buang status path yang sudah tidak terdaftar / dihapus.
    public void Retain(IEnumerable<string> mtxPaths)
    {
        var keep = new HashSet<string>(mtxPaths, StringComparer.OrdinalIgnoreCase);
        foreach (var key in _status.Keys.Where(k => !keep.Contains(k)).ToList())
            _status.TryRemove(key, out _);
    }

    // MediaMTX diketahui tak terjangkau di tick ini -- tandai tanpa memanggil API lagi.
    public void MarkUnreachable(string mtxPath, string quality) => SetStatus(mtxPath, StatusSaatMtxMati(quality));

    // Baca source -> bandingkan -> PATCH hanya kalau berbeda. Tidak pernah melempar kecuali dibatalkan.
    public async Task<string?> ApplyAsync(CctvMediaMtxClient mtx, string mtxPath, string quality, CancellationToken ct)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var status = await ApplyCoreAsync(mtx, mtxPath, quality, ct);
            SetStatus(mtxPath, status);
            return status;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Pesan exception HttpClient hanya berisi URL API MediaMTX (tanpa source), tetapi tetap
            // cukup tipe exception supaya aman.
            _logger.LogWarning("Sinkron kualitas path {Path} gagal ({Jenis}).", mtxPath, ex.GetType().Name);
            SetStatus(mtxPath, CctvQualitySyncStatus.Menunggu);
            return CctvQualitySyncStatus.Menunggu;
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task<string?> ApplyCoreAsync(CctvMediaMtxClient mtx, string mtxPath, string quality, CancellationToken ct)
    {
        var get = await mtx.GetPathSourceAsync(mtxPath, ct);
        switch (get.Outcome)
        {
            case CctvMtxCallOutcome.Unreachable:
                TandaiMati();
                return StatusSaatMtxMati(quality);
            case CctvMtxCallOutcome.NotFound:
                TandaiHidup();
                if (GetStatus(mtxPath) != CctvQualitySyncStatus.PathTidakAda)
                    _logger.LogWarning("Path {Path} tidak ada di konfigurasi MediaMTX — kualitas rekaman tidak diterapkan.", mtxPath);
                return CctvQualitySyncStatus.PathTidakAda;
            case CctvMtxCallOutcome.Failed:
                TandaiHidup();
                if (GetStatus(mtxPath) != CctvQualitySyncStatus.Menunggu)
                    _logger.LogWarning("MediaMTX menolak membaca konfigurasi path {Path} (HTTP {Status}).", mtxPath, get.StatusCode);
                return CctvQualitySyncStatus.Menunggu;
        }

        TandaiHidup();
        var swap = CctvMediaMtxClient.SwapQuality(get.Source, quality);
        if (!swap.Supported)
        {
            if (GetStatus(mtxPath) != CctvQualitySyncStatus.TidakDidukung)
                _logger.LogWarning("Source path {Path} tidak berpola .../Streaming/Channels/<ch><01|02> ({Source}) — kualitas tidak diubah.",
                    mtxPath, CctvMediaMtxClient.MaskCredentials(get.Source));
            return CctvQualitySyncStatus.TidakDidukung;
        }

        // Sudah sama -> JANGAN PATCH (PATCH memutus sambungan kamera beberapa detik).
        if (swap.CurrentQuality == quality) return CctvQualitySyncStatus.Sesuai;

        var patch = await mtx.PatchPathSourceAsync(mtxPath, swap.Source!, ct);
        switch (patch)
        {
            case CctvMtxCallOutcome.Ok:
                _logger.LogInformation("Kualitas rekaman path {Path} diganti {Dari} -> {Ke}.", mtxPath, swap.CurrentQuality, quality);
                return CctvQualitySyncStatus.Sesuai;
            case CctvMtxCallOutcome.Unreachable:
                TandaiMati();
                return CctvQualitySyncStatus.Menunggu;
            case CctvMtxCallOutcome.NotFound:
                return CctvQualitySyncStatus.PathTidakAda;
            default:
                if (GetStatus(mtxPath) != CctvQualitySyncStatus.Menunggu)
                    _logger.LogWarning("MediaMTX menolak mengubah source path {Path}.", mtxPath);
                return CctvQualitySyncStatus.Menunggu;
        }
    }

    // MediaMTX mati: saat menyala lagi semua path kembali ke mediamtx.yml (= sub). Kamera MAIN pasti
    // menunggu sinkron; kamera SUB akan sesuai sendiri -> status tidak diketahui (tanpa penanda).
    private static string? StatusSaatMtxMati(string quality) =>
        quality == CctvRecordQuality.Main ? CctvQualitySyncStatus.Menunggu : null;

    private void SetStatus(string mtxPath, string? status)
    {
        if (status is null) _status.TryRemove(mtxPath, out _);
        else _status[mtxPath] = status;
    }

    private void TandaiMati()
    {
        if (_mtxDown) return;
        _mtxDown = true;
        _logger.LogWarning("MediaMTX API tidak terjangkau — sinkron kualitas rekaman ditunda sampai tersambung kembali.");
    }

    private void TandaiHidup()
    {
        if (!_mtxDown) return;
        _mtxDown = false;
        _logger.LogInformation("MediaMTX API tersambung kembali — sinkron kualitas rekaman dilanjutkan.");
    }
}

// Prompt 97: tiap Cctv:QualitySyncSeconds (default 30) cocokkan source path semua kamera hidup
// di cctv.cameras dengan record_quality, dua arah. Path MediaMTX yang tidak terdaftar tidak disentuh.
public class CctvQualitySyncHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopes;
    private readonly CctvQualitySync _sync;
    private readonly CctvOptions _options;
    private readonly ILogger<CctvQualitySyncHostedService> _logger;
    private bool _dbErrorLogged;

    public CctvQualitySyncHostedService(IServiceScopeFactory scopes, CctvQualitySync sync,
        IOptions<CctvOptions> options, ILogger<CctvQualitySyncHostedService> logger)
    {
        _scopes = scopes;
        _sync = sync;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromSeconds(Math.Max(5, _options.QualitySyncSeconds));

        // Beri waktu API selesai start.
        try { await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken); }
        catch (OperationCanceledException) { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await TickAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                // Mis. database tidak terjangkau -- satu peringatan sampai pulih.
                if (!_dbErrorLogged)
                {
                    _dbErrorLogged = true;
                    _logger.LogWarning("Sinkron kualitas rekaman gagal membaca daftar kamera ({Jenis}: {Pesan}).",
                        ex.GetType().Name, ex.Message);
                }
            }

            try { await Task.Delay(interval, stoppingToken); }
            catch (OperationCanceledException) { return; }
        }
    }

    private async Task TickAsync(CancellationToken ct)
    {
        using var scope = _scopes.CreateScope();
        var cameras = await scope.ServiceProvider.GetRequiredService<CctvCameraService>().GetQualityTargetsAsync(ct);
        var mtx = scope.ServiceProvider.GetRequiredService<CctvMediaMtxClient>();

        if (_dbErrorLogged)
        {
            _dbErrorLogged = false;
            _logger.LogInformation("Sinkron kualitas rekaman: daftar kamera terbaca kembali.");
        }

        _sync.Retain(cameras.Select(c => c.MtxPath));

        var mtxMatiDiTickIni = false;
        foreach (var (path, quality) in cameras)
        {
            // Sekali tak terjangkau di tick ini, sisanya ditandai tanpa menunggu timeout per kamera.
            if (mtxMatiDiTickIni)
            {
                _sync.MarkUnreachable(path, quality);
                continue;
            }

            await _sync.ApplyAsync(mtx, path, quality, ct);
            mtxMatiDiTickIni = _sync.IsMtxDown;
        }
    }
}

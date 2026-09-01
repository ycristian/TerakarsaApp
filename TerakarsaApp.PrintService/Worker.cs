using Microsoft.Extensions.Options;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly PrintApiClient _apiClient;
    private readonly DailyFileLogger _fileLogger;
    private readonly PrintWorkerOptions _options;

    public Worker(ILogger<Worker> logger, PrintApiClient apiClient, DailyFileLogger fileLogger, IOptions<PrintWorkerOptions> options)
    {
        _logger = logger;
        _apiClient = apiClient;
        _fileLogger = fileLogger;
        _options = options.Value;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        Log(LogLevel.Information,
            $"TerakarsaApp.PrintService dimulai. DryRun={_options.DryRun}, PrinterLabelOn={_options.PrinterLabelOn}, PrinterThermalOn={_options.PrinterThermalOn}, " +
            $"ApiBaseUrl={_options.ApiBaseUrl}, PollSeconds={_options.PollSeconds}, BatchSize={_options.BatchSize}");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await PollOnceAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                // API tidak terjangkau atau error tak terduga saat klaim -- jangan crash,
                // coba lagi siklus berikutnya.
                Log(LogLevel.Warning, $"Gagal polling API: {ex.Message}");
            }

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(Math.Max(1, _options.PollSeconds)), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                // service sedang berhenti, keluar dari loop secara normal
            }
        }
    }

    private static readonly string[] LabelJobTypes = { "BUNDLE_LABEL", "PACK_LABEL", "REJECT_NOTE" };
    private static readonly string[] KuponJobTypes = { "KUPON_BORONGAN", "REKAP_PRODUKSI", "REKAP_KARYAWAN", "REKAP_WIP" };

    private async Task PollOnceAsync(CancellationToken ct)
    {
        var enabledJobTypes = new List<string>();
        if (_options.PrinterLabelOn) enabledJobTypes.AddRange(LabelJobTypes);
        if (_options.PrinterThermalOn) enabledJobTypes.AddRange(KuponJobTypes);

        // Semua printer off -- jangan panggil API sama sekali, tidak ada yang boleh diklaim.
        if (enabledJobTypes.Count == 0) return;

        var jobs = await _apiClient.ClaimAsync(Math.Max(1, _options.BatchSize), enabledJobTypes, _options.DryRun, ct);
        if (jobs.Count == 0) return;

        Log(LogLevel.Information, $"Klaim {jobs.Count} job cetak.");

        foreach (var job in jobs)
        {
            // Kegagalan satu job tidak boleh menghentikan job lain di batch ini.
            try
            {
                await ProcessJobAsync(job, ct);
            }
            catch (Exception ex)
            {
                Log(LogLevel.Error, $"Job #{job.PrintJobId}: error tak terduga - {ex.Message}");
                await ReportSafeAsync(job.PrintJobId, false, ex.Message, ct);
            }
        }
    }

    // Prompt 48: dispatch berdasar RenderMode hasil klaim (bukan job_type langsung) --
    // SIS_PrintJob_Claim hanya pernah mengembalikan job yang printer tujuannya sudah pasti
    // (job_type tanpa route hidup, atau device is_active = 0, tidak pernah ikut diklaim sama
    // sekali -- tetap PENDING). RenderMode 'RAW_TSPL' = jalur label lama (TsplBuilder,
    // TIDAK berubah); 'TOKEN' = render lewat SP (SIS_Print_Dispatch) + EscPosRenderer.
    private async Task ProcessJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        if (job.RenderMode == "RAW_TSPL")
        {
            await ProcessTsplJobAsync(job, ct);
            return;
        }
        if (job.RenderMode == "TOKEN")
        {
            await ProcessTokenJobAsync(job, ct);
            return;
        }

        Log(LogLevel.Warning, $"Job #{job.PrintJobId}: render_mode '{job.RenderMode}' tidak dikenal.");
        await ReportSafeAsync(job.PrintJobId, false, "Render mode tidak dikenal.", ct);
    }

    // Jalur label TSC TTP-244 Pro -- TIDAK diubah (payload BUNDLE_LABEL, TsplBuilder, dst tetap
    // persis). Satu-satunya perbedaan dari sebelum Prompt 48: printer diambil dari job.PrinterName
    // (hasil resolusi print_devices saat klaim), bukan _options.PrinterName di appsettings.
    private async Task ProcessTsplJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        if (job.JobType != "BUNDLE_LABEL" && job.JobType != "PACK_LABEL" && job.JobType != "REJECT_NOTE")
        {
            Log(LogLevel.Warning, $"Job #{job.PrintJobId}: job_type '{job.JobType}' belum didukung di jalur RAW_TSPL.");
            await ReportSafeAsync(job.PrintJobId, false, "Job type belum didukung.", ct);
            return;
        }

        byte[] tspl;
        string serial;
        try
        {
            if (job.JobType == "PACK_LABEL")
            {
                var packPayload = TsplBuilder.ParsePackLabelPayload(job.Payload);
                serial = packPayload.Serial;
                tspl = TsplBuilder.BuildPackLabel(packPayload);
            }
            else if (job.JobType == "REJECT_NOTE")
            {
                var rejectPayload = TsplBuilder.ParseRejectNotePayload(job.Payload);
                serial = rejectPayload.BundleSerial ?? $"WL#{rejectPayload.WorkflowLogId}";
                tspl = TsplBuilder.BuildRejectNote(rejectPayload);
            }
            else
            {
                var bundlePayload = TsplBuilder.ParseBundleLabelPayload(job.Payload);
                serial = bundlePayload.Serial;
                tspl = TsplBuilder.BuildBundleLabel(bundlePayload);
            }
        }
        catch (Exception ex)
        {
            Log(LogLevel.Error, $"Job #{job.PrintJobId}: payload rusak - {ex.Message}");
            await ReportSafeAsync(job.PrintJobId, false, $"Payload rusak: {ex.Message}", ct);
            return;
        }

        try
        {
            if (_options.DryRun)
            {
                var dryRunDir = Path.Combine(AppContext.BaseDirectory, "dryrun");
                Directory.CreateDirectory(dryRunDir);
                var path = Path.Combine(dryRunDir, $"{job.PrintJobId}.tspl");
                await File.WriteAllBytesAsync(path, tspl, ct);
                Log(LogLevel.Information, $"Job #{job.PrintJobId} (DryRun) serial {serial}: TSPL ditulis ke {path}");
            }
            else
            {
                RawPrinterHelper.SendBytesToPrinter(job.PrinterName, tspl);
                Log(LogLevel.Information, $"Job #{job.PrintJobId} serial {serial}: dicetak ke printer '{job.PrinterName}'.");
            }

            await ReportSafeAsync(job.PrintJobId, true, null, ct);
        }
        catch (Exception ex)
        {
            Log(LogLevel.Error, $"Job #{job.PrintJobId}: gagal cetak - {ex.Message}");
            await ReportSafeAsync(job.PrintJobId, false, ex.Message, ct);
        }
    }

    // Prompt 48: render dilakukan SAAT job diklaim (bukan saat job dibuat) -- panggil
    // api/print/render/{id} (SIS_Print_Dispatch), terjemahkan token -> byte ESC/POS lewat
    // EscPosRenderer, kirim ke printer job ini (job.PrinterName, hasil resolusi print_devices).
    // Kegagalan render (SP error / endpoint 400) dilaporkan lewat api/print/report dengan pesan
    // aslinya, sama seperti kegagalan cetak biasa.
    private async Task ProcessTokenJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        string tokenText;
        try
        {
            tokenText = await _apiClient.RenderAsync(job.PrintJobId, _options.DryRun, ct);
        }
        catch (Exception ex)
        {
            Log(LogLevel.Error, $"Job #{job.PrintJobId}: gagal render - {ex.Message}");
            await ReportSafeAsync(job.PrintJobId, false, ex.Message, ct);
            return;
        }

        var rendered = EscPosRenderer.Render(tokenText, job.CharsPerLine, job.CharsPerLineSmall);
        foreach (var warning in rendered.Warnings)
            Log(LogLevel.Warning, $"Job #{job.PrintJobId}: {warning}");

        // KUPON_BORONGAN dicetak rangkap (KuponBoronganCopies, default 2, pola sama dengan
        // sebelum Prompt 48); job_type TOKEN lain 1x.
        var copies = job.JobType == "KUPON_BORONGAN" ? Math.Max(1, _options.KuponBoronganCopies) : 1;

        try
        {
            if (_options.DryRun)
            {
                var dryRunDir = Path.Combine(AppContext.BaseDirectory, "dryrun");
                Directory.CreateDirectory(dryRunDir);
                var escposPath = Path.Combine(dryRunDir, $"{job.PrintJobId}.escpos");
                var txtPath = Path.Combine(dryRunDir, $"{job.PrintJobId}.txt");
                await File.WriteAllBytesAsync(escposPath, rendered.Bytes, ct);
                await File.WriteAllTextAsync(txtPath, rendered.PlainText, ct);
                Log(LogLevel.Information, $"Job #{job.PrintJobId} (DryRun): ESC/POS ditulis ke {escposPath} dan {txtPath} ({copies}x)");
            }
            else
            {
                for (var i = 0; i < copies; i++)
                {
                    RawPrinterHelper.SendBytesToPrinter(job.PrinterName, rendered.Bytes);
                }
                Log(LogLevel.Information, $"Job #{job.PrintJobId}: dicetak {copies}x ke printer '{job.PrinterName}'.");
            }

            await ReportSafeAsync(job.PrintJobId, true, null, ct);
        }
        catch (Exception ex)
        {
            Log(LogLevel.Error, $"Job #{job.PrintJobId}: gagal cetak - {ex.Message}");
            await ReportSafeAsync(job.PrintJobId, false, ex.Message, ct);
        }
    }

    private async Task ReportSafeAsync(int printJobId, bool success, string? errorMessage, CancellationToken ct)
    {
        try
        {
            await _apiClient.ReportAsync(printJobId, success, errorMessage, _options.DryRun, ct);
        }
        catch (Exception ex)
        {
            Log(LogLevel.Warning, $"Job #{printJobId}: gagal lapor hasil ke API - {ex.Message}");
        }
    }

    private void Log(LogLevel level, string message)
    {
        _logger.Log(level, "{Message}", message);
        _fileLogger.Write($"[{level}] {message}");
    }
}

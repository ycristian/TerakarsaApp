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
            $"TerakarsaApp.PrintService dimulai. DryRun={_options.DryRun}, Printer='{_options.PrinterName}', ApiBaseUrl={_options.ApiBaseUrl}, PollSeconds={_options.PollSeconds}, BatchSize={_options.BatchSize}");

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

    private async Task PollOnceAsync(CancellationToken ct)
    {
        var jobs = await _apiClient.ClaimAsync(Math.Max(1, _options.BatchSize), ct);
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

    private async Task ProcessJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        if (job.JobType != "BUNDLE_LABEL" && job.JobType != "PACK_LABEL" && job.JobType != "REJECT_NOTE")
        {
            Log(LogLevel.Warning, $"Job #{job.PrintJobId}: job_type '{job.JobType}' belum didukung.");
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
                RawPrinterHelper.SendBytesToPrinter(_options.PrinterName, tspl);
                Log(LogLevel.Information, $"Job #{job.PrintJobId} serial {serial}: dicetak ke printer '{_options.PrinterName}'.");
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
            await _apiClient.ReportAsync(printJobId, success, errorMessage, ct);
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

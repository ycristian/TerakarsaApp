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
            $"Printer='{_options.PrinterName}', KuponPrinterName='{_options.KuponPrinterName}', ApiBaseUrl={_options.ApiBaseUrl}, PollSeconds={_options.PollSeconds}, BatchSize={_options.BatchSize}");

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

    private static readonly HashSet<string> KuponJobTypes = new() { "KUPON_BORONGAN", "REKAP_PRODUKSI" };

    private async Task ProcessJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        if (KuponJobTypes.Contains(job.JobType))
        {
            await ProcessKuponJobAsync(job, ct);
            return;
        }

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
            if (_options.DryRun || !_options.PrinterLabelOn)
            {
                var dryRunDir = Path.Combine(AppContext.BaseDirectory, "dryrun");
                Directory.CreateDirectory(dryRunDir);
                var path = Path.Combine(dryRunDir, $"{job.PrintJobId}.tspl");
                await File.WriteAllBytesAsync(path, tspl, ct);
                var reason = _options.DryRun ? "DryRun" : "PrinterLabelOn=false";
                Log(LogLevel.Information, $"Job #{job.PrintJobId} ({reason}) serial {serial}: TSPL ditulis ke {path}");
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

    // Prompt 41/42: KUPON_BORONGAN/REKAP_PRODUKSI -- printer struk ESC/POS terpisah (KuponPrinterName),
    // via RawPrinterHelper yang sama (raw bytes, tanpa driver/SDK khusus).
    private async Task ProcessKuponJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        byte[] escpos;
        string label;
        try
        {
            if (job.JobType == "REKAP_PRODUKSI")
            {
                var rekapPayload = EscPosBuilder.ParseRekapProduksiPayload(job.Payload);
                label = rekapPayload.EmployeeName ?? rekapPayload.ResourceName ?? rekapPayload.DivisionName;
                escpos = EscPosBuilder.BuildRekapProduksi(rekapPayload, _options.KuponPaperWidthChars);
            }
            else
            {
                var kuponPayload = EscPosBuilder.ParseKuponBoronganPayload(job.Payload);
                label = kuponPayload.Serial ?? $"WL#{kuponPayload.WorkflowLogId}";
                escpos = EscPosBuilder.BuildKuponBorongan(kuponPayload, _options.KuponPaperWidthChars);
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
            if (_options.DryRun || !_options.PrinterThermalOn)
            {
                var dryRunDir = Path.Combine(AppContext.BaseDirectory, "dryrun");
                Directory.CreateDirectory(dryRunDir);
                var path = Path.Combine(dryRunDir, $"{job.PrintJobId}.escpos");
                await File.WriteAllBytesAsync(path, escpos, ct);
                var reason = _options.DryRun ? "DryRun" : "PrinterThermalOn=false";
                Log(LogLevel.Information, $"Job #{job.PrintJobId} ({reason}) {label}: ESC/POS ditulis ke {path}");
            }
            else
            {
                if (string.IsNullOrWhiteSpace(_options.KuponPrinterName))
                    throw new InvalidOperationException("Printer kupon belum dikonfigurasi.");

                RawPrinterHelper.SendBytesToPrinter(_options.KuponPrinterName, escpos);
                Log(LogLevel.Information, $"Job #{job.PrintJobId} {label}: dicetak ke printer '{_options.KuponPrinterName}'.");
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

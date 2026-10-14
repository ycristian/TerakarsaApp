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

    // Job_type label (TSC TTP-244 Pro, TSPL) TETAP hardcode -- TsplBuilder.cs punya layout
    // spesifik per jenis label di C#, jadi job_type baru di sini SELALU butuh kode baru juga
    // (tidak ada untungnya dipindah ke DB).
    // Prompt 73: THREAD_SKU_LABEL & THREAD_SPLIT_LABEL = label benang 30x20 mm
    // (TsplBuilder.BuildThreadLabel).
    private static readonly string[] LabelJobTypes =
    {
        "BUNDLE_LABEL", "PACK_LABEL", "REJECT_NOTE",
        "THREAD_SKU_LABEL", "THREAD_SPLIT_LABEL"
    };

    // Prompt 65: job_type yang dirakit di C# sebagai ESC/POS (printer thermal 80mm),
    // BUKAN lewat token SP seperti job_type kupon -- jadi tidak didaftarkan di
    // print_kupon_job_types, dan ditangkap berdasarkan job_type sebelum switch
    // RenderMode di ProcessJobAsync. Printernya tetap diambil dari hasil klaim
    // (print_job_routes -> print_devices), jadi bisa dipindah dari DB.
    private static readonly string[] EscPosJobTypes = { "TNI_KARTU" };

    // Ad hoc (2026-09-01): job_type "kupon" (thermal, render_mode TOKEN) TIDAK LAGI hardcode di
    // sini -- render TOKEN generik (EscPosRenderer cuma nerjemahin token, tidak peduli
    // job_type-nya apa), jadi job_type struk baru cukup SP render + baris di
    // print_kupon_job_types (DB), TANPA update/republish/restart service ini. Diambil ULANG
    // setiap siklus poll lewat GetKuponJobTypesAsync (bukan cache sekali di startup) supaya
    // baris baru langsung kepakai.
    private async Task PollOnceAsync(CancellationToken ct)
    {
        var enabledJobTypes = new List<string>();
        if (_options.PrinterLabelOn) enabledJobTypes.AddRange(LabelJobTypes);
        if (_options.PrinterThermalOn)
        {
            enabledJobTypes.AddRange(await _apiClient.GetKuponJobTypesAsync(ct));
            enabledJobTypes.AddRange(EscPosJobTypes);
        }

        // Semua printer off -- jangan panggil API sama sekali, tidak ada yang boleh diklaim.
        if (enabledJobTypes.Count == 0) return;

        var batchSize = Math.Max(1, _options.BatchSize);

        // Prompt 65 -- PERCEPATAN: kalau satu klaim mengembalikan job sebanyak
        // BatchSize, antrian kemungkinan masih panjang (mis. cetak ratusan kartu
        // satuan sekaligus), jadi langsung klaim lagi tanpa menunggu PollSeconds.
        // Perilaku untuk antrian kosong/sebagian TIDAK berubah.
        // Dibatasi supaya satu siklus poll tidak berputar selamanya dan service
        // tetap bisa berhenti saat diminta.
        const int maxBatchesPerCycle = 50;

        for (var batch = 0; batch < maxBatchesPerCycle; batch++)
        {
            if (ct.IsCancellationRequested) return;

            var jobs = await _apiClient.ClaimAsync(batchSize, enabledJobTypes, _options.DryRun, ct);
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

            // Batch belum penuh -> antrian habis, kembali ke jeda polling normal.
            if (jobs.Count < batchSize) return;
        }
    }

    // Prompt 48: dispatch berdasar RenderMode hasil klaim (bukan job_type langsung) --
    // SIS_PrintJob_Claim hanya pernah mengembalikan job yang printer tujuannya sudah pasti
    // (job_type tanpa route hidup, atau device is_active = 0, tidak pernah ikut diklaim sama
    // sekali -- tetap PENDING). RenderMode 'RAW_TSPL' = jalur label lama (TsplBuilder,
    // TIDAK berubah); 'TOKEN' = render lewat SP (SIS_Print_Dispatch) + EscPosRenderer.
    private async Task ProcessJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        // Prompt 65: TNI_KARTU dirakit di C# (TniKartuEscPosBuilder), jadi ditangkap
        // di sini SEBELUM switch RenderMode -- printernya memang device THERMAL yang
        // render_mode-nya 'TOKEN' (dipakai kupon), tapi kartu ini tidak lewat jalur token.
        if (EscPosJobTypes.Contains(job.JobType))
        {
            await ProcessTniKartuJobAsync(job, ct);
            return;
        }

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
        if (!LabelJobTypes.Contains(job.JobType))
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
            // Prompt 73: label benang 30x20 mm -- satu payload untuk label SKU & split.
            else if (job.JobType is "THREAD_SKU_LABEL" or "THREAD_SPLIT_LABEL")
            {
                var threadPayload = TsplBuilder.ParseThreadLabelPayload(job.Payload);
                serial = threadPayload.ConeCode ?? threadPayload.SkuCode ?? threadPayload.Qr;
                tspl = TsplBuilder.BuildThreadLabel(threadPayload);
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

    // Prompt 65: kartu personel PDH TNI AD -- ESC/POS dirakit dari payload di C#.
    // DryRun menulis .escpos.bin (byte mentah) DAN .txt (pratinjau teks baris demi
    // baris) supaya layout bisa diperiksa tanpa printer fisik.
    private async Task ProcessTniKartuJobAsync(PrintJobClaimedDto job, CancellationToken ct)
    {
        TerakarsaApp.Shared.PrintJobs.TniKartuPayload payload;
        byte[] escpos;
        try
        {
            payload = TniKartuEscPosBuilder.ParsePayload(job.Payload);
            escpos = TniKartuEscPosBuilder.Build(payload);
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
                var binPath = Path.Combine(dryRunDir, $"{job.PrintJobId}.escpos.bin");
                var txtPath = Path.Combine(dryRunDir, $"{job.PrintJobId}.txt");
                await File.WriteAllBytesAsync(binPath, escpos, ct);
                await File.WriteAllTextAsync(txtPath, TniKartuEscPosBuilder.BuildPlainText(payload), ct);
                Log(LogLevel.Information,
                    $"Job #{job.PrintJobId} (DryRun) kartu {payload.KodeRef}: ditulis ke {binPath} dan {txtPath}");
            }
            else
            {
                RawPrinterHelper.SendBytesToPrinter(job.PrinterName, escpos);
                Log(LogLevel.Information,
                    $"Job #{job.PrintJobId} kartu {payload.KodeRef}: dicetak ke printer '{job.PrinterName}'.");
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

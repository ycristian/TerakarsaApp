using Android.App;
using Android.Content;
using Android.OS;
using TerakarsaApp.Mobile.Services;
using TerakarsaApp.Printing;
using TerakarsaApp.Shared.PrintJobs;
using AndroidApp = Android.App.Application;

namespace TerakarsaApp.Mobile.Platforms.Android;

// Prompt 77: worker cetak di HP. Foreground service supaya Android tidak membunuhnya
// saat layar mati -- notifikasi tetap "Terakarsa Print Service aktif · <printer>".
//
// Loop: claim (api/print/claim dengan X-Print-Device-Token) -> rakit TSPL lewat
// TsplBuilder (library bersama dengan PrintService Windows, jadi layout label persis
// sama) -> kirim lewat Bluetooth SPP -> report.
//
// Poll 3 detik; melambat jadi 10 detik kalau layar sudah mati >= 5 menit (hemat
// baterai, label tidak pernah dicetak saat HP di kantong).
[Service(Exported = false, ForegroundServiceType = global::Android.Content.PM.ForegroundService.TypeConnectedDevice)]
public class PrintForegroundService : Service
{
    public const string ChannelId = "terakarsa_print";
    private const int NotifId = 7701;

    private static readonly TimeSpan LayarMatiLama = TimeSpan.FromMinutes(5);

    private CancellationTokenSource? _cts;
    private BluetoothPrinter? _printer;
    private DateTime? _layarMatiSejak;

    public static bool Berjalan { get; private set; }

    public static void Mulai()
    {
        var ctx = AndroidApp.Context;
        var intent = new Intent(ctx, typeof(PrintForegroundService));

        if (OperatingSystem.IsAndroidVersionAtLeast(26)) ctx.StartForegroundService(intent);
        else ctx.StartService(intent);
    }

    public static void Berhenti()
    {
        var ctx = AndroidApp.Context;
        ctx.StopService(new Intent(ctx, typeof(PrintForegroundService)));
    }

    public override IBinder? OnBind(Intent? intent) => null;

    public override StartCommandResult OnStartCommand(Intent? intent, StartCommandFlags flags, int startId)
    {
        if (Berjalan) return StartCommandResult.Sticky;

        Berjalan = true;
        BuatChannel();
        StartForeground(NotifId, BuatNotifikasi());

        _cts = new CancellationTokenSource();
        _printer = new BluetoothPrinter();

        PrintLog.Tulis("Print service aktif.");
        _ = Task.Run(() => LoopAsync(_cts.Token));

        return StartCommandResult.Sticky;
    }

    public override void OnDestroy()
    {
        Berjalan = false;
        _cts?.Cancel();
        _printer?.Dispose();
        _printer = null;

        PrintLog.Tulis("Print service berhenti.");
        base.OnDestroy();
    }

    private async Task LoopAsync(CancellationToken ct)
    {
        var services = IPlatformApplication.Current?.Services;
        if (services is null)
        {
            PrintLog.Tulis("Service tidak bisa mengakses konfigurasi app.");
            return;
        }

        var resolver = services.GetService(typeof(ServerResolver)) as ServerResolver;
        var queue = services.GetService(typeof(PrintQueueClient)) as PrintQueueClient;

        if (resolver is null || queue is null)
        {
            PrintLog.Tulis("Service tidak bisa mengakses konfigurasi app.");
            return;
        }

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var token = await PrintPrefs.TokenAsync();

                if (string.IsNullOrWhiteSpace(token))
                {
                    PrintLog.Tulis("HP ini belum terdaftar sebagai device cetak.");
                    PrintPrefs.Aktif = false;
                    Berhenti();
                    return;
                }

                var jobs = await queue.ClaimAsync(token!);

                if (queue.TokenDitolak)
                {
                    PrintLog.Tulis("Token device ditolak server — daftarkan ulang HP ini.");
                    PrintPrefs.Aktif = false;
                    Berhenti();
                    return;
                }

                foreach (var job in jobs)
                {
                    if (ct.IsCancellationRequested) break;
                    await KerjakanAsync(queue, token!, job);
                }

                if (jobs.Count == 0) _printer?.TutupKalauIdle();
            }
            catch (Exception ex)
            {
                PrintLog.Tulis($"Kesalahan loop: {ex.Message}");
            }

            await Task.Delay(TimeSpan.FromSeconds(JedaDetik()), ct).ContinueWith(_ => { }, CancellationToken.None);
        }
    }

    private async Task KerjakanAsync(PrintQueueClient queue, string token, PrintJobClaimedDto job)
    {
        byte[] tspl;

        try
        {
            tspl = Rakit(job);
        }
        catch (Exception ex)
        {
            PrintLog.Tulis($"Job #{job.PrintJobId} {job.JobType}: payload tidak dikenal — {ex.Message}");
            await queue.ReportAsync(token, job.PrintJobId, false, $"Payload tidak dikenal: {ex.Message}");
            return;
        }

        var (ok, error) = _printer?.Kirim(tspl) ?? (false, "Printer belum siap.");

        if (ok)
        {
            PrintLog.Tulis($"Job #{job.PrintJobId} {job.JobType}: tercetak.");
            await queue.ReportAsync(token, job.PrintJobId, true, null);
        }
        else
        {
            PrintLog.Tulis($"Job #{job.PrintJobId} {job.JobType}: GAGAL — {error}");
            await queue.ReportAsync(token, job.PrintJobId, false, error);
        }
    }

    // Layout label dirakit library BERSAMA dengan PrintService Windows -- label dari HP
    // dan dari PC identik byte per byte.
    private static byte[] Rakit(PrintJobClaimedDto job) => job.JobType switch
    {
        "THREAD_SKU_LABEL" or "THREAD_SPLIT_LABEL" =>
            TsplBuilder.BuildThreadLabel(TsplBuilder.ParseThreadLabelPayload(job.Payload)),
        "BUNDLE_LABEL" =>
            TsplBuilder.BuildBundleLabel(TsplBuilder.ParseBundleLabelPayload(job.Payload)),
        "PACK_LABEL" =>
            TsplBuilder.BuildPackLabel(TsplBuilder.ParsePackLabelPayload(job.Payload)),
        "REJECT_NOTE" =>
            TsplBuilder.BuildRejectNote(TsplBuilder.ParseRejectNotePayload(job.Payload)),
        _ => throw new NotSupportedException($"job_type {job.JobType} tidak didukung app HP.")
    };

    private int JedaDetik()
    {
        try
        {
            var pm = (PowerManager?)GetSystemService(PowerService);
            var nyala = pm?.IsInteractive ?? true;

            if (nyala)
            {
                _layarMatiSejak = null;
                return PrintPrefs.PollSeconds;
            }

            _layarMatiSejak ??= DateTime.Now;

            return DateTime.Now - _layarMatiSejak.Value >= LayarMatiLama ? 10 : PrintPrefs.PollSeconds;
        }
        catch (Exception)
        {
            return PrintPrefs.PollSeconds;
        }
    }

    private static void BuatChannel()
    {
        if (!OperatingSystem.IsAndroidVersionAtLeast(26)) return;

        var manager = (NotificationManager?)AndroidApp.Context.GetSystemService(NotificationService);
        if (manager is null) return;

        var channel = new NotificationChannel(ChannelId, "Terakarsa Print Service",
            NotificationImportance.Low)
        {
            Description = "Mengambil antrian cetak label dan mengirimnya ke printer Bluetooth."
        };

        manager.CreateNotificationChannel(channel);
    }

    private Notification BuatNotifikasi()
    {
        var printer = string.IsNullOrWhiteSpace(PrintPrefs.PrinterName) ? "printer belum dipilih" : PrintPrefs.PrinterName;

        var builder = new Notification.Builder(this, ChannelId)
            .SetContentTitle("Terakarsa Print Service aktif")
            .SetContentText($"· {printer}")
            .SetSmallIcon(global::Android.Resource.Drawable.StatNotifySync)
            .SetOngoing(true);

        return builder.Build();
    }
}

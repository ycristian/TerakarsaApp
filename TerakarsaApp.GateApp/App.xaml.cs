using System.IO;
using System.Windows;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using TerakarsaApp.GateApp.Services;

namespace TerakarsaApp.GateApp;

// Prompt 70: host DI + dua background service (CardSyncService, TapQueueService) dibangun di
// sini, lalu IServiceProvider yang SAMA diberikan ke BlazorWebView -- supaya UI dan background
// service melihat satu GateState dan satu gate.db.
public partial class App : Application
{
    private IHost? _host;

    public IServiceProvider Services => _host!.Services;

    protected override async void OnStartup(StartupEventArgs e)
    {
        // Pasang PALING AWAL. Aplikasi ini WinExe (tanpa console) dan OnStartup async void,
        // jadi exception apa pun -- termasuk saat window.Show() -- membuat proses mati DIAM-DIAM:
        // dotnet run langsung kembali ke prompt tanpa pesan, dan di tablet satpam cuma melihat
        // aplikasi "tidak mau buka". Tanpa log ini satu-satunya jejak ada di Event Viewer.
        DispatcherUnhandledException += (_, args) => ReportCrash(args.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            if (args.ExceptionObject is Exception ex) ReportCrash(ex);
        };

        base.OnStartup(e);

        var builder = Host.CreateApplicationBuilder();

        // appsettings.json ada di folder exe (bukan di working directory) -- aplikasi ini sering
        // dijalankan dari shortcut auto-start yang working directory-nya bisa apa saja.
        builder.Configuration.Sources.Clear();
        builder.Configuration
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: false, reloadOnChange: false);

        builder.Services.Configure<GateWorkerOptions>(builder.Configuration.GetSection("GateService"));

        builder.Services.AddHttpClient<GateApiClient>((sp, client) =>
        {
            var options = sp.GetRequiredService<IOptions<GateWorkerOptions>>().Value;
            if (!string.IsNullOrWhiteSpace(options.ApiBaseUrl))
                client.BaseAddress = new Uri(options.ApiBaseUrl);
            client.DefaultRequestHeaders.Add("X-Gate-Api-Key", options.ApiKey);
            // Tablet gate sering kehilangan jaringan: jangan menunggu lama, antrian lokal yang
            // menjaga datanya.
            client.Timeout = TimeSpan.FromSeconds(15);
        });

        builder.Services.AddSingleton<GateLocalDb>();
        builder.Services.AddSingleton<GateState>();
        builder.Services.AddSingleton<GateSoundPlayer>();

        // Di-register sebagai singleton DAN sebagai hosted service: layar "Status &
        // sinkronisasi" memanggil SyncOnceAsync/FlushOnceAsync milik instance yang sama
        // (tombol sync paksa), bukan membuat instance kedua.
        builder.Services.AddSingleton<CardSyncService>();
        builder.Services.AddSingleton<TapQueueService>();
        builder.Services.AddHostedService(sp => sp.GetRequiredService<CardSyncService>());
        builder.Services.AddHostedService(sp => sp.GetRequiredService<TapQueueService>());

        builder.Services.AddWpfBlazorWebView();
#if DEBUG
        builder.Services.AddBlazorWebViewDeveloperTools();
#endif

        _host = builder.Build();
        await _host.StartAsync();

        var window = new MainWindow(_host.Services);
        window.Show();
    }

    // gate-crash.log di folder exe (ditambah, tidak ditimpa) + MessageBox, supaya kegagalan
    // terlihat di layar dan bisa difoto/dikirim satpam. Tidak menelan exception-nya: setelah
    // pesan ditutup, aplikasi tetap mati seperti seharusnya -- melanjutkan dari keadaan yang
    // tidak diketahui bisa mencatat tap dengan salah.
    private static int _reported;

    private static void ReportCrash(Exception ex)
    {
        // DispatcherUnhandledException dan AppDomain.UnhandledException bisa sama-sama terpanggil
        // untuk satu crash; cukup laporkan sekali.
        if (Interlocked.Exchange(ref _reported, 1) == 1) return;

        var logPath = Path.Combine(AppContext.BaseDirectory, "gate-crash.log");
        try
        {
            File.AppendAllText(logPath,
                $"===== {DateTime.Now:yyyy-MM-dd HH:mm:ss} =====\r\n{ex}\r\n\r\n");
        }
        catch (Exception)
        {
            // folder exe tidak bisa ditulis: MessageBox di bawah tetap memberi tahu.
        }

        try
        {
            MessageBox.Show(
                $"Aplikasi gate berhenti karena error:\r\n\r\n{ex.GetBaseException().Message}\r\n\r\n" +
                $"Detail lengkap tersimpan di:\r\n{logPath}",
                "Gate TMOS", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        catch (Exception)
        {
            // tidak ada UI thread yang bisa dipakai: log di atas sudah cukup.
        }
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_host is not null)
        {
            await _host.StopAsync(TimeSpan.FromSeconds(3));
            _host.Dispose();
        }
        base.OnExit(e);
    }
}

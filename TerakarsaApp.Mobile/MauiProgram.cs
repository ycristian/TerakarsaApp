using Microsoft.Extensions.Logging;
using TerakarsaApp.Mobile.Services;
using ZXing.Net.Maui.Controls;

namespace TerakarsaApp.Mobile;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder
            .UseMauiApp<App>()
            // Prompt 86: pemindai QR kode login stasiun di Pengaturan (StationScanPage).
            .UseBarcodeReader()
            .ConfigureFonts(fonts =>
            {
                fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
                fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
            });

        builder.Services.AddSingleton<ServerResolver>();
        builder.Services.AddSingleton<MobileAuthService>();
        builder.Services.AddSingleton<PrintQueueClient>();

#if DEBUG
        builder.Logging.AddDebug();
#endif

        var app = builder.Build();

        // Prompt 76: mode Auto juga memeriksa ulang saat jaringan berubah
        // (keluar/masuk WiFi pabrik) -- halaman WebView mendengarkan
        // ServerResolver.Changed dan memuat ulang di origin baru.
        var resolver = app.Services.GetRequiredService<ServerResolver>();
        Connectivity.Current.ConnectivityChanged += async (_, _) => await resolver.RefreshAsync();

        return app;
    }
}

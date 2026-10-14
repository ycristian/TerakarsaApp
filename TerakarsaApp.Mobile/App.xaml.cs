using TerakarsaApp.Mobile.Pages;
using TerakarsaApp.Mobile.Services;

namespace TerakarsaApp.Mobile;

// Prompt 76: app Android "Terakarsa" -- pembungkus WebView untuk web TMOS.
public partial class App : Application
{
    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;

    public App(MobileAuthService auth, ServerResolver resolver)
    {
        InitializeComponent();

        _auth = auth;
        _resolver = resolver;
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
        var login = new LoginPage(_auth, _resolver);
        var window = new Window(new NavigationPage(login));

        // Mode Auto: alamat aktif diperiksa saat app start, saat jaringan berubah,
        // dan saat app kembali aktif (lihat MauiProgram + event di bawah).
        window.Created += async (_, _) => await MulaiAsync(login);
        window.Resumed += async (_, _) => await _resolver.RefreshAsync();

        return window;
    }

    private async Task MulaiAsync(LoginPage login)
    {
        await _resolver.RefreshAsync();
        await _auth.MuatTokenTersimpanAsync();

        if (!_auth.SudahLogin) return;

        // Token tersimpan: pastikan masih berlaku (daftar module sekaligus jadi
        // uji token). Kalau tidak, user tetap di layar login.
        if (!await _auth.MuatModuleAsync()) return;

        await login.Navigation.PushAsync(new TujuanPage(_auth, _resolver));
    }
}

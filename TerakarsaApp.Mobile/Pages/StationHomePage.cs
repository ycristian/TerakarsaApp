using TerakarsaApp.Mobile.Services;

namespace TerakarsaApp.Mobile.Pages;

// Prompt 86: layar root Mode Stasiun (menggantikan LoginPage + TujuanPage). Saat app dibuka
// langsung meneruskan ke WebView /station; operator kembali ke sini hanya lewat tombol back
// di root web. Login user (JWT) tidak dipakai sama sekali di mode ini.
public class StationHomePage : ContentPage
{
    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;

    private readonly Label _badge = new() { TextColor = Colors.White, FontSize = 12, FontAttributes = FontAttributes.Bold };
    private readonly Label _perangkat = Gaya.Keterangan(string.Empty);
    private readonly Label _kode = Gaya.Keterangan(string.Empty);

    private bool _sudahBukaOtomatis;

    public StationHomePage(MobileAuthService auth, ServerResolver resolver)
    {
        _auth = auth;
        _resolver = resolver;

        Title = "Mode Stasiun";
        BackgroundColor = Gaya.Latar;

        var buka = Gaya.Tombol("Buka Stasiun");
        buka.Clicked += async (_, _) => await BukaStasiunAsync();

        var admin = Gaya.Tombol("Masuk Admin", utama: false);
        admin.Clicked += async (_, _) => await MasukAdminAsync();

        var setting = Gaya.Tombol("Pengaturan", utama: false);
        setting.Clicked += async (_, _) =>
            await Navigation.PushAsync(new SettingPage(_auth, _resolver));

        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = new Thickness(24, 40),
                Spacing = 14,
                Children =
                {
                    Gaya.Judul("Mode Stasiun"),
                    Gaya.Badge(_badge, Gaya.Aksen),
                    _perangkat,
                    _kode,
                    new BoxView { HeightRequest = 6, Color = Colors.Transparent },
                    buka,
                    admin,
                    setting,
                    Gaya.Keterangan("Untuk keluar dari Mode Stasiun: Pengaturan → matikan Mode Stasiun → Simpan.")
                }
            }
        };
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();

        _perangkat.Text = $"Perangkat: {AppPrefs.StationDeviceName}";
        _kode.Text = AppPrefs.KodeStasiunValid(AppPrefs.StationLoginCode)
            ? "Kode login stasiun: tersimpan"
            : "Kode login stasiun: belum diisi / tidak valid";
        _badge.Text = _resolver.BadgeLabel;

        // Sekali saja setelah app dibuka: periksa alamat server dulu (Lokal/Internet), lalu
        // langsung buka stasiun supaya operator tidak perlu menekan apa pun.
        if (_sudahBukaOtomatis) return;
        _sudahBukaOtomatis = true;

        await _resolver.RefreshAsync();
        _badge.Text = _resolver.BadgeLabel;

        if (AppPrefs.StationModeSiap)
            await BukaStasiunAsync();
    }

    private async Task BukaStasiunAsync()
    {
        // Kode belum ada/tidak valid -> langsung ke pemindai QR (bukan ke Pengaturan). Kode hasil
        // scan langsung disimpan: belum ada kode yang jalan untuk dilindungi dari salah scan.
        if (!AppPrefs.StationModeSiap)
        {
            var kode = await StationScanPage.ScanKodeLoginAsync(this);
            if (kode is null) return;

            AppPrefs.StationLoginCode = kode;
            AppPrefs.StationMode = true;
            _kode.Text = "Kode login stasiun: tersimpan";
        }

        await Navigation.PushAsync(new WebPage(_auth, _resolver, "/station", "Stasiun", modeStasiun: true));
    }

    // Masuk ke admin panel tanpa mematikan Mode Stasiun -- alur login biasa (LoginPage ->
    // TujuanPage) di atas layar ini. Token user yang masih tersimpan & berlaku langsung
    // dipakai (sama seperti App.MulaiAsync di mode biasa). "Ganti akun"/logout dari web
    // memanggil PopToRootAsync -> kembali ke layar Mode Stasiun ini.
    private async Task MasukAdminAsync()
    {
        await _auth.MuatTokenTersimpanAsync();
        if (_auth.SudahLogin && await _auth.MuatModuleAsync())
        {
            await Navigation.PushAsync(new TujuanPage(_auth, _resolver));
            return;
        }

        await Navigation.PushAsync(new LoginPage(_auth, _resolver));
    }
}

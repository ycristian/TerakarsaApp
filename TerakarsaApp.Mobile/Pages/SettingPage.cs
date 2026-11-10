using TerakarsaApp.Mobile.Services;

namespace TerakarsaApp.Mobile.Pages;

// Prompt 76: Setting -- alamat server (lokal/publik/mode), fingerprint sertifikat
// lokal + tombol ambil, uji koneksi, versi app, dan placeholder Print Service
// (diisi Prompt 77).
public class SettingPage : ContentPage
{
    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;

    private readonly Entry _lokal = Gaya.Isian("https://192.168.8.233");
    private readonly Entry _publik = Gaya.Isian(AppPrefs.DefaultPublicBaseUrl);
    private readonly Picker _mode = new()
    {
        Title = "Mode alamat",
        ItemsSource = new List<string> { "Auto", "Lokal", "Internet" },
        BackgroundColor = Gaya.Kartu,
        TextColor = Gaya.Tinta
    };

    private readonly Entry _sidikJari = Gaya.Isian("belum diisi");
    private readonly Label _hasilUji = Gaya.Keterangan(string.Empty);
    private readonly Label _badge = new() { TextColor = Colors.White, FontSize = 12, FontAttributes = FontAttributes.Bold };

    // Prompt 86: Mode Stasiun.
    private readonly Switch _modeStasiun = new() { OnColor = Gaya.Aksen, VerticalOptions = LayoutOptions.Center };
    private readonly Entry _kodeStasiun = Gaya.Isian("10 karakter dari Kelola Stasiun");
    private readonly Entry _namaPerangkat = Gaya.Isian(AppPrefs.DefaultStationDeviceName);

    public SettingPage(MobileAuthService auth, ServerResolver resolver)
    {
        _auth = auth;
        _resolver = resolver;

        _modeStasiun.IsToggled = AppPrefs.StationMode;
        _kodeStasiun.Text = AppPrefs.StationLoginCode;
        _kodeStasiun.Keyboard = Keyboard.Create(KeyboardFlags.CapitalizeCharacter);
        _namaPerangkat.Text = AppPrefs.StationDeviceName;

        // Mode Stasiun dinyalakan tapi kode belum ada/tidak valid -> langsung buka pemindai.
        // Dipasang SETELAH IsToggled diisi supaya tidak terpicu saat halaman dibuka.
        _modeStasiun.Toggled += async (_, e) =>
        {
            if (e.Value && !AppPrefs.KodeStasiunValid(AppPrefs.Normalisasi(_kodeStasiun.Text)))
                await ScanKodeStasiunAsync();
        };

        Title = "Pengaturan";
        BackgroundColor = Gaya.Latar;

        _lokal.Text = AppPrefs.LocalBaseUrl;
        _publik.Text = AppPrefs.PublicBaseUrl;
        _sidikJari.Text = AppPrefs.LocalCertSha256;
        _mode.SelectedIndex = AppPrefs.UrlMode switch
        {
            ServerResolver.ModeLocal => 1,
            ServerResolver.ModePublic => 2,
            _ => 0
        };

        var ambilSidik = Gaya.Tombol("Ambil fingerprint dari server lokal", utama: false);
        ambilSidik.Clicked += async (_, _) => await AmbilSidikJariAsync();

        var uji = Gaya.Tombol("Uji koneksi", utama: false);
        uji.Clicked += async (_, _) => await UjiAsync();

        var printService = Gaya.Tombol("Buka Print Service", utama: false);
        printService.Clicked += async (_, _) =>
            await Navigation.PushAsync(new PrintServicePage(_auth, _resolver));

        var simpan = Gaya.Tombol("Simpan");
        simpan.Clicked += async (_, _) => await SimpanAsync();

        var scanKode = Gaya.Tombol("Scan QR kode login", utama: false);
        scanKode.Clicked += async (_, _) => await ScanKodeStasiunAsync();

        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = new Thickness(20, 24),
                Spacing = 12,
                Children =
                {
                    Gaya.Judul("Alamat server"),
                    Gaya.Badge(_badge, Gaya.Aksen),
                    Gaya.Keterangan("Alamat WEB (yang dibuka app). Alamat API diturunkan otomatis dari "
                                    + "alamat ini, dengan aturan yang sama seperti web di browser."),

                    Gaya.Keterangan("Alamat lokal (jaringan pabrik)"),
                    _lokal,
                    Gaya.Keterangan("Alamat publik (internet)"),
                    _publik,
                    Gaya.Keterangan("Auto = coba alamat lokal dulu (1,5 detik); kalau tidak terjangkau, "
                                    + "pakai alamat publik."),
                    _mode,

                    new BoxView { HeightRequest = 6, Color = Colors.Transparent },
                    Gaya.Judul("Sertifikat server lokal"),
                    Gaya.Keterangan("Server lokal memakai sertifikat sendiri (self-signed). App HANYA "
                                    + "menerima sertifikat yang fingerprint SHA-256-nya sama dengan di bawah, "
                                    + "dan hanya untuk alamat lokal. Alamat publik tetap diperiksa normal."),
                    _sidikJari,
                    ambilSidik,

                    // Prompt 86: disimpan oleh tombol Simpan di bawah, bersama alamat server.
                    new BoxView { HeightRequest = 6, Color = Colors.Transparent },
                    Gaya.Judul("Mode Stasiun"),
                    Gaya.Keterangan("Untuk perangkat stasiun di lantai produksi: app langsung membuka halaman "
                                    + "stasiun tanpa login, memakai kode login stasiun dari menu Kelola Stasiun "
                                    + "(tombol Kode Login). Kalau kode di-refresh admin, ganti kode di sini."),
                    new HorizontalStackLayout
                    {
                        Spacing = 10,
                        Children = { _modeStasiun, new Label { Text = "Aktifkan Mode Stasiun", TextColor = Gaya.Tinta, FontSize = 15, VerticalOptions = LayoutOptions.Center } }
                    },
                    Gaya.Keterangan("Kode login stasiun"),
                    _kodeStasiun,
                    scanKode,
                    Gaya.Keterangan("Nama perangkat (muncul di perangkat lain saat stasiun ini sedang dipakai)"),
                    _namaPerangkat,
                    Gaya.Keterangan($"ID perangkat: {AppPrefs.StationDeviceId[..8]}"),

                    new BoxView { HeightRequest = 6, Color = Colors.Transparent },
                    uji,
                    _hasilUji,
                    simpan,

                    new BoxView { HeightRequest = 10, Color = Colors.Transparent },
                    Gaya.Judul("Print Service"),
                    Gaya.Keterangan("Cetak label 30x20 mm dari HP ini ke printer Bluetooth."),
                    printService,

                    new BoxView { HeightRequest = 10, Color = Colors.Transparent },
                    Gaya.Keterangan($"Terakarsa versi {AppInfo.Current.VersionString} "
                                    + $"(build {AppInfo.Current.BuildString})")
                }
            }
        };
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        _badge.Text = _resolver.BadgeLabel;
    }

    private async Task SimpanAsync()
    {
        // Prompt 86: kode stasiun divalidasi dulu -- kode tidak valid tidak boleh tersimpan,
        // dan Mode Stasiun tidak bisa diaktifkan tanpa kode yang valid.
        var kodeStasiun = AppPrefs.Normalisasi(_kodeStasiun.Text);
        if ((_modeStasiun.IsToggled || kodeStasiun.Length > 0) && !AppPrefs.KodeStasiunValid(kodeStasiun))
        {
            await DisplayAlert("Mode Stasiun", AppPrefs.PesanKodeStasiunTidakValid, "OK");
            return;
        }

        var stasiunSiapSebelumnya = AppPrefs.StationModeSiap;
        AppPrefs.StationMode = _modeStasiun.IsToggled;
        AppPrefs.StationLoginCode = kodeStasiun;
        AppPrefs.StationDeviceName = _namaPerangkat.Text ?? string.Empty;
        _kodeStasiun.Text = kodeStasiun;
        _namaPerangkat.Text = AppPrefs.StationDeviceName;

        AppPrefs.LocalBaseUrl = _lokal.Text ?? string.Empty;
        AppPrefs.PublicBaseUrl = _publik.Text ?? string.Empty;
        AppPrefs.LocalCertSha256 = _sidikJari.Text ?? string.Empty;
        AppPrefs.UrlMode = _mode.SelectedIndex switch
        {
            1 => ServerResolver.ModeLocal,
            2 => ServerResolver.ModePublic,
            _ => ServerResolver.ModeAuto
        };

        await _resolver.RefreshAsync();
        _badge.Text = _resolver.BadgeLabel;

        await DisplayAlert("Pengaturan", $"Tersimpan. Alamat aktif: {_resolver.ActiveBaseUrl}", "OK");

        // Prompt 86: Mode Stasiun nyala/mati langsung berlaku -- ganti root window tanpa
        // tutup-buka app (StationHomePage langsung membuka /station; LoginPage = alur biasa).
        if (AppPrefs.StationModeSiap != stasiunSiapSebelumnya)
            GantiRootWindow();
    }

    private void GantiRootWindow()
    {
        var window = Application.Current?.Windows.FirstOrDefault();
        if (window is null) return;

        Page root = AppPrefs.StationModeSiap
            ? new StationHomePage(_auth, _resolver)
            : new LoginPage(_auth, _resolver);
        window.Page = new NavigationPage(root);
    }

    // Prompt 86: hasil scan hanya MENGISI isian kode; tetap harus ditekan Simpan, supaya salah
    // scan (mis. QR bundle) tidak langsung mengganti kode stasiun.
    private async Task ScanKodeStasiunAsync()
    {
        var kode = await StationScanPage.ScanKodeLoginAsync(this);
        if (kode is null) return;

        _kodeStasiun.Text = kode;
        await DisplayAlert("Scan QR", $"Kode {kode} terisi. Tekan Simpan untuk menyimpannya.", "OK");
    }

    private async Task UjiAsync()
    {
        _hasilUji.Text = "Menguji...";

        var lokalOk = false;
        var lokalPesan = "belum diisi";

        if (!string.IsNullOrWhiteSpace(_lokal.Text))
            (lokalOk, lokalPesan) = await _resolver.UjiAsync(_lokal.Text!.Trim(), ServerResolver.UjiManualTimeout);

        var (publikOk, publikPesan) = await _resolver.UjiAsync(
            string.IsNullOrWhiteSpace(_publik.Text) ? AppPrefs.DefaultPublicBaseUrl : _publik.Text!.Trim(),
            ServerResolver.UjiManualTimeout);

        _hasilUji.Text = $"Lokal: {(lokalOk ? "OK" : "gagal")} — {lokalPesan}\n"
                         + $"Internet: {(publikOk ? "OK" : "gagal")} — {publikPesan}";
    }

    private async Task AmbilSidikJariAsync()
    {
        if (string.IsNullOrWhiteSpace(_lokal.Text))
        {
            await DisplayAlert("Fingerprint", "Isi alamat lokal dulu.", "OK");
            return;
        }

        var (ok, pesan, sidik) = await SertifikatLokal.AmbilAsync(_lokal.Text!.Trim());

        if (!ok)
        {
            await DisplayAlert("Fingerprint", pesan, "OK");
            return;
        }

        var setuju = await DisplayAlert("Sertifikat server lokal",
            $"{pesan}\n\nSHA-256:\n{sidik}\n\nPercayai sertifikat ini?", "Percayai", "Batal");

        if (!setuju) return;

        _sidikJari.Text = sidik;
        AppPrefs.LocalCertSha256 = sidik;
    }
}

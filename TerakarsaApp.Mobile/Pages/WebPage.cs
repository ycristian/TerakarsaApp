using TerakarsaApp.Mobile.Services;

namespace TerakarsaApp.Mobile.Pages;

// Prompt 76: WebView yang membuka web TMOS dalam keadaan SUDAH LOGIN.
//
// Cara menyuntik token: web (Blazor WASM) membaca token dari localStorage saat boot
// (lihat CustomAuthStateProvider di TerakarsaApp.Client), jadi urutannya harus:
//   1. buka halaman apa pun di origin aktif (dipakai /login -- paling ringan),
//   2. setelah halaman selesai dimuat, isi localStorage "authToken"/"refreshToken"
//      lewat JavaScript -- NAMA KEY-nya sama dengan yang dipakai web,
//   3. baru arahkan ke route tujuan, sehingga app Blazor boot dengan token itu.
// Menyuntik setelah app Blazor boot tidak cukup: halaman sudah memutuskan "belum
// login" dan melempar ke /login.
//
// Prompt 86: modeStasiun = urutan muat yang sama, tapi yang disuntik kode login stasiun +
// identitas perangkat (stationLockCode/stationDeviceId/stationDeviceName -- dibaca /station,
// Prompt 85), BUKAN token user. stationToken dan stationLockCodeUsed tidak disentuh (dikelola
// web). Deteksi "/login -> logout app" tidak berlaku di mode ini.
public class WebPage : ContentPage
{
    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;
    private readonly string _route;
    private readonly bool _modeStasiun;

    private readonly WebView _web = new() { VerticalOptions = LayoutOptions.Fill };
    private readonly Label _status = new()
    {
        Text = "Memuat...",
        FontSize = 13,
        TextColor = Gaya.Redup,
        Padding = new Thickness(12, 8)
    };

    private bool _tokenDisuntik;
    private bool _sudahDiarahkan;
    private string _baseUrlSaatMuat;

    public WebPage(MobileAuthService auth, ServerResolver resolver, string route, string judul, bool modeStasiun = false)
    {
        _auth = auth;
        _resolver = resolver;
        _modeStasiun = modeStasiun;
        _route = route.StartsWith('/') ? route : "/" + route;
        _baseUrlSaatMuat = resolver.ActiveBaseUrl;

        Title = judul;
        BackgroundColor = Gaya.Latar;

        Content = new Grid
        {
            RowDefinitions =
            {
                new RowDefinition { Height = GridLength.Auto },
                new RowDefinition { Height = GridLength.Star }
            },
            Children = { _status, _web }
        };

        Grid.SetRow(_status, 0);
        Grid.SetRow(_web, 1);

        PasangGlue();
    }

    private bool _sudahTampil;

    protected override void OnAppearing()
    {
        base.OnAppearing();

        // Alamat server berubah (mis. keluar dari jaringan pabrik) -> muat ulang
        // halaman yang sama di origin baru, setelah token disuntik ulang. Dipasang ulang
        // setiap tampil karena OnDisappearing melepasnya (mis. saat modal scan QR terbuka).
        _resolver.Changed -= AlamatBerubah;
        _resolver.Changed += AlamatBerubah;

        // Prompt 86: muat hanya saat pertama tampil. Halaman ini tampil ulang setelah modal
        // pemindai QR ditutup -- memuat ulang di situ akan menyuntik kode LAMA; yang perlu
        // memuat ulang (scan berhasil) memanggil MulaiMuat sendiri.
        if (_sudahTampil) return;
        _sudahTampil = true;
        MulaiMuat();
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _resolver.Changed -= AlamatBerubah;
    }

    private void MulaiMuat()
    {
        _tokenDisuntik = false;
        _sudahDiarahkan = false;
        _baseUrlSaatMuat = _resolver.ActiveBaseUrl;
        _status.Text = $"Memuat {_baseUrlSaatMuat}...";
        _status.IsVisible = true;

        _web.Source = new UrlWebViewSource { Url = $"{_baseUrlSaatMuat}/login" };
    }

    private void AlamatBerubah()
    {
        MainThread.BeginInvokeOnMainThread(() =>
        {
            if (_resolver.ActiveBaseUrl == _baseUrlSaatMuat) return;
            MulaiMuat();
        });
    }

    private void PasangGlue()
    {
#if ANDROID
        _web.HandlerChanged += (_, _) =>
        {
            if (_web.Handler?.PlatformView is not Android.Webkit.WebView platform) return;
            if (Platform.CurrentActivity is not { } activity) return;

            Platforms.Android.WebViewGlue.Pasang(platform, activity, HalamanSelesai, PerintahApp);
        };
#endif
    }

    private bool _sedangScan;
    private bool _scanOtomatisDibatalkan;

    // Prompt 86: web meminta aksi native lewat link "terakarsa://<perintah>" (ditangkap
    // WebViewClient). Saat ini hanya "scan-station": kode login stasiun ditolak server
    // (/station mode app) -> buka pemindai, simpan kode baru, muat ulang stasiun.
    // "?auto=1" = dipicu otomatis oleh web saat kartu "kode tidak berlaku" tampil; diabaikan
    // kalau operator sudah membatalkan pemindai sekali (tombol di web tetap bisa dipakai).
    private void PerintahApp(string url)
    {
        if (!_modeStasiun) return;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return;
        if (!string.Equals(uri.Host, "scan-station", StringComparison.OrdinalIgnoreCase)) return;

        var otomatis = uri.Query.Contains("auto=1", StringComparison.OrdinalIgnoreCase);

        MainThread.BeginInvokeOnMainThread(async () =>
        {
            if (_sedangScan) return;
            if (otomatis && _scanOtomatisDibatalkan) return;

            _sedangScan = true;
            try
            {
                var kode = await StationScanPage.ScanKodeLoginAsync(this);
                if (kode is null)
                {
                    _scanOtomatisDibatalkan = true;
                    return;
                }

                // Langsung disimpan: kode lama sudah ditolak server, tidak ada yang dilindungi.
                AppPrefs.StationLoginCode = kode;
                _scanOtomatisDibatalkan = false;
                MulaiMuat();
            }
            finally
            {
                _sedangScan = false;
            }
        });
    }

    // Dipanggil dari WebViewClient Android setiap halaman selesai dimuat.
    private void HalamanSelesai(string url)
    {
        MainThread.BeginInvokeOnMainThread(async () =>
        {
            if (!_tokenDisuntik)
            {
                _tokenDisuntik = true;
                await SuntikTokenAsync();
                return;
            }

            if (!_sudahDiarahkan)
            {
                _sudahDiarahkan = true;
                _status.IsVisible = false;
                _web.Source = new UrlWebViewSource { Url = $"{_baseUrlSaatMuat}{_route}" };
                return;
            }

            // Web melakukan logout (atau token ditolak) -> balik ke layar login app.
            // Mode stasiun tidak punya login user -- /station menangani tokennya sendiri.
            if (!_modeStasiun && url.Contains("/login", StringComparison.OrdinalIgnoreCase))
            {
                await _auth.LogoutAsync(hubungiServer: false);
                await Navigation.PopToRootAsync();
            }
        });
    }

    private async Task SuntikTokenAsync()
    {
        var js = _modeStasiun ? JsSuntikStasiun() : JsSuntikTokenUser();

        try
        {
            await _web.EvaluateJavaScriptAsync(js);
        }
        catch (Exception)
        {
            // Kalau penyuntikan gagal, web akan menampilkan layar login-nya sendiri.
        }

        // Lanjut ke route tujuan (muat ulang origin yang sama supaya Blazor boot
        // dengan token yang baru disuntik).
        _sudahDiarahkan = true;
        _status.IsVisible = false;
        _web.Source = new UrlWebViewSource { Url = $"{_baseUrlSaatMuat}{_route}" };
    }

    private string JsSuntikTokenUser()
    {
        var token = Escape(_auth.AccessToken);
        var refresh = Escape(_auth.RefreshToken);

        return "(function(){try{"
               + $"localStorage.setItem('{MobileAuthService.TokenKey}','{token}');"
               + $"localStorage.setItem('{MobileAuthService.RefreshTokenKey}','{refresh}');"
               + "return 'ok';}catch(e){return 'err';}})()";
    }

    // Prompt 86: nama key harus persis dengan yang dibaca /station (Prompt 85). Disuntik ulang
    // setiap halaman dimuat ulang, termasuk saat ServerResolver memindah origin -- localStorage
    // per origin, dan web di origin baru akan klaim ulang sendiri (ID perangkat sama -> tanpa
    // peringatan ambil alih).
    private static string JsSuntikStasiun()
    {
        var kode = Escape(AppPrefs.StationLoginCode);
        var id = Escape(AppPrefs.StationDeviceId);
        var nama = Escape(AppPrefs.StationDeviceName);

        return "(function(){try{"
               + $"localStorage.setItem('stationLockCode','{kode}');"
               + $"localStorage.setItem('stationDeviceId','{id}');"
               + $"localStorage.setItem('stationDeviceName','{nama}');"
               + "return 'ok';}catch(e){return 'err';}})()";
    }

    private static string Escape(string? nilai) =>
        (nilai ?? string.Empty).Replace("\\", "\\\\").Replace("'", "\\'");

    // Tombol back Android: mundur di dalam web dulu; kalau tidak bisa, kembali ke
    // layar pilih tujuan (perilaku standar app pembungkus).
    protected override bool OnBackButtonPressed()
    {
        if (_web.CanGoBack)
        {
            _web.GoBack();
            return true;
        }

        return base.OnBackButtonPressed();
    }
}

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
public class WebPage : ContentPage
{
    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;
    private readonly string _route;

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

    public WebPage(MobileAuthService auth, ServerResolver resolver, string route, string judul)
    {
        _auth = auth;
        _resolver = resolver;
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

        // Alamat server berubah (mis. keluar dari jaringan pabrik) -> muat ulang
        // halaman yang sama di origin baru, setelah token disuntik ulang.
        _resolver.Changed += AlamatBerubah;
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
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

            Platforms.Android.WebViewGlue.Pasang(platform, activity, HalamanSelesai);
        };
#endif
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
            if (url.Contains("/login", StringComparison.OrdinalIgnoreCase))
            {
                await _auth.LogoutAsync(hubungiServer: false);
                await Navigation.PopToRootAsync();
            }
        });
    }

    private async Task SuntikTokenAsync()
    {
        var token = Escape(_auth.AccessToken);
        var refresh = Escape(_auth.RefreshToken);

        var js = "(function(){try{"
                 + $"localStorage.setItem('{MobileAuthService.TokenKey}','{token}');"
                 + $"localStorage.setItem('{MobileAuthService.RefreshTokenKey}','{refresh}');"
                 + "return 'ok';}catch(e){return 'err';}})()";

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

using TerakarsaApp.Mobile.Services;

namespace TerakarsaApp.Mobile.Pages;

// Prompt 76: layar "Pilih tujuan" -- hanya kartu yang modulnya dimiliki user.
//
//   Dashboard Utama : user punya module apa pun SELAIN INV_THREAD / TNI_PDH*  -> /
//   Admin Gudang    : module INV_THREAD                                       -> /gudang/benang
//   PO TNI          : module TNI_PDH                                          -> /tni
//
// Kalau cuma ada satu tujuan, layar ini dilewati dan WebView langsung dibuka.
public class TujuanPage : ContentPage
{
    private const string ModuleGudang = "INV_THREAD";
    private const string ModuleTni = "TNI_PDH";

    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;

    private readonly VerticalStackLayout _daftar = new() { Spacing = 12 };
    private readonly Label _badge = new() { TextColor = Colors.White, FontSize = 12, FontAttributes = FontAttributes.Bold };
    private readonly Label _alamat = Gaya.Keterangan(string.Empty);

    private bool _sudahLompat;

    public TujuanPage(MobileAuthService auth, ServerResolver resolver)
    {
        _auth = auth;
        _resolver = resolver;

        Title = "Pilih tujuan";
        BackgroundColor = Gaya.Latar;

        var setting = new Button
        {
            Text = "Pengaturan",
            BackgroundColor = Colors.Transparent,
            TextColor = Gaya.Aksen,
            FontSize = 14,
            HorizontalOptions = LayoutOptions.Start
        };
        setting.Clicked += async (_, _) => await Navigation.PushAsync(new SettingPage(_auth, _resolver));

        var gantiAkun = new Button
        {
            Text = "Ganti akun",
            BackgroundColor = Colors.Transparent,
            TextColor = Gaya.Merah,
            FontSize = 14,
            HorizontalOptions = LayoutOptions.Start
        };
        gantiAkun.Clicked += async (_, _) => await GantiAkunAsync();

        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = new Thickness(20, 28),
                Spacing = 14,
                Children =
                {
                    Gaya.Judul("Mau buka apa?"),
                    Gaya.Badge(_badge, Gaya.Aksen),
                    _alamat,
                    _daftar,
                    new BoxView { HeightRequest = 8, Color = Colors.Transparent },
                    setting,
                    gantiAkun
                }
            }
        };
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();

        _badge.Text = _resolver.BadgeLabel;
        _alamat.Text = _resolver.ActiveBaseUrl;

        if (_auth.Modules.Count == 0) await _auth.MuatModuleAsync();

        var tujuan = DaftarSasaran();
        Susun(tujuan);

        // Satu tujuan saja -> buka langsung (sekali, supaya tidak balik-balik saat
        // WebView ditutup dengan tombol back).
        if (tujuan.Count == 1 && !_sudahLompat)
        {
            _sudahLompat = true;
            await Buka(tujuan[0]);
        }
    }

    private record Sasaran(string Judul, string Keterangan, string Route);

    private List<Sasaran> DaftarSasaran()
    {
        var hasil = new List<Sasaran>();

        var punyaLain = _auth.Modules.Any(m =>
            !m.Code.Equals(ModuleGudang, StringComparison.OrdinalIgnoreCase) &&
            !m.Code.StartsWith(ModuleTni, StringComparison.OrdinalIgnoreCase));

        if (punyaLain)
            hasil.Add(new Sasaran("Dashboard Utama", "Produksi, order, laporan", "/"));

        if (_auth.PunyaModule(ModuleGudang))
            hasil.Add(new Sasaran("Admin Gudang", "Stok benang: scan, ambil, kembali, opname", "/gudang/benang"));

        if (_auth.PunyaModule(ModuleTni))
            hasil.Add(new Sasaran("PO TNI", "Module PDH TNI AD", "/tni"));

        // Tidak punya module apa pun: tetap beri jalan ke dashboard supaya user
        // melihat pesan dari web, bukan layar kosong di app.
        if (hasil.Count == 0)
            hasil.Add(new Sasaran("Dashboard Utama", "Produksi, order, laporan", "/"));

        return hasil;
    }

    private void Susun(List<Sasaran> tujuan)
    {
        _daftar.Children.Clear();

        foreach (var t in tujuan)
        {
            var kartu = Gaya.KartuTujuan(t.Judul, t.Keterangan, t.Route);
            var tap = new TapGestureRecognizer();
            var pilih = t;
            tap.Tapped += async (_, _) => await Buka(pilih);
            kartu.GestureRecognizers.Add(tap);
            _daftar.Children.Add(kartu);
        }
    }

    private Task Buka(Sasaran t) =>
        Navigation.PushAsync(new WebPage(_auth, _resolver, t.Route, t.Judul));

    private async Task GantiAkunAsync()
    {
        var yakin = await DisplayAlert("Ganti akun", "Keluar dari akun ini?", "Ya", "Batal");
        if (!yakin) return;

        await _auth.LogoutAsync();
        await Navigation.PopToRootAsync();
    }
}

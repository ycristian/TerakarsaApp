using TerakarsaApp.Mobile.Services;

namespace TerakarsaApp.Mobile.Pages;

// Prompt 76: login native. Memakai endpoint login yang sama dengan web; setelah
// berhasil, daftar module user diambil lalu app pindah ke layar Pilih tujuan.
public class LoginPage : ContentPage
{
    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;

    private readonly Entry _username = Gaya.Isian("Username");
    private readonly Entry _password = Gaya.Isian("Password", password: true);
    private readonly Button _masuk = Gaya.Tombol("Masuk");
    private readonly Label _pesan = new() { TextColor = Gaya.Merah, FontSize = 13, IsVisible = false };
    private readonly Label _badge = new() { TextColor = Colors.White, FontSize = 12, FontAttributes = FontAttributes.Bold };
    private readonly Label _alamat = Gaya.Keterangan(string.Empty);

    public LoginPage(MobileAuthService auth, ServerResolver resolver)
    {
        _auth = auth;
        _resolver = resolver;

        Title = "Masuk";
        BackgroundColor = Gaya.Latar;

        _masuk.Clicked += async (_, _) => await MasukAsync();
        _password.Completed += async (_, _) => await MasukAsync();

        var setting = new Button
        {
            Text = "Pengaturan server",
            BackgroundColor = Colors.Transparent,
            TextColor = Gaya.Aksen,
            FontSize = 14
        };
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
                    new Label
                    {
                        Text = "Terakarsa",
                        FontSize = 30,
                        FontAttributes = FontAttributes.Bold,
                        TextColor = Gaya.Aksen
                    },
                    Gaya.Keterangan("Sistem pencatatan produksi garmen"),
                    Gaya.Badge(_badge, Gaya.Aksen),
                    _alamat,
                    new BoxView { HeightRequest = 8, Color = Colors.Transparent },
                    _username,
                    _password,
                    _masuk,
                    _pesan,
                    setting
                }
            }
        };
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();

        // Alamat aktif bisa berubah saat app kembali dari layar Setting.
        await _resolver.RefreshAsync();
        TampilkanAlamat();
    }

    private void TampilkanAlamat()
    {
        _badge.Text = _resolver.BadgeLabel;
        _alamat.Text = _resolver.ActiveBaseUrl;
    }

    private async Task MasukAsync()
    {
        if (string.IsNullOrWhiteSpace(_username.Text) || string.IsNullOrWhiteSpace(_password.Text))
        {
            Tampilkan("Username dan password wajib diisi.");
            return;
        }

        _masuk.IsEnabled = false;
        _masuk.Text = "Memproses...";
        _pesan.IsVisible = false;

        var (success, error) = await _auth.LoginAsync(_username.Text.Trim(), _password.Text);

        _masuk.IsEnabled = true;
        _masuk.Text = "Masuk";

        if (!success)
        {
            Tampilkan(error);
            return;
        }

        _password.Text = string.Empty;
        await Navigation.PushAsync(new TujuanPage(_auth, _resolver));
    }

    private void Tampilkan(string pesan)
    {
        _pesan.Text = pesan;
        _pesan.IsVisible = true;
    }
}

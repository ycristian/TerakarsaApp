using TerakarsaApp.Mobile.Services;
using ZXing.Net.Maui;
using ZXing.Net.Maui.Controls;

namespace TerakarsaApp.Mobile.Pages;

// Prompt 86: pemindai QR kode login stasiun di Pengaturan (dibuka modal). Hanya membaca --
// hasilnya dikembalikan ke SettingPage untuk mengisi isian kode, TIDAK langsung disimpan.
// Izin kamera diminta pemanggil sebelum halaman ini dibuka.
public class StationScanPage : ContentPage
{
    private readonly TaskCompletionSource<string?> _hasil = new();
    private readonly CameraBarcodeReaderView _kamera;

    // null = dibatalkan.
    public Task<string?> HasilAsync => _hasil.Task;

    // Minta izin kamera, buka pemindai (modal di atas `halaman`), kembalikan kode login yang
    // valid. null = batal atau gagal -- pesannya sudah ditampilkan ke user. Dipakai Pengaturan,
    // layar Mode Stasiun, dan WebView stasiun (kode ditolak server).
    public static async Task<string?> ScanKodeLoginAsync(Page halaman)
    {
        var izin = await Permissions.RequestAsync<Permissions.Camera>();
        if (izin != PermissionStatus.Granted)
        {
            await halaman.DisplayAlert("Scan QR", "Izin kamera dibutuhkan untuk scan QR. Aktifkan di pengaturan Android.", "OK");
            return null;
        }

        var pemindai = new StationScanPage();
        await halaman.Navigation.PushModalAsync(pemindai);
        var isi = await pemindai.HasilAsync;
        if (isi is null) return null;

        var kode = AppPrefs.AmbilKodeDariQr(isi);
        if (!AppPrefs.KodeStasiunValid(kode))
        {
            await halaman.DisplayAlert("Scan QR", "QR ini bukan kode login stasiun. " + AppPrefs.PesanKodeStasiunTidakValid, "OK");
            return null;
        }

        return kode;
    }

    public StationScanPage()
    {
        Title = "Scan QR Kode Login";
        BackgroundColor = Colors.Black;

        _kamera = new CameraBarcodeReaderView
        {
            Options = new BarcodeReaderOptions
            {
                Formats = BarcodeFormat.QrCode,
                AutoRotate = true,
                Multiple = false
            },
            IsDetecting = true,
            VerticalOptions = LayoutOptions.Fill
        };
        _kamera.BarcodesDetected += QrTerbaca;

        var batal = Gaya.Tombol("Batal", utama: false);
        batal.Clicked += async (_, _) => await SelesaiAsync(null);

        var keterangan = new Label
        {
            Text = "Arahkan kamera ke QR di modal Kode Login (Kelola Stasiun).",
            TextColor = Colors.White,
            FontSize = 14,
            HorizontalTextAlignment = TextAlignment.Center
        };

        var bawah = new VerticalStackLayout
        {
            Padding = new Thickness(20, 12, 20, 24),
            Spacing = 12,
            Children = { keterangan, batal }
        };

        var grid = new Grid
        {
            RowDefinitions =
            {
                new RowDefinition { Height = GridLength.Star },
                new RowDefinition { Height = GridLength.Auto }
            },
            Children = { _kamera, bawah }
        };
        Grid.SetRow(_kamera, 0);
        Grid.SetRow(bawah, 1);

        Content = grid;
    }

    private void QrTerbaca(object? sender, BarcodeDetectionEventArgs e)
    {
        var isi = e.Results?.FirstOrDefault()?.Value;
        if (string.IsNullOrWhiteSpace(isi)) return;

        MainThread.BeginInvokeOnMainThread(async () => await SelesaiAsync(isi));
    }

    private async Task SelesaiAsync(string? isi)
    {
        // Event kamera bisa datang beberapa kali berturut-turut -- hanya yang pertama dipakai.
        if (!_hasil.TrySetResult(isi)) return;

        _kamera.IsDetecting = false;
        await Navigation.PopModalAsync();
    }

    protected override bool OnBackButtonPressed()
    {
        _ = SelesaiAsync(null);
        return true;
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _kamera.IsDetecting = false;
        _hasil.TrySetResult(null);
    }
}

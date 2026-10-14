using System.Net.Http.Json;
using TerakarsaApp.Mobile.Services;
using TerakarsaApp.Printing;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.Mobile.Pages;

// Prompt 77: Setting → Print Service.
//
// Alur sekali-pasang:
//   1. izin Bluetooth (Android 12+: BLUETOOTH_CONNECT/SCAN runtime)
//   2. pilih printer dari daftar yang SUDAH di-pairing di pengaturan Android
//   3. Daftarkan HP ini -> api/print/devices/register-mobile -> device_token
//      disimpan di SecureStorage
//   4. owner memindahkan route THREAD_*_LABEL ke device ini di /admin/printer
//   5. switch Aktif -> foreground service mulai mengambil antrian
public class PrintServicePage : ContentPage
{
    private readonly MobileAuthService _auth;
    private readonly ServerResolver _resolver;

    private readonly Entry _namaDevice = Gaya.Isian("HP Gudang");
    private readonly Picker _printer = new()
    {
        Title = "Printer Bluetooth (sudah di-pairing)",
        BackgroundColor = Gaya.Kartu,
        TextColor = Gaya.Tinta
    };

    private readonly Label _status = Gaya.Keterangan(string.Empty);
    private readonly Label _logLabel = new() { FontSize = 12, TextColor = Gaya.Redup, LineBreakMode = LineBreakMode.WordWrap };
    private readonly Switch _aktif = new() { OnColor = Gaya.Aksen };

    private List<(string Nama, string Mac)> _pairing = new();

    public PrintServicePage(MobileAuthService auth, ServerResolver resolver)
    {
        _auth = auth;
        _resolver = resolver;

        Title = "Print Service";
        BackgroundColor = Gaya.Latar;

        _namaDevice.Text = PrintPrefs.DeviceName;
        _aktif.IsToggled = PrintPrefs.Aktif;
        _aktif.Toggled += async (_, e) => await AktifDiubahAsync(e.Value);

        var muatPrinter = Gaya.Tombol("Muat daftar printer", utama: false);
        muatPrinter.Clicked += async (_, _) => await MuatPrinterAsync();

        var daftar = Gaya.Tombol("Daftarkan HP ini");
        daftar.Clicked += async (_, _) => await DaftarkanAsync();

        var test = Gaya.Tombol("Test print (30×20 mm)", utama: false);
        test.Clicked += async (_, _) => await TestPrintAsync();

        Content = new ScrollView
        {
            Content = new VerticalStackLayout
            {
                Padding = new Thickness(20, 24),
                Spacing = 12,
                Children =
                {
                    Gaya.Judul("Printer Bluetooth"),
                    Gaya.Keterangan("Pasangkan printer dulu di pengaturan Bluetooth Android "
                                    + "(Xprinter XP-P323B), lalu muat daftarnya di sini."),
                    _printer,
                    muatPrinter,

                    new BoxView { HeightRequest = 6, Color = Colors.Transparent },
                    Gaya.Judul("Daftarkan HP ini"),
                    Gaya.Keterangan("Nama device yang tampil di halaman Printer & Routing web."),
                    _namaDevice,
                    daftar,
                    Gaya.Keterangan("Setelah terdaftar, minta admin memindahkan job label benang ke "
                                    + "device ini di halaman web /admin/printer."),

                    new BoxView { HeightRequest = 6, Color = Colors.Transparent },
                    Gaya.Judul("Status"),
                    _status,
                    new HorizontalStackLayout
                    {
                        Spacing = 10,
                        Children = { new Label { Text = "Aktif", TextColor = Gaya.Tinta, VerticalOptions = LayoutOptions.Center }, _aktif }
                    },
                    test,

                    new BoxView { HeightRequest = 6, Color = Colors.Transparent },
                    Gaya.Judul("Log"),
                    _logLabel
                }
            }
        };
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();

        PrintLog.Changed += LogBerubah;
        TampilkanStatus();
        TampilkanLog();

        await MintaIzinBluetoothAsync();
        await MuatPrinterAsync();
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        PrintLog.Changed -= LogBerubah;
    }

    private void LogBerubah() => MainThread.BeginInvokeOnMainThread(TampilkanLog);

    private void TampilkanLog() =>
        _logLabel.Text = PrintLog.Semua().Count == 0 ? "(belum ada)" : string.Join("\n", PrintLog.Semua());

    private void TampilkanStatus()
    {
        var terdaftar = PrintPrefs.SudahTerdaftar ? $"terdaftar sebagai {PrintPrefs.DeviceCode}" : "belum terdaftar";
        var printer = string.IsNullOrWhiteSpace(PrintPrefs.PrinterName) ? "printer belum dipilih" : PrintPrefs.PrinterName;

#if ANDROID
        var jalan = Platforms.Android.PrintForegroundService.Berjalan ? "service jalan" : "service berhenti";
#else
        var jalan = "service hanya tersedia di Android";
#endif

        _status.Text = $"HP {terdaftar} · {printer} · {jalan} · alamat {_resolver.BadgeLabel}";
    }

    private async Task<bool> MintaIzinBluetoothAsync()
    {
#if ANDROID
        // Android 12+ memakai izin runtime BLUETOOTH_CONNECT/SCAN; di bawahnya izin
        // BLUETOOTH/BLUETOOTH_ADMIN cukup dideklarasikan di manifest.
        if (!OperatingSystem.IsAndroidVersionAtLeast(31)) return true;

        var status = await Permissions.RequestAsync<IzinBluetooth>();

        if (status != PermissionStatus.Granted)
        {
            await DisplayAlert("Izin Bluetooth",
                "App butuh izin Bluetooth untuk mengirim label ke printer.", "OK");
            return false;
        }
#endif
        return true;
    }

    private async Task MuatPrinterAsync()
    {
#if ANDROID
        _pairing = Platforms.Android.BluetoothPrinter.DaftarPairing();
#endif

        _printer.ItemsSource = _pairing.Select(p => $"{p.Nama} ({p.Mac})").ToList();

        if (_pairing.Count == 0)
        {
            _printer.Title = "Belum ada printer di-pairing";
            return;
        }

        var terpilih = _pairing.FindIndex(p => p.Mac == PrintPrefs.PrinterMac);
        if (terpilih >= 0) _printer.SelectedIndex = terpilih;

        _printer.SelectedIndexChanged += PrinterDipilih;
        await Task.CompletedTask;
    }

    private void PrinterDipilih(object? sender, EventArgs e)
    {
        if (_printer.SelectedIndex < 0 || _printer.SelectedIndex >= _pairing.Count) return;

        var (nama, mac) = _pairing[_printer.SelectedIndex];
        PrintPrefs.PrinterName = nama;
        PrintPrefs.PrinterMac = mac;

        PrintLog.Tulis($"Printer dipilih: {nama}");
        TampilkanStatus();
    }

    private async Task DaftarkanAsync()
    {
        if (!_auth.SudahLogin)
        {
            await DisplayAlert("Daftarkan HP", "Login dulu sebelum mendaftarkan HP ini.", "OK");
            return;
        }

        if (string.IsNullOrWhiteSpace(PrintPrefs.PrinterMac))
        {
            await DisplayAlert("Daftarkan HP", "Pilih printer Bluetooth dulu.", "OK");
            return;
        }

        var nama = string.IsNullOrWhiteSpace(_namaDevice.Text) ? "HP Gudang" : _namaDevice.Text!.Trim();

        // device_code tetap per HP: dipakai ulang kalau sudah ada, supaya registrasi
        // ulang mengganti token device yang sama (bukan membuat device baru).
        var kode = PrintPrefs.SudahTerdaftar
            ? PrintPrefs.DeviceCode
            : "HP-" + Guid.NewGuid().ToString("N")[..6].ToUpperInvariant();

        try
        {
            using var http = ServerResolver.BuatHttpClientAktif(_resolver);
            http.DefaultRequestHeaders.Authorization = new("Bearer", _auth.AccessToken);

            var response = await http.PostAsJsonAsync("api/print/devices/register-mobile",
                new PrintDeviceRegisterRequest
                {
                    DeviceCode = kode,
                    DeviceName = nama,
                    PrinterName = $"{PrintPrefs.PrinterName} [{PrintPrefs.PrinterMac}]"
                });

            if (!response.IsSuccessStatusCode)
            {
                var pesan = (await response.Content.ReadAsStringAsync()).Trim().Trim('"');
                await DisplayAlert("Daftarkan HP",
                    string.IsNullOrWhiteSpace(pesan) ? "Registrasi gagal." : pesan, "OK");
                return;
            }

            var hasil = await response.Content.ReadFromJsonAsync<PrintDeviceRegisterResult>();
            if (hasil is null || string.IsNullOrWhiteSpace(hasil.DeviceToken))
            {
                await DisplayAlert("Daftarkan HP", "Server tidak mengirim token device.", "OK");
                return;
            }

            PrintPrefs.DeviceCode = hasil.DeviceCode;
            PrintPrefs.DeviceName = hasil.DeviceName;
            await PrintPrefs.SimpanTokenAsync(hasil.DeviceToken);

            PrintLog.Tulis($"HP terdaftar sebagai {hasil.DeviceCode}.");
            TampilkanStatus();

            await DisplayAlert("Daftarkan HP",
                $"HP ini terdaftar sebagai {hasil.DeviceCode}.\n\nLangkah berikutnya: minta admin "
                + "mengarahkan job label ke device ini di halaman web Printer & Routing.", "OK");
        }
        catch (Exception ex)
        {
            await DisplayAlert("Daftarkan HP", $"Tidak bisa menghubungi server: {ex.Message}", "OK");
        }
    }

    private async Task AktifDiubahAsync(bool aktif)
    {
        if (aktif)
        {
            if (!PrintPrefs.SudahTerdaftar)
            {
                _aktif.IsToggled = false;
                await DisplayAlert("Print service", "Daftarkan HP ini dulu.", "OK");
                return;
            }

            if (!await MintaIzinBluetoothAsync())
            {
                _aktif.IsToggled = false;
                return;
            }

            PrintPrefs.Aktif = true;

#if ANDROID
            await MintaBebasHematBateraiAsync();
            Platforms.Android.PrintForegroundService.Mulai();
#endif
        }
        else
        {
            PrintPrefs.Aktif = false;

#if ANDROID
            Platforms.Android.PrintForegroundService.Berhenti();
#endif
        }

        TampilkanStatus();
    }

#if ANDROID
    // Tanpa pengecualian hemat baterai, Android membekukan polling saat HP menganggur
    // dan label baru tercetak setelah HP dibuka.
    private async Task MintaBebasHematBateraiAsync()
    {
        try
        {
            var ctx = global::Android.App.Application.Context;
            var pm = (global::Android.OS.PowerManager?)ctx.GetSystemService(global::Android.Content.Context.PowerService);
            var paket = ctx.PackageName;

            if (pm is null || paket is null) return;
            if (pm.IsIgnoringBatteryOptimizations(paket)) return;

            var lanjut = await DisplayAlert("Hemat baterai",
                "Supaya label langsung tercetak walau layar mati, HP perlu mengizinkan app ini "
                + "berjalan tanpa dibatasi hemat baterai.", "Buka pengaturan", "Nanti");

            if (!lanjut) return;

            var intent = new global::Android.Content.Intent(
                global::Android.Provider.Settings.ActionRequestIgnoreBatteryOptimizations,
                global::Android.Net.Uri.Parse("package:" + paket));

            intent.AddFlags(global::Android.Content.ActivityFlags.NewTask);
            ctx.StartActivity(intent);
        }
        catch (Exception)
        {
            // Beberapa ROM menolak intent ini -- bukan penghalang, service tetap jalan.
        }
    }
#endif

    // Test print TIDAK lewat antrian: byte TSPL dirakit di sini lalu dikirim langsung,
    // supaya admin bisa memastikan printer & roll benar sebelum ada job sungguhan.
    private async Task TestPrintAsync()
    {
        if (string.IsNullOrWhiteSpace(PrintPrefs.PrinterMac))
        {
            await DisplayAlert("Test print", "Pilih printer Bluetooth dulu.", "OK");
            return;
        }

        var contoh = new ThreadLabelPayload
        {
            Kind = "SPLIT",
            Qr = "TS:SP-000000",
            ConeCode = "SP-000000",
            ColorCode = "TEST",
            ColorName = "TES CETAK",
            Brand = "Terakarsa",
            ThreadType = "Poly",
            ConeSize = "BESAR",
            WeightGram = 123,
            Copies = 1
        };

        var tspl = TsplBuilder.BuildThreadLabel(contoh);

#if ANDROID
        using var printer = new Platforms.Android.BluetoothPrinter();
        var (ok, error) = printer.Kirim(tspl);

        PrintLog.Tulis(ok ? "Test print terkirim." : $"Test print GAGAL — {error}");
        await DisplayAlert("Test print", ok ? "Label uji terkirim ke printer." : error, "OK");
#else
        await DisplayAlert("Test print", "Hanya tersedia di Android.", "OK");
#endif
    }
}

#if ANDROID
// Izin runtime Bluetooth Android 12+ (BLUETOOTH_CONNECT & BLUETOOTH_SCAN).
public class IzinBluetooth : Permissions.BasePlatformPermission
{
    public override (string androidPermission, bool isRuntime)[] RequiredPermissions => new[]
    {
        (global::Android.Manifest.Permission.BluetoothConnect, true),
        (global::Android.Manifest.Permission.BluetoothScan, true)
    };
}
#endif

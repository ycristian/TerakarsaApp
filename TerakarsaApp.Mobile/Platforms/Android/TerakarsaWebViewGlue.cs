using Android.Content;
using Android.Runtime;
using Android.Net.Http;
using Android.Webkit;
using AndroidX.Core.Content;
using Java.Interop;
using TerakarsaApp.Mobile.Services;
using AWebView = Android.Webkit.WebView;

namespace TerakarsaApp.Mobile.Platforms.Android;

// Prompt 76: glue WebView Android.
//
// MAUI WebView dipakai sebagai wadah, tapi WebViewClient & WebChromeClient-nya
// DIGANTI karena app butuh tiga hal yang tidak disediakan MAUI:
//   1. OnReceivedSslError  -> menerima sertifikat self-signed server LOKAL HANYA
//      kalau fingerprint SHA-256-nya cocok dengan yang tersimpan di Setting.
//   2. OnPermissionRequest -> memberi izin kamera ke web (scan QR label benang).
//   3. OnShowFileChooser   -> <input type=file capture> (foto SKU) bisa memakai
//      kamera/galeri.
//
// Konsekuensi yang diterima: event Navigating/Navigated milik MAUI TIDAK dipakai
// (halaman memakai event di kelas ini). Source tetap diatur lewat MAUI WebView.
public class TerakarsaWebViewClient : WebViewClient
{
    private readonly Action<string> _onPageFinished;

    public TerakarsaWebViewClient(Action<string> onPageFinished)
    {
        _onPageFinished = onPageFinished;
    }

    public override void OnPageFinished(AWebView? view, string? url)
    {
        base.OnPageFinished(view, url);
        if (!string.IsNullOrEmpty(url)) _onPageFinished(url!);
    }

    // JANGAN pernah memanggil handler.Proceed() tanpa cek fingerprint.
    public override void OnReceivedSslError(AWebView? view, SslErrorHandler? handler, SslError? error)
    {
        if (handler is null || error is null)
        {
            handler?.Cancel();
            return;
        }

        if (BolehLanjut(error)) handler.Proceed();
        else handler.Cancel();
    }

    private static bool BolehLanjut(SslError error)
    {
        var hostLokal = ServerResolver.HostDari(AppPrefs.LocalBaseUrl);
        if (string.IsNullOrEmpty(hostLokal)) return false;

        // Hanya untuk host server lokal; alamat publik tetap validasi normal.
        var hostError = ServerResolver.HostDari(error.Url);
        if (!string.Equals(hostError, hostLokal, StringComparison.OrdinalIgnoreCase)) return false;

        // SslCertificate.X509Certificate baru ada di API 29+. Di Android 8/9,
        // sertifikat server lokal harus dipasang di trust store perangkat (kalau
        // dipercaya, error SSL ini tidak muncul sama sekali). Lihat README.
        if (!OperatingSystem.IsAndroidVersionAtLeast(29)) return false;

        var cert = error.Certificate?.X509Certificate;
        if (cert is null) return false;

        try
        {
            var der = cert.GetEncoded();
            if (der is null) return false;

            var sidik = ServerResolver.SidikJari(der);
            return string.Equals(sidik, AppPrefs.LocalCertSha256, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception)
        {
            return false;
        }
    }
}

public class TerakarsaWebChromeClient : WebChromeClient
{
    private readonly Context _context;
    private readonly Func<Task<bool>> _mintaIzinKamera;
    private readonly Action<IValueCallback?> _bukaPemilihFile;

    public TerakarsaWebChromeClient(Context context, Func<Task<bool>> mintaIzinKamera,
        Action<IValueCallback?> bukaPemilihFile)
    {
        _context = context;
        _mintaIzinKamera = mintaIzinKamera;
        _bukaPemilihFile = bukaPemilihFile;
    }

    // Web minta kamera (pemindai QR). Izin Android diminta lebih dulu; kalau ditolak,
    // permintaan web juga ditolak supaya halaman bisa menampilkan pesannya sendiri.
    public override void OnPermissionRequest(PermissionRequest? request)
    {
        if (request is null) return;

        var minta = request.GetResources();
        if (minta is null || !minta.Contains(PermissionRequest.ResourceVideoCapture))
        {
            request.Deny();
            return;
        }

        var sudah = ContextCompat.CheckSelfPermission(_context, global::Android.Manifest.Permission.Camera)
                    == global::Android.Content.PM.Permission.Granted;

        if (sudah)
        {
            request.Grant(new[] { PermissionRequest.ResourceVideoCapture });
            return;
        }

        // Minta izin Android dulu, lalu jawab permintaan web di thread UI.
        _ = Task.Run(async () =>
        {
            var diberi = await _mintaIzinKamera();

            MainThread.BeginInvokeOnMainThread(() =>
            {
                if (diberi) request.Grant(new[] { PermissionRequest.ResourceVideoCapture });
                else request.Deny();
            });
        });
    }

    public override bool OnShowFileChooser(AWebView? webView, IValueCallback? filePathCallback,
        FileChooserParams? fileChooserParams)
    {
        _bukaPemilihFile(filePathCallback);
        return true;
    }
}

// Dipasang dari halaman WebView (shared code) lewat handler MAUI.
public static class WebViewGlue
{
    private static IValueCallback? _fileCallback;

    public static void Pasang(AWebView view, Context context, Action<string> onPageFinished)
    {
        var pengaturan = view.Settings;
        pengaturan.JavaScriptEnabled = true;
        pengaturan.DomStorageEnabled = true;          // localStorage: tempat token disuntik
        pengaturan.MediaPlaybackRequiresUserGesture = false;   // kamera scan boleh mulai sendiri
        pengaturan.AllowFileAccess = true;

        view.SetWebViewClient(new TerakarsaWebViewClient(onPageFinished));
        view.SetWebChromeClient(new TerakarsaWebChromeClient(context, MintaIzinKameraAsync, BukaPemilihFile));
    }

    private static async Task<bool> MintaIzinKameraAsync()
    {
        var status = await Permissions.RequestAsync<Permissions.Camera>();
        return status == PermissionStatus.Granted;
    }

    // Pemilih file sederhana: FilePicker MAUI (galeri/berkas). Kamera tetap bisa
    // dipakai web lewat getUserMedia (scan QR) -- yang ini khusus <input type=file>.
    private static void BukaPemilihFile(IValueCallback? callback)
    {
        _fileCallback = callback;

        _ = Task.Run(async () =>
        {
            global::Android.Net.Uri[]? hasil = null;

            try
            {
                var berkas = await MainThread.InvokeOnMainThreadAsync(async () =>
                    await FilePicker.Default.PickAsync(new PickOptions
                    {
                        PickerTitle = "Pilih foto",
                        FileTypes = FilePickerFileType.Images
                    }));

                if (berkas is not null)
                {
                    var uri = global::Android.Net.Uri.FromFile(new Java.IO.File(berkas.FullPath));
                    if (uri is not null) hasil = new[] { uri };
                }
            }
            catch (Exception)
            {
                hasil = null;
            }

            MainThread.BeginInvokeOnMainThread(() =>
            {
                // WebView menunggu jawaban: kalau null pun HARUS dikirim, kalau tidak
                // <input type=file> jadi macet dan tidak bisa dibuka lagi.
                _fileCallback?.OnReceiveValue(hasil);
                _fileCallback = null;
            });
        });
    }
}

using Android.App;
using Android.Content.PM;
using Android.OS;

namespace TerakarsaApp.Mobile;

// ScreenOrientation = FullSensor (bukan Unspecified bawaan MAUI): app ikut sensor di
// KEEMPAT arah dan TIDAK terhalang kunci rotasi sistem. Tanpa ini, tablet yang
// auto-rotate-nya dimatikan -- lumrah di tablet kerja -- tetap menampilkan portrait
// walau fisiknya landscape, padahal module Cutting dirancang untuk tablet landscape
// ~1024px (dua kolom di Buat Hamparan; lihat cutting.css). HP tetap bisa portrait
// karena FullSensor mengizinkan portrait juga.
//
// ConfigurationChanges sudah mencakup Orientation/ScreenSize/ScreenLayout, jadi rotasi
// ditangani di proses yang sama -- WebView TIDAK dimuat ulang saat tablet diputar,
// sehingga isi form Buat Hamparan yang sedang diisi tidak hilang.
[Activity(Theme = "@style/Maui.SplashTheme", MainLauncher = true, LaunchMode = LaunchMode.SingleTop,
    ScreenOrientation = ScreenOrientation.FullSensor,
    ConfigurationChanges = ConfigChanges.ScreenSize | ConfigChanges.Orientation | ConfigChanges.UiMode | ConfigChanges.ScreenLayout | ConfigChanges.SmallestScreenSize | ConfigChanges.Density)]
public class MainActivity : MauiAppCompatActivity
{
}

# Prompt 76 — App Android "Terakarsa": MAUI Shell, Login, Pilih Tujuan, WebView, Dua Alamat Server

Dijalankan SETELAH Prompt 75. Proyek baru di solution; tidak menyentuh Client/API kecuali
yang disebut di §5.

## Tujuan

App Android yang membungkus web TMOS yang sudah ada (WebView), dengan login native, pilihan
tujuan setelah login, dan otomatis memakai alamat server lokal saat di jaringan pabrik.
Print service Bluetooth ditambahkan di Prompt 77 — sediakan tempatnya di menu Setting.

## 1. Proyek

- `TerakarsaApp.Mobile` — .NET MAUI, target **Android saja** (`net10.0-android`; kalau
  template MAUI untuk .NET 10 belum stabil di mesin ini, pakai `net9.0-android` dan catat).
  Tambahkan ke `TerakarsaApp.slnx`. Reference `TerakarsaApp.Shared`.
- Kalau workload `maui-android` belum terpasang: jalankan `dotnet workload install maui-android`
  dan catat di ringkasan. Build Mobile tidak boleh membuat `dotnet build TerakarsaApp.slnx`
  gagal di mesin tanpa workload — kalau perlu, exclude Mobile dari build default solution
  dan build terpisah: `dotnet build TerakarsaApp.Mobile -v q`.
- Package id `id.terakarsa.app`, nama "Terakarsa", icon sederhana huruf T (SVG di
  `Resources/AppIcon`), warna aksen `#0f766e`, minimum Android 8.0 (API 26).

## 2. Alamat server (dua alamat)

`Preferences`: `LocalBaseUrl` (default kosong, mis. `https://192.168.1.10`), `PublicBaseUrl`
(default `https://app.terakarsa.id`), `UrlMode` = `Auto` | `Local` | `Public`.

Service `ServerResolver`:
- Mode Auto: saat app start, saat `Connectivity.ConnectivityChanged`, dan saat resume →
  `GET {LocalBaseUrl}/api/health` timeout 1500 ms. OK → aktif = lokal; gagal → publik.
  Hasil disimpan sebagai `ActiveBaseUrl`, ditampilkan sebagai badge kecil di layar pilih
  tujuan dan Setting ("Lokal" / "Internet").
- Mode Local/Public: paksa.
- Ganti `ActiveBaseUrl` saat WebView sedang terbuka → reload halaman yang sama di origin
  baru setelah token disuntik ulang (§4).

**Sertifikat lokal (opsi 1)**: server lokal memakai sertifikat self-signed. Buat
`HttpClient` Android (`AndroidMessageHandler`) dan WebView (`WebViewClient.OnReceivedSslError`)
**hanya** menerima sertifikat yang cocok dengan fingerprint yang tersimpan di Setting
(`LocalCertSha256`), dan hanya untuk host `LocalBaseUrl`. Jangan terima semua sertifikat.
Di Setting ada tombol "Ambil fingerprint dari server lokal sekarang" yang membaca sertifikat
dari koneksi (TOFU) dan menampilkannya untuk disetujui. Alamat publik tetap validasi normal.

Endpoint `GET api/health` di API: kalau belum ada, tambahkan (anonymous, balas
`{ status:"ok", server:"<nama mesin>" }`) — ini satu-satunya perubahan di API.

## 3. Login native

- Layar login: username, password, tombol masuk, badge alamat aktif, link ke Setting.
- Panggil endpoint login yang sama dengan web (telusuri `AuthController` untuk bentuk
  request/response dan refresh). Simpan access + refresh token di `SecureStorage`.
- Refresh token dengan pola yang sama seperti Client (rotasi manual). Kalau refresh gagal →
  kembali ke layar login.
- Ambil daftar module user (endpoint yang dipakai Client untuk menu dinamis).

## 4. Pilih tujuan & WebView

Layar **Pilih tujuan**, kartu besar, hanya tampil yang modulnya dimiliki user:

| Kartu | Syarat | Route web |
|---|---|---|
| Dashboard Utama | user punya module apa pun selain INV_THREAD/TNI_PDH (telusuri kode module dashboard) | `/` |
| Admin Gudang | `INV_THREAD` | `/gudang/benang` |
| PO TNI | `TNI_PDH` | route landing module TNI (telusuri) |

Kalau hanya satu kartu → langsung buka tanpa layar pilih. Tombol "Ganti akun" (logout)
dan ikon Setting di pojok.

WebView (`Android.Webkit.WebView` lewat MAUI `WebView` + handler, atau langsung platform
view — pilih yang paling sedikit kode):
- Sebelum load, suntik token ke `localStorage` origin aktif dengan **nama key yang sama**
  yang dipakai Client (telusuri JS interop auth di `TerakarsaApp.Client`), supaya web
  langsung dalam keadaan login. Lakukan lewat `EvaluateJavascript` setelah `about:blank`
  di origin tersebut, atau lewat `WebViewAssetLoader`/cookie — pilih yang terbukti jalan,
  uji di emulator.
- Logout di web → app menangkap (deteksi redirect ke `/login`) → kembali ke layar login app.
- Izin kamera: `WebChromeClient.OnPermissionRequest` → grant `RESOURCE_VIDEO_CAPTURE`
  setelah izin Android `CAMERA` diberikan (minta saat pertama dibutuhkan). Izin
  `android.permission.CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE` di manifest.
- Tombol back Android: `GoBack()` kalau bisa, kalau tidak → ke layar pilih tujuan.
- File upload dari web (foto SKU, `<input type=file capture>`): implementasikan
  `WebChromeClient.OnShowFileChooser` supaya kamera/galeri bisa dipakai.
- Pull-to-refresh tidak perlu.

## 5. Setting

Halaman Setting: alamat lokal, alamat publik, mode (Auto/Lokal/Internet), fingerprint
sertifikat lokal (+ tombol ambil), tombol "Uji koneksi" (menampilkan hasil lokal & publik),
versi app, **bagian "Print Service" placeholder** (teks "Tersedia di pembaruan berikutnya").

## 6. Build APK

- Signing: buat keystore `terakarsa-release.keystore` lewat `keytool` dengan password dari
  file `TerakarsaApp.Mobile/signing.local.json` (gitignored; sertakan `signing.example.json`).
- Perintah publish ditulis di `TerakarsaApp.Mobile/README.md`:
  `dotnet publish TerakarsaApp.Mobile -c Release -f net10.0-android -p:AndroidPackageFormat=apk ...`
  → hasil `.apk` siap sideload. README juga memuat cara install (Enable unknown sources),
  cara mengisi alamat lokal, dan cara ambil fingerprint.
- Versi: `ApplicationDisplayVersion` 1.0, `ApplicationVersion` 1.

## 7. Verifikasi

`dotnet build TerakarsaApp.Mobile -v q` sukses. Kalau emulator Android tersedia di mesin
ini: jalankan, login, pastikan WebView membuka landing dalam keadaan login. Kalau tidak
tersedia, catat bahwa pengujian perangkat dilakukan owner.

## Yang TIDAK boleh dilakukan

- Jangan ubah UI web / Client (selain tidak ada). Jangan ubah mekanisme auth API.
- Jangan terima sertifikat SSL sembarangan (hanya fingerprint tersimpan, hanya host lokal).

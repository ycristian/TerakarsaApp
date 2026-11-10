# Prompt 86 — App Android: Mode Stasiun dengan kode login terkunci

Lanjutan Prompt 76 (app pembungkus WebView) dan Prompt 85 (kode login terkunci). Prompt 85
**harus sudah terpasang** di server: semua logika klaim, peringatan `DIPAKAI|`, dan login
ulang otomatis ada di halaman web `/station`. App hanya menyimpan kode + identitas
perangkat, lalu menyuntikkannya ke WebView. Tidak ada perubahan API, SQL, atau web di
prompt ini.

Project: `TerakarsaApp.Mobile` (di luar `TerakarsaApp.slnx`, lihat README-nya).

## 0. Yang diinginkan

- Perangkat stasiun (1 stasiun = 1 perangkat tetap) memakai app ini dalam **Mode
  Stasiun**: app langsung membuka `/station` tanpa login user dan tanpa layar pilih tujuan.
- Kode login stasiun (kode terkunci 10 karakter dari Kelola Stasiun) disimpan di
  **Pengaturan**, bisa diketik atau **di-scan dari QR**, dan bisa diedit owner kalau kodenya
  di-refresh.
- Perangkat tidak bisa "keluar" dari stasiun lewat app: kalau token hilang, web login ulang
  sendiri memakai kode dari Pengaturan (aturan "mode app" di Prompt 85 §6).

## 1. `Services/AppPrefs.cs`

Tambah (Preferences biasa, bukan SecureStorage — konsisten dengan alamat server dan harus
bisa diedit):

- `StationMode` (bool, default `false`).
- `StationLoginCode` — dinormalisasi: trim, buang spasi/`-`, huruf besar.
- `StationDeviceName` — default `"{DeviceInfo.Manufacturer} {DeviceInfo.Model}"`; kosong →
  kembali ke default.
- `StationDeviceId` — GUID `"N"`, dibuat sekali saat pertama dibaca, tidak bisa diedit.
  Terpisah dari `PrintPrefs.DeviceCode` (print service punya siklus daftar ulang sendiri).
- Helper validasi kode: tepat 10 karakter `[A-Z0-9]`. Kode sekali pakai 5 huruf **ditolak**
  dengan pesan *"Pakai kode login terkunci (10 karakter) dari menu Kelola Stasiun. Kode
  pairing 5 huruf hanya berlaku sekali."*

## 2. `Pages/SettingPage.cs` — bagian "Mode Stasiun"

Bagian baru di atas "Print Service":

- Switch **Mode Stasiun**.
- Isian **Kode login stasiun** + tombol **Scan QR**.
- Isian **Nama perangkat** (mis. "Tablet Sewing 1") — nama ini yang muncul di peringatan
  `DIPAKAI|` di perangkat lain dan di daftar Kelola Stasiun.
- Keterangan kecil: ID perangkat (8 karakter pertama) untuk diagnosa.
- Disimpan oleh tombol **Simpan** yang sudah ada (`SimpanAsync`). Mode Stasiun aktif dengan
  kode tidak valid → tolak simpan dengan pesan validasi di §1.
- Setelah simpan, perubahan Mode Stasiun langsung berlaku: ganti root window ke
  `StationHomePage` (aktif) atau kembali ke `LoginPage` (nonaktif) — tidak perlu tutup-buka
  app.

## 3. Scan QR di Pengaturan

- Layar scanner native sederhana (kamera penuh + tombol batal). Library: pilih satu yang
  **berhasil di-build untuk `net10.0-android`** dengan MAUI versi project ini (kandidat:
  `ZXing.Net.Maui.Controls` atau scanner berbasis ML Kit seperti
  `BarcodeScanning.Native.Maui`). Laporkan library dan versi yang dipakai. Registrasi di
  `MauiProgram`.
- Izin kamera sudah ada di `AndroidManifest.xml`; minta saat runtime lewat
  `Permissions.RequestAsync<Permissions.Camera>()` sebelum membuka scanner.
- Isi QR yang diterima:
  - URL yang mengandung `/station/` → ambil segmen terakhir (QR di modal Kode Login
    Prompt 85 berisi `{PublicBaseUrl}/station/{kode}`);
  - selain itu → teks mentah.
  Lalu normalisasi + validasi seperti §1.
- Hasil scan **hanya mengisi** isian kode; tidak langsung disimpan. Owner tetap menekan
  Simpan, supaya salah scan (mis. QR bundle) tidak mengganti kode stasiun. Hasil tidak valid
  → pesan, isian tidak berubah.

## 4. Startup — `App.xaml.cs`

- `StationMode` aktif dan kode valid → root `NavigationPage(new StationHomePage(...))`;
  `MuatTokenTersimpanAsync`/`MuatModuleAsync` (login JWT) **tidak dijalankan**.
  `_resolver.RefreshAsync()` tetap jalan seperti sekarang.
- Selain itu → alur lama persis (LoginPage → TujuanPage).

## 5. `Pages/StationHomePage.cs` (baru, code-only seperti layar lain)

- Judul "Mode Stasiun", badge alamat aktif (Lokal/Internet), nama perangkat.
- Tombol **Buka Stasiun** dan **Pengaturan**.
- Saat pertama tampil setelah app dibuka, langsung membuka WebView stasiun (operator tidak
  perlu menekan apa pun). Kembali ke layar ini hanya lewat tombol back di root web.

## 6. WebView stasiun — `Pages/WebPage.cs`

Boleh menambah mode/parameter ke `WebPage`, atau kelas baru yang memakai glue yang sama
(`Platforms.Android.WebViewGlue`) — pilih yang paling sedikit menduplikasi. **Perilaku
WebPage untuk tujuan lama (Dashboard, Gudang, TNI) tidak boleh berubah.**

Untuk mode stasiun:

- Urutan muat sama dengan sekarang (buka origin aktif → suntik localStorage → arahkan ke
  route), route `/station`.
- Yang disuntik (nama key harus persis, dibaca web Prompt 85):
  `stationLockCode` = `AppPrefs.StationLoginCode`,
  `stationDeviceId` = `AppPrefs.StationDeviceId`,
  `stationDeviceName` = `AppPrefs.StationDeviceName`.
  **Tidak** menyuntik `authToken`/`refreshToken`, dan **tidak** menyentuh `stationToken`
  maupun `stationLockCodeUsed` (dikelola web).
- Disuntik ulang setiap kali halaman dimuat ulang — termasuk saat `ServerResolver.Changed`
  memindah origin (localStorage per origin; di origin baru web akan klaim ulang sendiri,
  dan karena `stationDeviceId` sama, tanpa peringatan).
- Deteksi "URL mengandung /login → logout app" **tidak berlaku** di mode stasiun.
- Tombol back Android: mundur di dalam web dulu; kalau tidak bisa → kembali ke
  `StationHomePage`.

## 7. Yang TIDAK boleh dilakukan

- Mengubah API, SQL, atau halaman web (semua sudah di Prompt 85).
- Melakukan klaim stasiun secara native atau menyimpan `stationToken` di app.
- Mengubah alur login/tujuan/print service yang sudah ada.
- Mendaftarkan project ke `TerakarsaApp.slnx`.
- Mengunci Pengaturan dengan PIN (tidak diminta; kalau perlu, prompt terpisah).

## 8. Verifikasi

- `dotnet build TerakarsaApp.Mobile -v q` lolos (dan build lama
  `dotnet build TerakarsaApp.slnx -v q` tetap lolos).
- Tambah bagian **"Mode Stasiun (Prompt 86)"** di `TerakarsaApp.Mobile/README.md`: cara
  mengisi kode (ketik/scan), arti nama perangkat, apa yang terjadi saat kode di-refresh
  admin, dan cara keluar dari Mode Stasiun (matikan switch di Pengaturan).
- Pengujian di perangkat dilakukan owner. Tulis checklist uji di laporan, minimal:
  1. Scan QR Kode Login → isian terisi; Simpan → app langsung masuk `/station`.
  2. Tutup-buka app → langsung di `/station` tanpa login.
  3. "Sambungkan ulang" di web → kembali masuk tanpa peringatan.
  4. Perangkat kedua dengan kode yang sama → peringatan `DIPAKAI|` menyebut nama perangkat
     pertama.
  5. Admin refresh kode → perangkat tetap jalan; setelah token hilang muncul pesan "kode di
     Pengaturan app tidak berlaku"; isi kode baru → masuk lagi.
  6. Pindah jaringan (Lokal ↔ Internet) → stasiun tetap terbuka setelah muat ulang.
  7. Matikan Mode Stasiun → app kembali ke layar login biasa.

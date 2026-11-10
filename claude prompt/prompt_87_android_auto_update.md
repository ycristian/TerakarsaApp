# Prompt 87 — App Android: update otomatis dari share folder

Lanjutan Prompt 76 (app pembungkus WebView) dan Prompt 86 (Mode Stasiun). Owner menaruh APK
baru di share folder; app di setiap HP/tablet mendeteksi versi baru dan menawarkan update
sendiri, tanpa kabel USB atau kirim file manual.

Project: `TerakarsaApp.Mobile` (di luar `TerakarsaApp.slnx`, lihat README-nya) +
`TerakarsaApp.API`. **Tidak ada perubahan SQL** di prompt ini.

## 0. Yang diinginkan

- Owner build APK release, lalu menaruhnya di share folder (path diatur di appsettings API).
- App memeriksa versi terbaru saat dibuka; kalau ada yang lebih baru → dialog
  "Update tersedia" → download → layar install Android terbuka.
- Berlaku untuk mode biasa (login user) maupun Mode Stasiun (tanpa login).

### Keputusan desain (sudah dibahas dengan owner)

- **HP tidak membaca share folder langsung.** Android tidak punya klien SMB bawaan dan setiap
  perangkat harus menyimpan kredensial jaringan. API yang membaca folder itu dan
  menyajikannya lewat HTTP.
- **Konfirmasi "Install" oleh user tetap wajib** di setiap update (aturan Android; install
  senyap hanya bisa di perangkat MDM/device owner — di luar cakupan).
- **Semua APK update wajib ditandatangani keystore release yang sama**
  (`signing.local.json`) dan `ApplicationVersion` harus naik. Perangkat yang terpasang build
  Debug (kunci debug) harus di-uninstall sekali lalu pasang release; setelah itu update
  otomatis jalan normal.
- **Endpoint tanpa login** (`[AllowAnonymous]`): Mode Stasiun tidak punya JWT, dan app perlu
  bisa update walau token kedaluwarsa. APK bukan rahasia (isinya hanya pembungkus WebView).

## 1. Konvensi nama file APK

`terakarsa-<versionCode>-<versionName>.apk`, contoh `terakarsa-3-1.2.apk`.

- `versionCode` = `ApplicationVersion` di csproj (integer, yang dibandingkan Android).
- `versionName` = `ApplicationDisplayVersion` (hanya untuk tampilan).
- File di folder yang namanya tidak cocok pola → diabaikan (boleh ada file lain/arsip).
- Versi terbaru = `versionCode` terbesar. Versi lama tidak perlu dihapus (riwayat/rollback
  manual).
- Opsional: `terakarsa-<versionCode>-<versionName>.txt` di sebelahnya = catatan rilis
  (teks bebas, ditampilkan di dialog update).

## 2. Script rilis — `TerakarsaApp.Mobile/publish-apk.ps1` (baru)

Supaya owner tidak perlu ingat konvensi di §1:

1. Baca `ApplicationVersion` + `ApplicationDisplayVersion` dari csproj.
2. Tolak kalau `signing.local.json` tidak ada (APK tanpa kunci release tidak bisa jadi update).
3. Tolak kalau di folder tujuan sudah ada APK dengan `versionCode` ≥ versi csproj — pesan:
   naikkan `ApplicationVersion` dulu.
4. `dotnet publish -c Release -f net10.0-android`, output ke
   `<repo_root>\publish\TerakarsaApp.Mobile` (konvensi deploy repo ini).
5. Copy APK yang sudah ditandatangani (`*-Signed.apk`) ke folder tujuan dengan nama §1.
6. Parameter `-Folder` (default: path share folder owner), `-Notes "..."` → tulis file `.txt`.

## 3. API

### Konfigurasi — `appsettings.json`

```json
"MobileUpdate": {
  "ApkFolder": ""
}
```

Kosong → fitur update nonaktif (endpoint versi mengembalikan 204, app diam saja). Path boleh
lokal (`D:\Terakarsa\apk`) atau UNC (`\\AGS\share\apk`). Catat di laporan: identitas app pool
IIS API harus punya akses **baca** ke folder itu kalau UNC.

### `Services/MobileUpdateService.cs` (baru)

- Scan folder, parse nama file §1, ambil versionCode terbesar.
- Hitung SHA-256 file (cache per path + ukuran + `LastWriteTimeUtc`, jangan hitung ulang
  tiap request).

### `Controllers/MobileUpdateController.cs` (baru, `[AllowAnonymous]`)

- `GET api/mobile-update/android` → `MobileUpdateInfoDto`
  (`VersionCode`, `VersionName`, `FileName`, `SizeBytes`, `Sha256`, `Notes`) atau 204.
- `GET api/mobile-update/android/apk` → stream file terbaru,
  content-type `application/vnd.android.package-archive`, dukung range request
  (`enableRangeProcessing`) supaya download di jaringan lemah bisa dilanjutkan.
- Jangan pernah menerima nama file dari client (tidak ada path traversal).

DTO di `TerakarsaApp.Shared/MobileUpdate/MobileUpdateModels.cs`.

## 4. App — pemeriksaan update

### `Services/UpdateService.cs` (baru)

- Panggil endpoint versi lewat `ServerResolver.BuatHttpClient(ActiveBaseUrl)` (ikut aturan
  sertifikat lokal yang sudah ada).
- Bandingkan dengan `AppInfo.BuildString` (versionCode app terpasang).
- Download ke `FileSystem.CacheDirectory`, tampilkan progres (persen), verifikasi SHA-256
  → tidak cocok: hapus file, pesan "File update rusak, coba lagi".
- Gagal jaringan/server → diam (tidak mengganggu pemakaian), kecuali dipicu manual dari
  Pengaturan.

### Kapan diperiksa

- Saat app dibuka (setelah `_resolver.RefreshAsync()`), di **kedua** alur `App.xaml.cs`
  (login biasa dan Mode Stasiun). Tidak memblokir: halaman tetap jalan, dialog muncul di atas.
- Tombol **Cek update** di `SettingPage` (bagian baru "Tentang aplikasi": versi terpasang +
  tombol). Di sini hasil apa pun ditampilkan ("Sudah versi terbaru", pesan error, dll).
- "Nanti" → tidak ditanya lagi sampai app dibuka ulang.

### Dialog

"Update tersedia: versi {VersionName} (sekarang {versi terpasang})" + catatan rilis kalau
ada + tombol **Update** / **Nanti**.

## 5. App — memasang APK (Android)

- `AndroidManifest.xml`: tambah `REQUEST_INSTALL_PACKAGES` + `<provider>` FileProvider
  (`androidx.core.content.FileProvider`, authority `${applicationId}.fileprovider`) dengan
  `Resources/xml/file_paths.xml` yang hanya membuka cache dir. Perbarui komentar izin di
  bagian atas manifest.
- Sebelum memasang: `PackageManager.CanRequestPackageInstalls()` false → jelaskan singkat
  ("Izinkan Terakarsa memasang update — cukup sekali") lalu buka
  `Settings.ActionManageUnknownAppSources` untuk package ini; setelah kembali, lanjutkan.
- Pasang lewat `Intent.ActionView` + URI FileProvider + `GrantReadUriPermission`
  (cukup; `PackageInstaller` session tidak perlu).
- Kode Android di `Platforms/Android/ApkInstaller.cs` (baru), dipanggil dari `UpdateService`
  lewat `#if ANDROID` seperti pola `WebViewGlue`.

## 6. Yang TIDAK boleh dilakukan

- Akses SMB/share folder langsung dari app, atau menyimpan kredensial jaringan di app.
- Install senyap / meminta device owner.
- Update paksa yang memblokir app (selalu ada "Nanti").
- Menerima nama/path file dari client di API.
- Mengubah SQL, halaman web, alur login/tujuan/Mode Stasiun/print service yang sudah ada.
- Mendaftarkan `TerakarsaApp.Mobile` ke `TerakarsaApp.slnx`.

## 7. Verifikasi

- `dotnet build TerakarsaApp.slnx -v q` dan `dotnet build TerakarsaApp.Mobile -v q` lolos.
- Tambah bagian **"Update otomatis (Prompt 87)"** di `TerakarsaApp.Mobile/README.md`: cara
  rilis (naikkan `ApplicationVersion` → jalankan `publish-apk.ps1`), konvensi nama file,
  syarat keystore sama, dan perangkat ber-build Debug harus uninstall sekali.
- Checklist uji owner di laporan, minimal:
  1. Folder kosong / `ApkFolder` kosong → app jalan normal tanpa dialog.
  2. Taruh APK versi lebih tinggi → buka app → dialog muncul → Update → izin "sumber tidak
     dikenal" diminta sekali → layar install → app terbuka dengan versi baru.
  3. Buka app lagi → tidak ada dialog (sudah versi terbaru).
  4. "Nanti" → tidak muncul lagi sampai app dibuka ulang.
  5. Mode Stasiun → dialog juga muncul, `/station` tetap jalan di belakangnya.
  6. File APK diganti/rusak di tengah download → pesan "File update rusak".
  7. Pengaturan → Cek update → "Sudah versi terbaru".
  8. `publish-apk.ps1` tanpa menaikkan `ApplicationVersion` → ditolak.

## Belum diputuskan (isi sebelum dieksekusi)

- Path share folder untuk default `-Folder` di §2 dan `MobileUpdate:ApkFolder` di §3.

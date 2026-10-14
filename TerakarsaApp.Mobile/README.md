# App Android "Terakarsa" (Prompt 76–77)

Pembungkus **WebView** untuk web TMOS yang sudah ada — bukan UI baru. Yang native hanya:
login, pemilihan tujuan, pemilihan alamat server (lokal/internet), dan (Prompt 77)
print service Bluetooth.

- Package id: `id.terakarsa.app` · nama "Terakarsa" · minimum Android 8.0 (API 26)
- Target build: `net10.0-android` (Android saja)
- UI dibuat **code-only** (tanpa XAML): hanya 4 layar utilitas, tampilan sebenarnya ada di web.

## Build

Project ini **TIDAK didaftarkan di `TerakarsaApp.slnx`** supaya `dotnet build TerakarsaApp.slnx -v q`
(perintah build harian di CLAUDE.md) tidak gagal di mesin tanpa workload Android dan tidak
jadi lambat. Build terpisah:

```
dotnet build TerakarsaApp.Mobile -v q
```

Workload yang dibutuhkan: `android` + MAUI (di mesin dev sekarang sudah ada — paket
`android` 36.1.43 dan `maui-windows` 10.0.20 cukup untuk build `net10.0-android`).
Kalau di mesin lain gagal dengan pesan workload:

```
dotnet workload install maui-android
```

## APK untuk sideload

1. Buat keystore sekali saja:

```
keytool -genkeypair -v -keystore terakarsa-release.keystore -alias terakarsa ^
        -keyalg RSA -keysize 2048 -validity 10000
```

2. Salin `signing.example.json` → `signing.local.json` (gitignored), isi path keystore +
   password. File itu dibaca otomatis saat build Release.

3. Publish:

```
dotnet publish TerakarsaApp.Mobile -c Release -f net10.0-android -p:AndroidPackageFormat=apk
```

Hasil `.apk` ada di `TerakarsaApp.Mobile/bin/Release/net10.0-android/publish/`.

## Install di HP

1. Kirim `.apk` ke HP (USB / WhatsApp / Drive).
2. Buka file-nya; Android akan minta izin **"Install unknown apps"** untuk aplikasi
   pengirim — aktifkan, lalu Install.
3. Buka app → **Pengaturan server** (link di bawah tombol Masuk).

## Mengisi alamat server

- **Alamat lokal**: alamat WEB TMOS di jaringan pabrik, mis. `https://192.168.8.233`.
  Alamat API diturunkan otomatis dari alamat ini — aturannya sama dengan web di browser
  (`*.terakarsa.id` → `api.terakarsa.id`; selain itu host sama, port 5281 untuk http /
  7130 untuk https). Jadi **isi alamat web, bukan alamat API**.
- **Alamat publik**: `https://app.terakarsa.id` (default).
- **Mode**:
  - `Auto` (disarankan) — app mencoba alamat lokal dulu (timeout 1,5 detik) setiap kali
    dibuka, saat jaringan berubah, dan saat app kembali aktif. Tidak terjangkau → pakai
    alamat publik. Badge di layar menunjukkan "Lokal" atau "Internet".
  - `Lokal` / `Internet` — dipaksa.
- **Uji koneksi** menampilkan hasil kedua alamat sekaligus (`GET api/health`).

## Sertifikat server lokal (self-signed)

App **tidak menerima sertifikat sembarangan**. Untuk server lokal, app hanya menerima
sertifikat yang fingerprint SHA-256-nya sama dengan yang tersimpan di Pengaturan, dan
hanya untuk host alamat lokal. Alamat publik tetap diperiksa normal.

Cara mengisi: Pengaturan → **Ambil fingerprint dari server lokal** → app menampilkan
subject + masa berlaku + SHA-256 → tekan **Percayai** kalau benar (sekali saja; ulangi
kalau sertifikat server diganti). Bisa juga ditempel manual dari:

```
openssl s_client -connect 192.168.8.233:7130 </dev/null 2>/dev/null | openssl x509 -fingerprint -sha256 -noout
```

(format `AA:BB:...` boleh ditempel apa adanya — app membuang pemisahnya sendiri.)

**Catatan Android 8 & 9**: API untuk membaca sertifikat dari error SSL di WebView
(`SslCertificate.X509Certificate`) baru ada di Android 10. Di Android 8/9, pasang
sertifikat server lokal ke trust store perangkat (Settings → Security → Install
certificate); kalau sudah dipercaya perangkat, WebView tidak memunculkan error SSL dan
app jalan normal. Pemanggilan API (login) tetap memakai pinning fingerprint di semua versi.

## Perilaku app

- Login native memakai endpoint yang sama dengan web (`api/auth/login`, `api/auth/refresh`).
  Token disimpan di SecureStorage.
- **Pilih tujuan** hanya menampilkan kartu yang modulnya dimiliki user:
  Dashboard Utama (`/`), Admin Gudang (`/gudang/benang`, module `INV_THREAD`),
  PO TNI (`/tni`, module `TNI_PDH`). Kalau hanya satu, langsung dibuka.
- WebView dibuka dalam keadaan **sudah login**: token disuntik ke `localStorage`
  (`authToken` / `refreshToken` — nama key yang sama dengan web) sebelum app Blazor boot.
- Logout dari web (atau token ditolak) → app kembali ke layar login.
- Kamera untuk scan QR diteruskan ke web; izin Android diminta saat pertama dibutuhkan.
- `<input type="file">` (foto SKU) memakai pemilih berkas Android.
- Tombol back: mundur di dalam web dulu, baru keluar ke layar pilih tujuan.

## Pengujian

Build sudah diverifikasi di mesin dev (`dotnet build TerakarsaApp.Mobile -v q` sukses).
**Pengujian di perangkat/emulator dilakukan owner** — tidak ada emulator Android yang
berjalan di mesin ini saat seri 76–77 dikerjakan.

---

# Print Service Bluetooth (Prompt 77)

HP admin gudang bisa mencetak label 30×20 mm ke **Xprinter XP-P323B** lewat Bluetooth
klasik (SPP), memakai **antrian print job yang sama** dengan PrintService Windows. Admin
tetap menekan "Cetak label" di web; HP mengambil job yang dirutekan ke HP itu.

Layout label dirakit `TerakarsaApp.Printing.TsplBuilder` — library yang sama dengan
PrintService Windows, jadi label dari HP identik byte per byte dengan label dari PC.

## Sekali pasang

1. **Pairing printer di Android**: nyalakan printer → Settings → Bluetooth → pair
   "XP-P323B" (PIN biasanya `0000` atau `1234`). App hanya memakai printer yang sudah
   di-pairing, tidak melakukan pencarian sendiri.
2. **Di app**: Pengaturan → **Buka Print Service**.
   - Izinkan permintaan izin Bluetooth (Android 12+).
   - **Muat daftar printer** → pilih XP-P323B.
   - Isi nama device (mis. "HP Gudang Rina") → **Daftarkan HP ini**.
     App menyimpan `device_token` di SecureStorage; token itu hanya ditampilkan/dibuat
     di HP ini. Mendaftarkan ulang akan MENGGANTI token (cara mencabut HP yang hilang).
3. **Di web** (`/admin/printer`, menu Sistem → Printer & Routing, hanya Admin):
   ubah dropdown `THREAD_SKU_LABEL` dan `THREAD_SPLIT_LABEL` ke device HP tadi.
   Untuk kembali ke printer PC, ubah lagi ke "Label Bundle (TSC TTP-244 Pro)".
4. **Di app**: nyalakan switch **Aktif**. Android akan menawarkan pengecualian hemat
   baterai — terima, supaya label tetap tercetak saat layar mati.

## Uji cetak

- **Test print** di halaman Print Service mengirim satu label contoh LANGSUNG ke printer
  (tanpa antrian) — untuk memastikan printer, roll 30×20 mm, dan pairing benar.
- Uji lewat antrian: buka web di app → Stok Benang → Kembali & Timbang → simpan →
  **Cetak label**. Job masuk antrian, HP mengambilnya dalam ±3 detik, dan statusnya
  berubah jadi "Tercetak" di halaman web itu.

## Saat bermasalah

- Log 50 baris terakhir ada di halaman Print Service (job, keberhasilan, pesan error).
- Notifikasi "Terakarsa Print Service aktif · <printer>" harus ada selama switch Aktif.
- Jika log berbunyi **"Token device ditolak server — daftarkan ulang HP ini"**: device
  dihapus/di-nonaktifkan di server, atau HP lain memakai `device_code` yang sama.
  Tekan **Daftarkan HP ini** sekali lagi.
- Job gagal cetak akan dicoba ulang server maksimal 3 kali (aturan yang sama dengan
  PrintService Windows), lalu berstatus ERROR.
- Koneksi Bluetooth ditutup otomatis setelah 60 detik tanpa job; printer portabel
  mematikan radionya sendiri, jadi itu normal.

## Catatan teknis

- Poll 3 detik; melambat jadi 10 detik kalau layar sudah mati ≥ 5 menit.
- `JobTypes` dikirim KOSONG saat claim — route di server yang menentukan job mana milik
  HP ini, sehingga job type label baru tidak butuh update app.
- Job struk (`render_mode = TOKEN`) tidak bisa diarahkan ke HP: app hanya merakit TSPL.
  Server menolaknya di `SIS_PrintJobRoute_Manage`, dan dropdown web tidak menawarkannya.

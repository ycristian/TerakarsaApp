# Prompt 77 — App Android: Print Service Bluetooth (Xprinter XP-P323B), Registrasi Device

Dijalankan SETELAH Prompt 76. Prompt terakhir seri.

## Tujuan

HP admin gudang bisa mencetak label 30×20 mm ke printer portabel XP-P323B lewat
Bluetooth klasik (SPP), dengan antrian print job yang sama seperti PrintService Windows.
Admin cetak dari web seperti biasa; app di HP mengambil job yang di-route ke HP itu.

## 1. Library bersama `TerakarsaApp.Printing`

Buat class library baru `TerakarsaApp.Printing` (netstandard2.1 atau net10.0, tanpa
dependensi Windows) dan **pindahkan** `TsplBuilder.cs` (beserta model payload label yang
dipakainya) dari `TerakarsaApp.PrintService` ke sana. PrintService dan Mobile mereferensikan
library ini. Perilaku PrintService tidak berubah — hanya lokasi file. `EscPosRenderer`
tetap di PrintService (tidak dibutuhkan Mobile).

## 2. Database — `sql/inv/alter_77_print_devices_mobile.sql` (idempotent)

Tambahkan ke `print_devices`:
- `transport varchar(20) not null default 'WINDOWS'` CHECK IN ('WINDOWS','ANDROID_BT')
- `device_token varchar(64) null` (hanya ANDROID_BT, unik filtered)
- `last_seen_at datetime2 null`, `last_seen_info varchar(200) null` (nama printer BT, versi app)

`printer_name` untuk ANDROID_BT diisi nama/MAC printer Bluetooth (informasi saja).

SP:
- `SIS_PrintDevice_RegisterMobile` @DeviceCode, @DeviceName, @PrinterName, @UserId →
  upsert device ANDROID_BT, render_mode RAW_TSPL, buat `device_token` acak 48 karakter
  (hanya saat pertama; registrasi ulang mengganti token dan menampilkannya lagi). Hanya
  user dengan module `INV_THREAD` atau Admin.
- `SIS_PrintDevice_ListMobile` — device ANDROID_BT milik organisasi + route yang
  mengarah ke sana.
- `SIS_PrintJob_Claim` / `SIS_PrintJob_Report`: tambah parameter opsional `@DeviceId`.
  Kalau diisi → hanya klaim job yang `print_job_routes` mengarah ke device itu dan device
  `is_active = 1`, dan update `last_seen_at`. Jalur lama (tanpa @DeviceId, API key) tidak
  berubah.

## 3. API

- Header baru `X-Print-Device-Token`. Middleware/filter di `PrintController`: kalau header
  ini ada → cocokkan ke `print_devices.device_token` aktif → `@DeviceId`; kalau header
  `X-Print-Api-Key` → jalur lama. Keduanya tidak boleh dicampur dalam satu request.
- `POST api/print/devices/register-mobile` (`[Authorize]`, module INV_THREAD) → balas
  `device_token` sekali.
- `GET api/print/devices/mobile` (Admin) untuk halaman routing.
- `GET api/print/claim`/`report`/`render` menerima device token.

## 4. Client (web) — halaman kecil untuk routing

Di halaman admin printer yang sudah ada (kalau ada) atau halaman baru `/admin/printer`:
tabel `print_job_routes` dengan dropdown device per job_type, supaya owner memindahkan
`THREAD_SKU_LABEL` / `THREAD_SPLIT_LABEL` ke device HP tanpa SQL. Module: Admin saja
(module code printer yang sudah ada kalau ada; kalau tidak, `PRINT_ADMIN` di-seed).

## 5. Mobile — Setting → Print Service

- **Daftarkan HP ini**: input nama device (default "HP Gudang"), pilih printer dari daftar
  Bluetooth yang sudah di-pairing (`BluetoothAdapter.BondedDevices`), tombol Daftar →
  panggil register-mobile dengan token user → simpan `device_token` di `SecureStorage`.
- **Status**: Aktif/Nonaktif (switch), printer terpilih, koneksi (terhubung/terputus),
  job terakhir, log 50 baris terakhir.
- **Test print**: kirim TSPL contoh 30×20 langsung ke printer (tanpa antrian).
- Izin Android 12+: `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` (runtime); di bawah 12:
  `BLUETOOTH`, `BLUETOOTH_ADMIN`. Minta saat pertama membuka bagian ini.

## 6. Mobile — worker

- **Foreground service** (`[Service(ForegroundServiceType = ConnectedDevice)]`, notifikasi
  tetap "Terakarsa Print Service aktif · <printer>") saat switch Aktif.
- Loop: `POST api/print/claim` (`X-Print-Device-Token`, `JobTypes` = semua job type
  RAW_TSPL yang di-route ke device ini — ambil dari hasil claim, atau kirim kosong dan
  biarkan SP memfilter per route) setiap `PollSeconds` (default 3 detik; 10 detik kalau
  layar mati ≥ 5 menit), pakai `ActiveBaseUrl` dari Prompt 76.
- Untuk tiap job: `TsplBuilder.Build…` sesuai job_type (THREAD_*: `BuildThreadLabel`;
  BUNDLE_LABEL juga didukung karena builder sama) → bytes → kirim via
  `BluetoothSocket` SPP (UUID `00001101-0000-1000-8000-00805F9B34FB`). Koneksi dibuka saat
  ada job, ditutup setelah idle 60 detik. Gagal kirim → `report` Success=false dengan pesan,
  retry mengikuti SP (seperti Windows).
- Kalau token device ditolak (401) → service berhenti, tampilkan di Setting "Daftarkan ulang".
- Battery optimization: minta pengecualian (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`)
  saat mengaktifkan, dengan penjelasan singkat.

## 7. Verifikasi

- `dotnet build TerakarsaApp.slnx -v q` (PrintService ikut library baru) dan
  `dotnet build TerakarsaApp.Mobile -v q` sukses.
- PrintService Windows DryRun masih menghasilkan `.tspl` yang identik untuk BUNDLE_LABEL
  (bandingkan satu file sebelum/sesudah pemindahan `TsplBuilder` — lampirkan diff kosong).
- Pengujian ke printer fisik dilakukan owner; tulis langkahnya di
  `TerakarsaApp.Mobile/README.md` (pairing printer di Android, daftarkan HP, pindahkan
  route di `/admin/printer`, cetak dari halaman Kembali).

## Yang TIDAK boleh dilakukan

- Jangan ubah format TSPL label yang sudah ada.
- Jangan ubah jalur `X-Print-Api-Key` untuk PrintService Windows.
- Jangan simpan `device_token` di Preferences biasa — hanya SecureStorage.

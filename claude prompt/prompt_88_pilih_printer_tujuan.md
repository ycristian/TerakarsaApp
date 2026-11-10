# Prompt 88 — Printer Jaringan (TCP) + Pilih Printer Tujuan Saat Cetak Label

## Konteks & tujuan

Pabrik sekarang punya 2 printer label TSPL: TSC TTP-244 Pro (USB, PC PrintService) dan
Xprinter XP-D4601B (WiFi, IP `192.168.8.51`, port `9100`, dipasang di lantai atas). Ke depan
printer label akan bertambah dan **dinamai berdasarkan lokasinya**.

Dua hal yang diubah di prompt ini:

1. **PrintService bisa kirim langsung ke printer jaringan** lewat socket TCP (`host:port`),
   tanpa printer itu didaftarkan di Windows. Menambah printer baru = isi IP di halaman admin
   Printer & Routing, tidak ada deploy ulang.
2. **Routing jadi satu job type → banyak device tujuan.** Kalau job type punya lebih dari satu
   device tujuan, user **wajib memilih** printer saat cetak (dropdown + tombol "jadikan
   default"). Kalau hanya satu, otomatis seperti sekarang.

### Batas tegas

- `TsplBuilder.cs`, isi label (payload, `qr_content`, layout TSPL), dan `EscPosRenderer.cs`
  **tidak diubah**. XP-D4601B sama-sama 203 DPI, koordinat TSPL sudah cocok.
- Jalur app Android (HP Bluetooth, XP-P323B, klaim job lewat token device) **tetap jalan
  seperti sekarang**. Boleh disesuaikan hanya sebatas yang diperlukan oleh perubahan routing
  (poin 2 dan 3) — jangan ubah cara HP mendaftar/pairing/polling.
- Jangan membuat mekanisme multi-instance PrintService. Satu worker di satu PC menangani
  semua printer PC (USB Windows maupun TCP).
- SQL tetap ke folder `sql/` (file alter baru `sql/alter_88_print_multi_route.sql` idempotent +
  update `sql/create_tables_tmos_final.sql`). Claude Code boleh mengeksekusi DDL langsung ke
  database seperti seri sebelumnya.

**Baca dulu kondisi terkini di repo sebelum mengubah apa pun**: skema `print_devices` dan
`print_job_routes` sudah berubah sejak Prompt 48 (ada tipe device HP Bluetooth, token device,
"terakhir aktif", dsb. dari seri 76–77). Semua instruksi di bawah menyesuaikan ke skema yang
ada, bukan ke skema Prompt 48.

---

## 1. Skema SQL

### 1a. `print_devices` — printer jaringan + grup

Tambahkan (nama kolom sesuaikan dengan konvensi yang sudah ada di tabel ini):

- `connection_type varchar(20) not null` — nilai: `WINDOWS` (nama printer Windows, seperti
  sekarang), `TCP` (socket ke `host:port`), dan nilai yang sudah dipakai untuk HP Bluetooth
  (pertahankan nilainya kalau sudah ada kolom sejenis; kalau sudah ada kolom tipe device, **pakai
  kolom itu dan tambahkan nilai `TCP`**, jangan buat kolom kembar).
- `host varchar(100) null`, `port int null` — wajib terisi kalau `connection_type = 'TCP'`
  (CHECK constraint). `printer_name` boleh kosong/placeholder untuk device TCP.
- `device_group varchar(30) not null` — pengelompokan ukuran/jenis: `LABEL_BUNDLE` (label
  bundle 10×5 cm, TSPL), `LABEL_BENANG` (label 30×20 mm, TSPL, HP), `STRUK_80` (thermal 80 mm,
  TOKEN). Isi untuk baris yang sudah ada lewat alter script: TSC → `LABEL_BUNDLE`, HP Gudang
  → `LABEL_BENANG`, Iware → `STRUK_80`.

Seed device baru (idempotent, `device_code = 'LABEL_ATAS'`):
`device_name = N'Label Lantai Atas (XP-D4601B)'`, `connection_type = 'TCP'`,
`host = '192.168.8.51'`, `port = 9100`, `render_mode = 'RAW_TSPL'`,
`device_group = 'LABEL_BUNDLE'`, `is_active = 1`. Nama bisa diganti dari halaman admin.

### 1b. `print_job_routes` — banyak device per job type

- Ganti unique index `UX_print_job_routes_type (job_type)` menjadi unique pada
  `(job_type, print_device_id)` WHERE `deleted_at IS NULL`.
- Baris yang ada tidak diubah (otomatis jadi "satu tujuan" untuk tiap job type).

### 1c. `print_jobs` — device dipilih saat dibuat

`print_jobs.print_device_id` sekarang **boleh diisi saat job dibuat** (pilihan user). Aturan:

- Kalau job type punya **>1** route hidup & aktif → `print_device_id` **wajib** diisi saat
  insert, dan harus salah satu dari route job type itu. Kalau tidak → SP menolak dengan pesan
  jelas (`'Pilih printer tujuan'`), job **tidak** dibuat. Tidak ada job "ngambang" tanpa tujuan.
- Kalau job type punya **tepat 1** route → `print_device_id` boleh NULL; diisi saat klaim
  seperti sekarang.
- Kalau job type punya **0** route → tolak seperti sekarang (atau biarkan PENDING sesuai perilaku
  yang ada — ikuti perilaku saat ini, jangan ubah).

Buat satu SP util yang dipakai semua jalur insert: `SIS_PrintJob_ResolveDevice`
(`@JobType`, `@RequestedDeviceId` → mengembalikan device id final atau RAISERROR). Semua SP yang
membuat `print_jobs` (lihat §3) memanggil ini, jadi aturannya satu tempat.

Mirror yang sama ke `print_jobs_dryrun` / SP `*_DryRun`.

### 1d. Klaim

Ubah `SIS_PrintJob_Claim` (dan varian DryRun, dan SP klaim yang dipakai app HP):

- Kalau `pj.print_device_id` **sudah terisi** → pakai device itu; syarat: device hidup, aktif,
  dan masih ada di `print_job_routes` untuk job type tsb. Kalau tidak memenuhi → **tetap
  PENDING** (bukan error), sama seperti perilaku device nonaktif sekarang.
- Kalau NULL → ambil satu-satunya route job type tsb (kalau ternyata >1 route, jangan diklaim —
  tetap PENDING; ini kondisi data lama/anomali, tampilkan di halaman admin sebagai "menunggu
  pilihan printer").
- Pemisahan **siapa yang boleh mengklaim**: PrintService PC hanya mengklaim job yang device
  finalnya `connection_type IN ('WINDOWS','TCP')`; app HP hanya device miliknya sendiri (sesuai
  mekanisme yang sudah ada). Ini wajib, karena sekarang job type yang sama bisa punya tujuan PC
  dan HP sekaligus.
- Hasil klaim mengembalikan tambahan kolom `ConnectionType`, `Host`, `Port`.

### 1e. Read SP untuk UI

- `SIS_PrintDevice_ListForJobType @JobType` → device aktif yang ada di route job type tsb
  (`print_device_id`, `device_name`, `device_group`, `connection_type`). Dipakai dropdown user.
- Halaman admin: sesuaikan SP list routing agar mengembalikan banyak device per job type, dan
  SP manage routing menerima daftar device (hapus/tambah baris route = soft delete / insert).

---

## 2. PrintService (Worker)

- Tambah pengirim `TcpRawPrinter`: `TcpClient` ke `host:port`, timeout koneksi 5 detik, tulis
  semua byte, flush, tutup. Dipakai untuk device `connection_type = 'TCP'`, baik `RAW_TSPL`
  maupun `TOKEN` (byte ESC/POS juga bisa lewat TCP). Pengirim Windows (winspool) tetap untuk
  `WINDOWS`.
- Kegagalan koneksi (printer mati / IP salah) → report gagal dengan pesan jelas
  (`"TCP 192.168.8.51:9100: connection refused/timeout"`), ikut mekanisme retry 3× yang ada.
- DryRun: device TCP ditulis ke `./dryrun/{id}.tspl` seperti biasa, nama file ditambah suffix
  device code.
- Daftar job type yang diklaim (`@JobTypesCsv`, `PrinterLabelOn/PrinterThermalOn`) — **cek
  apakah masih relevan**; kalau sekarang klaim sudah berbasis device, jangan tambah logika
  baru, cukup pastikan job type label untuk device TCP ikut terklaim.
- Update `TerakarsaApp.PrintService/README.md`: bagian printer jaringan + cara tambah printer
  dari halaman admin.

---

## 3. Titik cetak yang memakai pilihan printer

Semua jalur yang membuat job dengan `device_group = 'LABEL_BUNDLE'`. **Cari sendiri di repo**
nama SP/endpoint-nya (jangan mengarang), minimal:

1. **Admin Cutting — buat hamparan → stiker bundle** (`CUTTING_BUNDLE_LABEL`, seri 78–80).
2. **Station Bundling — serah/set stok cutting ke penjahit** (job label yang dibuat saat
   bundle diserahkan; cek `SIS_Bundle_Manage` dan station Bundling).
3. **Kelola Bundle — cetak ulang label** (`SIS_Bundle_ReprintLabel` / `BUNDLE_LABEL`).
4. **Bundle anak — cetak label bundle anak** (Prompt 82).

Tiap jalur:

- API menerima `printDeviceId` (nullable). SP meneruskan ke `SIS_PrintJob_ResolveDevice`.
- Kalau user tidak memilih padahal wajib → API mengembalikan 400 dengan pesan SP, UI
  menampilkan pesan dan **tidak** menjalankan aksinya. Untuk jalur yang aksinya lebih dari
  sekadar cetak (mis. serah bundle ke penjahit, buat hamparan), validasi printer dilakukan
  **sebelum** transaksi utama, supaya tidak ada aksi yang jadi tapi labelnya tidak tercetak.
- Cetak ulang **tidak** mengubah `print_device_id` job lama; selalu job baru dengan device
  pilihan saat itu.

### Komponen UI bersama: `PrinterPicker`

Satu komponen Blazor dipakai di keempat layar (web biasa, tablet Admin Cutting, station,
WebView app Android):

- Parameter: `JobType`. Memanggil `SIS_PrintDevice_ListForJobType`.
- **0 device** → tampil peringatan "Belum ada printer untuk {JobType}", tombol aksi cetak
  dinonaktifkan.
- **1 device** → komponen **tidak tampil** (otomatis). Boleh tampil sebagai teks kecil
  "Cetak ke: Label Lantai Atas" kalau ruang ada.
- **>1 device** → dropdown nama device + ikon/badge grup, tombol **"Jadikan default"**.
- Default disimpan di `localStorage` per perangkat, key `tmos.printer.default.{JobType}` →
  `print_device_id`. Saat buka layar, kalau ada default dan device itu masih ada di daftar →
  otomatis terpilih; kalau tidak ada lagi (nonaktif/dihapus) → kosong, user harus pilih.
- Pilihan terakhir (tanpa klik "default") juga diingat sampai halaman di-reload.
- Pola localStorage: pakai helper JS interop yang sudah ada di project kalau ada; kalau belum,
  buat satu helper kecil dan pakai di semua tempat.

---

## 4. Halaman admin Printer & Routing (`/admin/printer`)

Kembangkan halaman yang sudah ada:

**Device cetak**
- Form tambah/edit device: nama (lokasi), tipe koneksi (`PC Windows` / `PC Jaringan (TCP)` /
  HP Bluetooth hanya tampil, didaftarkan dari HP seperti sekarang), nama printer Windows
  (hanya untuk Windows), host + port (hanya untuk TCP), render mode, grup, aktif.
- Badge tipe: tambah `PC Jaringan` di samping `PC Windows` / `HP Bluetooth`; tampilkan
  `host:port` di baris detail.
- Tombol **Test print** per device: membuat job test (job type `TEST_PRINT`, payload sederhana
  "TEST {device_name} {waktu}") langsung ke device itu (`print_device_id` diisi, tanpa route).
  Untuk `RAW_TSPL` rakit label kecil berisi teks; untuk `TOKEN` beberapa baris token. Tambahkan
  `TEST_PRINT` ke daftar job type yang boleh diklaim worker. Kalau tombol test print sudah ada,
  pakai yang ada dan pastikan jalan untuk TCP.

**Routing job cetak**
- Kolom "Device tujuan" dari dropdown tunggal menjadi **multi-pilih** (checkbox list / chip).
  Daftar hanya device aktif dengan `render_mode` yang cocok dengan job type; tampilkan badge
  grup supaya admin tidak salah pilih (mis. HP Gudang untuk BUNDLE_LABEL). Tidak perlu
  memblokir lintas grup secara paksa — admin yang memutuskan.
- Kalau job type punya >1 device, tampilkan catatan kecil: "User memilih printer saat cetak".
- Kolom "Menunggu": tambah hitungan job PENDING yang tidak bisa diklaim karena device-nya
  tidak valid lagi (lihat §1d), dengan tooltip penyebabnya.

---

## 5. Urutan deploy

1. Jalankan `sql/alter_88_print_multi_route.sql` (tabel + seed device `LABEL_ATAS` + index) lalu
   semua SP yang diubah/dibuat.
2. Deploy API + Client (IIS).
3. Publish PrintService ke NUC, `sc stop` / `sc start TmosPrintService`.
4. Di `/admin/printer`: ganti nama device `LABEL_ATAS` sesuai lokasi, **Test print** ke
   192.168.8.51 → harus keluar label.
5. Routing `BUNDLE_LABEL` dan `CUTTING_BUNDLE_LABEL`: centang TSC + Label Lantai Atas.
6. Tidak ada perubahan di app Android yang wajib di-sideload ulang; kalau ada perubahan
   WebView-side, cukup web.

## 6. Verifikasi

- Buat hamparan di tablet Admin Cutting → dropdown printer muncul (2 pilihan), pilih Lantai
  Atas, klik "Jadikan default" → stiker keluar di XP-D4601B; `print_jobs.print_device_id`
  terisi saat insert, bukan saat klaim. Reload halaman → default masih terpilih.
- Routing `BUNDLE_LABEL` dikembalikan ke 1 device → dropdown hilang, cetak ulang langsung jalan.
- Routing diset 2 device, cetak ulang tanpa memilih → 400 "Pilih printer tujuan", tidak ada
  baris baru di `print_jobs`.
- Matikan XP-D4601B → job test gagal dengan pesan TCP jelas, retry 3× lalu ERROR; job label
  lain ke TSC tetap jalan.
- Nonaktifkan device Lantai Atas saat ada job PENDING ke device itu → job tetap PENDING,
  tampil di hitungan "menunggu" admin; aktifkan lagi → terklaim.
- HP Gudang: label benang masih bisa dicetak dari app Android seperti sebelumnya.
- DryRun: file `.tspl` untuk device TCP muncul dengan suffix device code.

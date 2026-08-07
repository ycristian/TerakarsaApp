# Prompt 48 — Arsitektur Print Thermal: Layout Pindah ke SQL (Token + Routing Printer)

## Konteks & tujuan

Saat ini isi cetakan dirakit di C# (`TerakarsaApp.PrintService`). Setiap revisi layout
struk = build + publish ulang service. Prompt ini memindahkan **perakitan isi cetakan
thermal ke stored procedure**, sehingga revisi layout cukup `CREATE OR ALTER PROCEDURE`
tanpa menyentuh aplikasi.

Mekanismenya: SP menghasilkan teks ber-**token** (kode format sederhana, bukan byte
printer). Worker menerjemahkan token → byte ESC/POS. Token dirancang lengkap di prompt
ini supaya ke depan hampir tidak pernah perlu deploy ulang worker.

Sekalian: routing printer lewat tabel, menggantikan `PrinterName` tunggal di
appsettings.

### Batas tegas

- **Hanya jalur printer thermal 80mm (ESC/POS, Iware XS-80BT).**
- **Label bundle TSC TTP-244 Pro TIDAK disentuh.** `TsplBuilder.cs`, payload
  `BUNDLE_LABEL`, `SIS_Bundle_Manage`, `SIS_Bundle_ReprintLabel`, dan isi `qr_content`
  tetap persis seperti sekarang. Jalur itu hanya ikut menyesuaikan cara worker memilih
  printer (poin 5), tidak lebih.
- Semua PrintService berjalan di **satu PC** yang terhubung ke semua printer, jadi satu
  instance worker menangani banyak printer. Jangan buat mekanisme multi-instance.

### Cetak ulang

Render dilakukan **saat job diklaim**, bukan saat job dibuat. Konsekuensi yang
memang diinginkan: cetak ulang selalu mengikuti layout SP terbaru dan data terkini.

---

## 1. Skema SQL

Tambahkan ke `sql/create_tables_tmos_final.sql` (section PRODUKSI, di dekat `print_jobs`)
dan buat `sql/alter_48_print_devices.sql` yang idempotent untuk DB yang sudah ada.

```sql
-- Daftar printer fisik. Menambah/mengganti printer = INSERT/UPDATE di sini,
-- tidak perlu deploy ulang PrintService.
CREATE TABLE print_devices(
 print_device_id int primary key identity(1,1),
 device_code varchar(30) not null,          -- 'THERMAL', 'LABEL', 'THERMAL_FINISHING', dst
 device_name varchar(150) not null,         -- nama untuk manusia, mis. 'Struk Lantai 1'
 printer_name varchar(255) not null,        -- nama printer Windows PERSIS
 render_mode varchar(20) not null           -- 'TOKEN' (dirender SP) | 'RAW_TSPL' (dirakit C#)
   constraint CK_print_devices_render_mode check (render_mode in ('TOKEN','RAW_TSPL')),
 chars_per_line int not null default 48,    -- lebar font A
 chars_per_line_small int not null default 64, -- lebar font B
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
CREATE UNIQUE INDEX UX_print_devices_code ON print_devices(device_code) WHERE deleted_at IS NULL;

-- Pemetaan job_type -> printer tujuan.
CREATE TABLE print_job_routes(
 print_job_route_id int primary key identity(1,1),
 job_type varchar(30) not null,
 print_device_id int not null
   constraint FK_pjr_print_devices foreign key references print_devices(print_device_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
CREATE UNIQUE INDEX UX_print_job_routes_type ON print_job_routes(job_type) WHERE deleted_at IS NULL;
```

Tambahan kolom pada `print_jobs` (di alter script juga):

```sql
ALTER TABLE print_jobs ADD print_device_id int null
  constraint FK_print_jobs_print_devices foreign key references print_devices(print_device_id);
```

Diisi **saat klaim** (bukan saat job dibuat), sebagai catatan printer mana yang benar-benar
dipakai. Dengan begitu mengubah routing langsung berlaku untuk job yang masih antre.

### Seed (idempotent, di alter script)

- Device `LABEL` → `printer_name` = nilai `PrinterName` yang selama ini dipakai untuk TSC
  (biarkan Claude Code membaca nilainya dari `appsettings.json` PrintService dan menaruhnya
  sebagai default; kalau tidak ketemu, pakai `'TSC TTP-244 Pro'`), `render_mode = 'RAW_TSPL'`.
- Device `THERMAL` → `printer_name` = `'Iware XS-80BT'`, `render_mode = 'TOKEN'`,
  48 / 64 karakter.
- Route: `BUNDLE_LABEL` → `LABEL`; `job_type` kupon borongan yang sudah ada → `THERMAL`.
  **Cari sendiri nama `job_type` kupon borongan di repo** (`SIS_*` kupon/payroll,
  `PrintService`, dan tempat INSERT ke `print_jobs`) — jangan mengarang nama baru.
- `created_by` pakai user sistem yang sudah ada di DB (cari pola yang dipakai seed lain).

---

## 2. Kamus token (spesifikasi — patuhi persis)

Output SP render adalah teks biasa. **Satu baris teks = satu baris cetak.** Token ditulis
dengan kurung kurawal di awal baris dan boleh digabung. Karakter `{` literal ditulis `{{`.

### Token format (di awal baris, boleh lebih dari satu)

| Token | Arti |
|---|---|
| `{S1}` | ukuran normal (default) |
| `{S2}` | dobel tinggi + lebar |
| `{S3}` | tiga kali tinggi + lebar |
| `{SH2}` | dobel tinggi saja |
| `{SW2}` | dobel lebar saja |
| `{B}` | tebal |
| `{U}` | garis bawah |
| `{FA}` | font A (default, lebar `chars_per_line`) |
| `{FB}` | font B (kecil/rapat, lebar `chars_per_line_small`) |
| `{L}` `{C}` `{R}` | rata kiri (default) / tengah / kanan |

Semua format berlaku **hanya untuk baris itu**, lalu reset ke default. Ini disengaja: SP
tidak perlu ingat mematikan format, dan tidak ada risiko format bocor ke baris berikutnya.

### Token baris utuh (berdiri sendiri, tidak digabung teks)

| Token | Arti |
|---|---|
| `{HR}` | garis pemisah `-` selebar kertas |
| `{HR=}` | garis pemisah `=` selebar kertas |
| `{FEED:n}` | n baris kosong |
| `{CUT}` | potong kertas |
| `{DRAWER}` | pulsa buka laci kasir |

### Token kolom

| Token | Arti |
|---|---|
| `{2COL}kiri\|kanan` | kiri rata kiri, kanan rata kanan, diisi spasi di tengah |
| `{ROW:w1,w2,...}a\|b\|c` | kolom lebar tetap (satuan karakter); kolom terakhir rata kanan, sisanya rata kiri |

Ini bagian terpenting dari kamus. Tanpa ini SP harus menghitung padding spasi sendiri
dan hasilnya rapuh begitu nama artikel/angka berubah panjang.

### Token data

| Token | Arti |
|---|---|
| `{QR:isi}` | QR code, rata tengah, ukuran sedang |
| `{BC:isi}` | barcode Code128, rata tengah, dengan teks di bawahnya |

Kupon borongan sekarang belum memakai keduanya. Tetap implementasikan supaya nanti tidak
perlu deploy worker lagi hanya untuk menambahkannya.

### Aturan renderer

- **Word-wrap otomatis**: baris yang melebihi lebar kertas dipotong per kata, baris
  lanjutan mewarisi format baris induk. SP tidak perlu memotong teks sendiri.
- Isi kolom pada `{2COL}` / `{ROW}` yang melebihi lebarnya dipotong dengan `…` (tidak
  di-wrap — supaya tabel tidak berantakan).
- Lebar kertas diambil dari `print_devices` sesuai font aktif, bukan dari konstanta.
- Karakter non-ASCII dipetakan ke padanan ASCII terdekat (codepage CP437, `ESC t 0`).
- Token tidak dikenal → **abaikan token itu, cetak sisanya**, dan tulis warning di log.
  Jangan gagalkan job hanya karena satu token asing; kalau tidak, SP baru yang memakai
  token yang belum ada di worker akan menghanguskan seluruh cetakan.
- Akhir dokumen: kalau SP tidak menulis `{CUT}`, worker otomatis menambahkan
  `{FEED:4}{CUT}`.

---

## 3. Stored Procedures

### `SIS_Print_Dispatch` (@PrintJobId INT)

Muara semua render thermal. Baca `job_type`, `ref_id`, `payload` dari `print_jobs`, lalu
routing ke SP render sesuai `job_type` (pola `IF ... ELSE IF`, sengaja eksplisit supaya
gampang dibaca dan ditambah).

Kembalikan satu kolom `TokenText NVARCHAR(MAX)`.

**Penjagaan salah-pasang printer (wajib, sebelum routing):** periksa `render_mode` device
tujuan job (`print_jobs.print_device_id` → `print_devices`). Kalau bukan `'TOKEN'` →
`RAISERROR('Job %d diarahkan ke printer %s yang bukan mode TOKEN.', ...)`.

Alasannya: route salah pasang tidak menghasilkan error yang kelihatan — printer akan
memuntahkan kertas berisi perintah mentah sebagai teks. Gagal dengan pesan jelas jauh
lebih baik daripada diam-diam salah.

Kalau `job_type` tidak punya cabang → `RAISERROR('Job type %s belum punya SP render.', ...)`.

### `SIS_Print_KuponBorongan` (@RefId INT, @Payload NVARCHAR(MAX) = NULL)

Render kupon borongan sebagai teks token. **Layout harus sama persis dengan cetakan
sekarang** — baca dulu kode C# yang merakit kupon di `TerakarsaApp.PrintService`, lalu
terjemahkan elemen per elemen ke token. Jangan mendesain ulang tampilannya.

Parameter yang selama ini disimpan di `payload` JSON dibaca dengan `OPENJSON`. Data lain
(nama penjahit, bundle, qty, periode) diambil **langsung dari tabel saat render**, bukan
dari payload — supaya cetak ulang mengikuti data terkini.

Filter `deleted_at IS NULL` seperti biasa.

### Fungsi bantu `SIS_fn_Trunc` (@Text NVARCHAR(MAX), @Len INT)

Potong dengan `…` bila melebihi `@Len`. Dipakai SP render kalau perlu memangkas manual di
luar mekanisme kolom.

### Revisi `SIS_PrintJob_Claim` (@BatchSize INT = 5)

Tetap satu statement atomik dengan `UPDLOCK, READPAST` seperti sekarang. Perubahan:

- Saat klaim, resolusi printer: `print_jobs.job_type` → `print_job_routes` →
  `print_devices`. Isi `print_jobs.print_device_id` dengan hasilnya (di `UPDATE` yang sama).
- Kalau `job_type` tidak punya route hidup, atau device-nya `is_active = 0`: **jangan
  klaim job itu** (biarkan tetap PENDING) — job tanpa tujuan lebih baik menunggu daripada
  gagal 3 kali lalu jadi ERROR permanen.
- Kolom tambahan di hasil: `DeviceCode`, `PrinterName`, `RenderMode`, `CharsPerLine`,
  `CharsPerLineSmall`.

`SIS_PrintJob_Report` dan `SIS_PrintJob_RequeueStale` tidak berubah.

Semua SP di atas ditaruh di `sql/sp_Print_Render.sql` (SP render + dispatch + fungsi
bantu), kecuali revisi `SIS_PrintJob_Claim` yang tetap di `sql/sp_PrintJob_Manage.sql`.

---

## 4. API

Di `PrintController` ([RequirePrintApiKey], tidak berubah):

- **GET `api/print/render/{printJobId}`** → panggil `SIS_Print_Dispatch`, kembalikan
  `{ tokenText }`. Error dari SP diteruskan sebagai 400 dengan pesan aslinya.

DTO klaim (`PrintJobClaimedDto` di `TerakarsaApp.Shared`) ditambah field baru dari poin 3.

---

## 5. TerakarsaApp.PrintService

### `EscPosRenderer.cs` (baru)

Terjemahkan teks token → `byte[]` ESC/POS sesuai kamus di poin 2. Lebar kertas dan font
diambil dari data job (hasil klaim), bukan hardcode. Sertakan komentar singkat di tiap
blok token yang menyebutkan perintah ESC/POS-nya (`ESC !`, `ESC a`, `GS !`, `GS V`), supaya
mudah dirawat.

### Perubahan `Worker.cs`

Alur per job jadi:

1. Job punya `RenderMode = 'RAW_TSPL'` → **jalur lama tanpa perubahan**: parse payload
   JSON, `TsplBuilder`, kirim byte.
2. Job punya `RenderMode = 'TOKEN'` → panggil `api/print/render/{id}` →
   `EscPosRenderer` → kirim byte.
3. Printer tujuan diambil dari `PrinterName` **milik job**, bukan dari appsettings.

Kegagalan render (SP error / endpoint 400) dilaporkan lewat `api/print/report` dengan
pesan aslinya, sama seperti kegagalan cetak. Satu job gagal tidak menghentikan job lain.

### Konfigurasi

- `PrinterName` di `appsettings.json` **dihapus** — sudah pindah ke `print_devices`.
- `DryRun` tetap ada, tapi kini menulis **dua file** per job ke `./dryrun/`:
  `{print_job_id}.escpos` (atau `.tspl` untuk jalur lama) dan `{print_job_id}.txt` berisi
  hasil render sebagai teks polos dengan lebar kertas yang benar. File `.txt` inilah yang
  dipakai untuk memeriksa layout tanpa printer fisik.

Perbarui `README.md` PrintService: hapus penjelasan `PrinterName`, tambahkan penjelasan
`print_devices` / `print_job_routes` dan cara mengganti printer lewat SQL.

---

## 6. Verifikasi

1. `dotnet build` seluruh solution sukses.
2. DryRun = true, cetak 1 bundle → `.tspl` tetap terbit dan isinya **identik byte-per-byte**
   dengan sebelum prompt ini. Ini pemeriksaan regresi utama: jalur label harus terbukti
   tidak berubah.
3. DryRun = true, cetak 1 kupon borongan → bandingkan `.txt` dengan cetakan lama.
   Perbedaan hanya boleh berupa spasi/padding, bukan isi atau urutan elemen.
4. Ubah `SIS_Print_KuponBorongan` (mis. tambah satu baris `{C}{B}` di header) → cetak
   ulang **tanpa restart service** → baris baru muncul. Ini bukti tujuan utama prompt
   tercapai.
5. Nonaktifkan route kupon (`deleted_at` diisi) → job baru tetap PENDING, tidak jadi ERROR,
   dan kembali tercetak setelah route dipulihkan.
6. Uji token yang tidak dikenal: sisipkan `{ZZZ}` di SP → cetakan tetap terbit, ada warning
   di log.
7. Uji salah-pasang: arahkan sementara route kupon ke device `LABEL` → job gagal dengan
   pesan jelas dari `SIS_Print_Dispatch`, **bukan** mencetak teks perintah mentah.
   Kembalikan route setelahnya.

## Urutan deploy

1. `sql/alter_48_print_devices.sql`
2. `sql/sp_Print_Render.sql`
3. `sql/sp_PrintJob_Manage.sql` (revisi Claim)
4. Deploy API
5. Deploy PrintService

Langkah 3 dan 4 harus berdekatan: Claim versi baru mengembalikan kolom yang belum dikenal
API lama, dan API versi baru butuh kolom itu.

## Yang TIDAK boleh dilakukan

- Jangan ubah `TsplBuilder.cs`, payload `BUNDLE_LABEL`, atau isi `qr_content`.
- Jangan buat UI pengelolaan `print_devices` / `print_job_routes` — cukup lewat SQL manual
  untuk sekarang.
- Jangan hilangkan `DryRun` atau mekanisme retry/RequeueStale yang sudah ada.
- Jangan tambah library/NuGet baru. ESC/POS ditulis manual sebagai byte.
- Jangan render saat job dibuat — render hanya saat klaim.
- Jangan sentuh alur stasiun, workflow log, atau halaman Blazor mana pun.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

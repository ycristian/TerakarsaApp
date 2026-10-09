# Prompt 70 — Absensi RFID: Kartu Karyawan, Gate App, Rekap

> Nomor 60–69 sudah dipakai seri PO TNI AD, jadi prompt ini memakai **70**. Ganti nomornya di
> nama file dan di `alter_70_absensi_rfid.sql` kalau mau memakai nomor lain.

## Konteks

Pabrik memakai kartu RFID sebagai kartu pegawai. Kartu **tidak pernah dibawa pulang**: dititip
di rak gate satpam, diambil tiap pagi, dikembalikan tiap sore. Karena itu **status kartu =
status orang**, dan absensi diturunkan dari tap ambil/kembali kartu — tanpa tombol
MASUK/PULANG di layar.

Hardware yang dipakai:

- Reader: USB RFID 13.56 MHz, **keyboard emulation** (plug & play, tanpa driver/SDK). Output
  **10 digit desimal + Enter**. Reader diperlakukan seperti keyboard: cukup input yang di-fokus.
- Kartu: Mifare S50 1K, PVC 0,8 mm, **4-byte UID**. Hanya UID yang dipakai — **tidak ada data
  yang ditulis ke kartu**. Nama/jabatan/resource dicetak atau ditulis di permukaan kartu.
- Perangkat gate: **tablet Windows 2-in-1 10 inci dengan layar sentuh**, di dudukan di meja
  satpam, reader dicolok lewat dock/hub USB. Punya baterai, jadi tap tetap tercatat saat listrik
  padam. Aplikasi desktop, bukan browser.

Layar menghadap **satpam saja** — karyawan tidak melihatnya. Karena itu **bunyi berbeda per
hasil adalah lapis verifikasi utama**, bukan pelengkap (lihat bagian 5.7).

Warna resource ada di **holder/lanyard fisik**, bukan di kartu — supaya mutasi line cukup tukar
holder. Warna tetap ditampilkan di layar gate supaya satpam bisa mencocokkan dengan holder yang
dipakai karyawan.

Kartu ini nantinya juga dipakai untuk pengambilan barang di gudang. Karena itu `employee_cards`
dirancang sebagai **lapisan identitas umum**, bukan tabel milik modul absensi. Modul material
tinggal ikut memakainya nanti — **di luar cakupan prompt ini**.

## Acuan visual — WAJIB DIBACA SEBELUM MENULIS UI

File **`claude prompt/mockup_70_absensi_rfid.html`** berisi ke-12 layar yang diminta prompt ini,
sebagai HTML + inline style murni. **Baca file itu sebelum menulis satu pun `.razor`**, dan ambil
dari sana: struktur elemen, ukuran teks, jarak, warna, isi tabel, dan seluruh teks bahasa
Indonesia. Jangan merancang ulang tampilan dari nol.

- **9 layar gate** (`Gate 1`–`Gate 9`) → salin apa adanya ke `TerakarsaApp.GateApp`. Proyek baru,
  tidak ada CSS warisan, jadi markup dan inline style di mockup adalah acuan langsung.
- **3 layar admin** (`Admin 1`–`Admin 3`) → **acuan tata letak dan isi kolom saja**. Halaman TMOS
  lain memakai Bootstrap; ikuti pola halaman master yang sudah ada, jangan menyalin CSS mockup.
- Data di mockup (nama, kode, jam, UID) hanya contoh — diganti hasil SP.
- Warna badge resource di mockup juga contoh; nilainya dibaca dari `resources.color_hex`.

Kalau ada pertentangan antara teks prompt ini dan mockup, **prompt ini yang menang** untuk
perilaku dan aturan data; **mockup yang menang** untuk tampilan dan kata-kata di layar.

---

## 1. Perubahan tabel (script alter, manual)

File baru `sql/alter_70_absensi_rfid.sql`, idempotent. `sql/create_tables_tmos_final.sql` ikut
diperbarui.

### 1.1 `positions` — tambah kolom

```
is_gate_operator bit not null default 0
```

Penanda jabatan yang boleh membuka menu satpam di aplikasi gate (mis. jabatan Satpam). Akses
melekat pada **jabatan**, bukan pada kartu dan bukan pada user login — aplikasi gate memang
tanpa login, dan `employees` tidak punya relasi ke `users`.

### 1.2 `resources` — tambah kolom

```
color_hex varchar(7) null          -- mis. '#1E5FA8', dipakai badge warna di layar gate
```

Diisi sesuai warna holder fisik per line/resource. NULL → layar gate memakai warna netral.

### 1.3 `employees` — tambah kolom

```
phone varchar(30) null
```

Dikumpulkan satpam di gate saat pembagian kartu. Tidak dipakai modul lain.

### 1.4 `employee_cards` (tabel baru)

```
employee_card_id       int primary key identity(1,1)
employee_id            int not null       FK -> employees(employee_id)
card_uid               varchar(20) not null    -- 10 digit desimal, DISIMPAN SUDAH DI-PAD NOL DI DEPAN
card_type              varchar(20) not null    -- TETAP / SEMENTARA
card_status            varchar(20) not null    -- AKTIF / NONAKTIF
issued_at              datetime2 not null default sysdatetime()
issued_by_employee_id  int null  FK -> employees(employee_id)   -- satpam yang mendaftarkan dari gate
remarks                varchar(255) null
+ kolom audit standar (created_at, created_by, updated_at, updated_by, deleted_at, deleted_by)
```

- Filtered unique index `UX_employee_cards_uid` pada `card_uid` **WHERE deleted_at IS NULL AND
  card_status = 'AKTIF'` — satu UID hanya boleh aktif di satu karyawan, tapi kartu lama yang
  sudah NONAKTIF tetap tersimpan sebagai riwayat.
- **Satu karyawan boleh punya beberapa kartu AKTIF sekaligus** (mis. kartu tetap + kartu
  sementara). Ini disengaja, jangan dikunci.
- `issued_by_employee_id` NULL kalau kartu didaftarkan dari admin panel (pelakunya sudah
  tercatat di `created_by`).

### 1.5 `attendance_sessions` (tabel baru)

```
attendance_session_id int primary key identity(1,1)
employee_id        int not null       FK -> employees(employee_id)
division_id        int not null       FK -> divisions(division_id)      -- snapshot saat check in
resource_id        int null           FK -> resources(resource_id)      -- snapshot saat check in
work_date          date not null                                        -- tanggal check in (pemilik sesi)
check_in_at        datetime2 not null
check_out_at       datetime2 null                                       -- NULL = belum / tidak diketahui
session_status     varchar(20) not null   -- OPEN / CLOSED / ANOMALI
session_flag       varchar(30) null       -- LEMBUR_DIKONFIRMASI / BELUM_CHECKOUT / LUPA_KEMBALI / DIKOREKSI
entry_source       varchar(10) not null   -- GATE / MANUAL
remarks            varchar(255) null
+ kolom audit standar
```

- `division_id`/`resource_id` di-snapshot saat check in supaya mutasi line tidak mengubah
  riwayat absensi.
- `session_status`:
  - `OPEN` — kartu sedang diambil, orang ada di dalam.
  - `CLOSED` — ditutup normal, `check_out_at` terisi.
  - `ANOMALI` — ditutup paksa, `check_out_at` **NULL**, butuh koreksi admin.
- Filtered unique index: hanya boleh ada **satu sesi OPEN per karyawan**
  (`WHERE session_status = 'OPEN' AND deleted_at IS NULL`). Beberapa kartu aktif milik satu orang
  tetap bermuara ke satu sesi — sesi melekat pada karyawan, bukan pada kartu.
- Index pendukung: (`work_date`, `division_id`), (`employee_id`, `work_date`).

### 1.6 `gate_taps` (tabel baru — log mentah, tidak boleh di-update)

```
gate_tap_id        int primary key identity(1,1)
tap_uid            uniqueidentifier not null   -- digenerate GateApp, kunci idempoten
card_uid           varchar(20) not null
tapped_at          datetime2 not null          -- WAKTU TAP ASLI (dari gate), bukan waktu terima server
gate_code          varchar(30) not null
result_code        varchar(30) not null
attendance_session_id int null  FK -> attendance_sessions(attendance_session_id)
employee_id        int null     FK -> employees(employee_id)   -- NULL kalau kartu tidak dikenal
is_offline_replay  bit not null default 0
created_at         datetime2 not null default sysdatetime()
```

- Unique index pada `tap_uid` — ini yang mencegah tap terhitung dua kali kalau jaringan putus
  setelah server commit tapi sebelum GateApp menerima balasan.
- Tabel ini log murni: tidak ada update, tidak ada soft delete.

### 1.7 `employee_change_log` (tabel baru — log mentah)

```
employee_change_log_id int primary key identity(1,1)
employee_id            int not null  FK -> employees(employee_id)
field_name             varchar(50) not null      -- employee_name / phone
old_value              varchar(255) null
new_value              varchar(255) null
changed_by_employee_id int null  FK -> employees(employee_id)   -- satpam, kalau dari gate
source                 varchar(10) not null      -- GATE / ADMIN
created_at             datetime2 not null default sysdatetime()
created_by             int not null
```

Tanpa tabel ini, data karyawan bisa berubah dari gate tanpa jejak. Satu baris per field yang
berubah.

---

## 2. Aturan sesi (ditegakkan di SP, bukan di aplikasi gate)

Jam masuk diambil dari `work_schedule_defaults` (`division_id` + `day_of_week` dari
`tapped_at`, `is_working_day = 1`). **Jendela check-in = `start_time` − 2 jam s/d `start_time`.**
Contoh `start_time` 08:00 → jendela 06:00–08:00.

Kalau tidak ada baris jadwal, atau `is_working_day = 0` untuk hari itu, pakai `start_time`
baris hari kerja terdekat milik divisi yang sama; kalau tetap tidak ada, fallback konstanta
**08:00** (beri komentar jelas di SP).

| Kondisi tap | Hasil |
|---|---|
| Waktu tap di dalam jendela check-in | **SELALU CHECK IN** (hari baru), apa pun status kartunya |
| Di luar jendela, tidak ada sesi OPEN | CHECK IN |
| Di luar jendela, ada sesi OPEN, durasi ≤ 14 jam | CHECK OUT normal |
| Di luar jendela, ada sesi OPEN, durasi > 14 jam dan ≤ 24 jam | **PERLU_KONFIRMASI** — satpam memilih |
| Di luar jendela, ada sesi OPEN, durasi > 24 jam | Tutup paksa sebagai ANOMALI, tanpa pilihan |

Detail:

- **Check in saat ada sesi OPEN** (orang lembur melewati jendela, lalu paginya tap lagi): sesi
  lama ditutup `session_status = 'ANOMALI'`, `check_out_at = NULL`,
  `session_flag = 'BELUM_CHECKOUT'`; lalu sesi baru dibuat. Tap pagi **tidak pernah gagal**
  karena sesi kemarin menggantung.
- **PERLU_KONFIRMASI** — SP tidak mengubah apa pun, hanya mengembalikan info sesi. Gate
  menampilkan layar pilihan, lalu memanggil SP lagi dengan `@ConfirmAction`:
  - `LEMBUR` → tutup normal (`CLOSED`, `check_out_at` terisi), `session_flag =
    'LEMBUR_DIKONFIRMASI'`. Tidak masuk laporan anomali.
  - `LUPA_KEMBALI` → `ANOMALI`, `check_out_at = NULL`, `session_flag = 'LUPA_KEMBALI'`.
- **Cooldown 30 detik**: `card_uid` yang sama di-tap lagi dalam 30 detik → `result_code =
  'DUPLIKAT'`, tidak ada perubahan sesi. Layar gate menampilkan "sudah tercatat".
- **Jam**: SP memakai `tapped_at` yang dikirim gate (waktu tap asli), **bukan** `SYSDATETIME()`.
  Ini yang membuat antrian offline tetap tercatat di jam yang benar. `SYSDATETIME()` tetap
  dipakai untuk kolom audit.
- Tap offline diproses **berurutan menurut `tapped_at`** saat antrian dikirim.
- Saat offline, layar konfirmasi tidak bisa muncul (butuh server). Sesi > 14 jam yang masuk
  lewat replay offline langsung jadi `ANOMALI` + `BELUM_CHECKOUT`, dikoreksi admin belakangan.

---

## 3. Stored Procedures (semua file baru di `sql/`, dijalankan manual)

### `sql/sp_EmployeeCard_Manage.sql`

`SIS_EmployeeCard_Manage` — `@Action` = CREATE / UPDATE / DEACTIVATE / DELETE.

- CREATE: validasi `card_uid` 10 digit angka (pad nol di depan sebelum simpan); tolak kalau UID
  sudah AKTIF di karyawan lain dengan pesan yang menyebut **nama pemilik** kartu tersebut.
  `@CardType` wajib TETAP atau SEMENTARA.
- DEACTIVATE: `card_status = 'NONAKTIF'` (bukan soft delete) — ini jalur normal untuk kartu
  hilang/diganti, supaya riwayat tetap utuh.
- DELETE: soft delete, hanya untuk salah input.

### `sql/sp_EmployeeCard_Select.sql`

- `SIS_EmployeeCard_List` (@Search, @OnlyActive) — JOIN employees, divisions, positions,
  resources. Kolom: uid, nama, kode karyawan, divisi, jabatan, resource, jenis kartu, status,
  tanggal terbit, nama satpam penerbit.
- `SIS_EmployeeCard_GetById`.

### `sql/sp_Gate.sql`

**`SIS_Gate_CardSync`** — satu panggilan, tiga result set:

1. Semua kartu `AKTIF` (baris hidup) + data tampilan: `card_uid`, `employee_id`,
   `employee_name`, `employee_code`, `position_name`, `division_id`, `resource_name`,
   `color_hex`, `card_type`, `is_gate_operator` (dari `positions`), `start_time` hari ini untuk
   divisi itu.
2. Semua karyawan aktif (untuk daftar pilih saat mendaftarkan kartu dan mengubah data):
   `employee_id`, `employee_name`, `employee_code`, `phone`, `division_name`, `resource_name`,
   `color_hex`, `has_active_card` (bit).
3. Satu baris: `server_time` (`SYSDATETIME()`), jumlah karyawan aktif.

**`SIS_Gate_Tap`** — inti logika pasal 2.

```
@TapUid          uniqueidentifier
@CardUid         varchar(20)
@TappedAt        datetime2
@GateCode        varchar(30)
@ConfirmAction   varchar(20) = NULL     -- NULL / 'LEMBUR' / 'LUPA_KEMBALI'
@IsOfflineReplay bit = 0
```

- Idempoten: kalau `@TapUid` sudah ada di `gate_taps`, **jangan proses ulang** — kembalikan
  hasil yang tersimpan.
- Seluruh pekerjaan dalam satu transaksi.
- Satu result set, kolom: `result_code`, `employee_name`, `employee_code`, `position_name`,
  `resource_name`, `color_hex`, `check_in_at`, `check_out_at`, `duration_minutes`,
  `message` (bahasa Indonesia, untuk layar).
- `result_code`: `CHECK_IN` / `CHECK_OUT` / `PERLU_KONFIRMASI` / `DUPLIKAT` /
  `KARTU_TIDAK_DIKENAL` / `KARTU_NONAKTIF`.
- Kartu tidak dikenal/nonaktif tetap dicatat ke `gate_taps` (bukti percobaan tap).

**`SIS_Gate_Counts`** (@GateCode, @AtDate) — tiga angka untuk layar tunggu: hadir (sesi OPEN),
belum ambil kartu (karyawan aktif tanpa sesi OPEN), perlu cek (sesi ANOMALI hari ini).

**`SIS_Gate_Pending`** (@Mode) — daftar untuk menu satpam:
- `BELUM_AMBIL` — karyawan aktif tanpa sesi OPEN
- `BELUM_KEMBALI` — sesi OPEN
- `BELUM_PUNYA_KARTU` — karyawan aktif tanpa satu pun kartu AKTIF

Kolom: employee_id, nama, kode, divisi, resource, color_hex, jam check in (kalau ada).

**`SIS_Gate_RegisterCard`** — pendaftaran kartu dari gate.

```
@EmployeeId          int
@CardUid             varchar(20)
@CardType            varchar(20)    -- TETAP / SEMENTARA
@DeactivateOldCards  bit = 0        -- 1 = semua kartu AKTIF milik karyawan ini di-NONAKTIF-kan dulu
@OperatorEmployeeId  int            -- satpam
```

- Validasi `@OperatorEmployeeId` punya jabatan dengan `is_gate_operator = 1`; kalau tidak,
  RAISERROR.
- Validasi UID seperti `SIS_EmployeeCard_Manage` CREATE.
- `issued_by_employee_id = @OperatorEmployeeId`.
- Satu transaksi: nonaktifkan kartu lama (kalau diminta), lalu insert kartu baru.

**`SIS_Gate_UpdateEmployee`** — ubah data karyawan dari gate.

```
@EmployeeId          int
@EmployeeName        varchar(150)
@Phone               varchar(30)
@OperatorEmployeeId  int
```

- **Hanya `employee_name` dan `phone`.** `resource_id`, `division_id`, `position_id` TIDAK
  boleh diubah lewat SP ini — jangan sediakan parameternya sama sekali. Resource menentukan
  siapa dibayar untuk hasil produksi, itu keputusan supervisor, bukan satpam.
- Validasi `@OperatorEmployeeId` seperti di atas.
- Tulis satu baris `employee_change_log` per field yang benar-benar berubah, `source = 'GATE'`.

### `sql/sp_Attendance.sql`

- **`SIS_Attendance_Report`** (@DateFrom, @DateTo, @DivisionId, @ResourceId, @EmployeeId):
  satu baris per sesi. Kolom: tanggal, nama, kode, divisi, resource, jam masuk, jam pulang,
  durasi menit, status, flag, sumber. Sesi ANOMALI ikut muncul dengan jam pulang kosong.
- **`SIS_Attendance_Anomali`** (@DateFrom, @DateTo): hanya `session_status = 'ANOMALI'` —
  antrian kerja halaman Koreksi.
- **`SIS_Attendance_Manage`** — `@Action` = UPDATE / CREATE_MANUAL / DELETE.
  - UPDATE: koreksi `check_in_at` / `check_out_at`; set `session_status = 'CLOSED'`,
    `session_flag = 'DIKOREKSI'`. Tolak kalau `check_out_at < check_in_at`.
  - CREATE_MANUAL: sesi untuk karyawan yang kartunya hilang/lupa tap, `entry_source = 'MANUAL'`,
    `remarks` wajib diisi.
  - DELETE: soft delete + `remarks` wajib.
  - **Catatan:** izin/sakit/cuti **tidak** ditangani prompt ini. Tidak ada tap = tidak ada
    baris. Jangan buat tabel atau kolom untuk itu.

---

## 4. API — `TerakarsaApp.API`

### 4.1 Autentikasi gate

`RequireGateApiKeyAttribute` — header **`X-Gate-Api-Key`**, dicocokkan dengan
`GateService:ApiKey` di appsettings. Polanya **persis meniru** `RequirePrintApiKeyAttribute`
(file `TerakarsaApp.API/Authorization/RequirePrintApiKeyAttribute.cs`). Terpisah dari JWT,
`X-Station-Token`, dan `X-Print-Api-Key`.

`created_by` untuk semua mutasi dari gate diisi user sistem `gate_system`, id dibaca dari
appsettings `Gate:SystemUserId` — pola yang sama dengan `Station:SystemUserId`. Pelaku
sebenarnya (satpam) ada di kolom `*_by_employee_id`.

### 4.2 `GateController` — `api/gate`, `[RequireGateApiKey]`, **tanpa** `[Authorize]`

| Endpoint | Isi |
|---|---|
| GET `cards` | `SIS_Gate_CardSync` → master kartu + master karyawan + `serverTime` |
| POST `taps` | body: **array** tap (`tapUid`, `cardUid`, `tappedAt`, `confirmAction`, `isOfflineReplay`). Server mengurutkan menurut `tappedAt` lalu memanggil `SIS_Gate_Tap` satu per satu. Response: array hasil, urutan sama dengan input. Satu tap gagal tidak membatalkan tap lain |
| GET `counts` | `SIS_Gate_Counts` |
| GET `pending?mode=` | `SIS_Gate_Pending` |
| POST `cards/register` | `SIS_Gate_RegisterCard` |
| POST `employees/update` | `SIS_Gate_UpdateEmployee` |

`gateCode` diambil dari body/query, bukan hardcode. Dua endpoint terakhir **tidak boleh**
diantrekan offline.

### 4.3 `AttendanceController` — `api/attendance`, `[Authorize]` + `[RequireModule("HR_ATTENDANCE")]`

CRUD kartu (`SIS_EmployeeCard_*`), rekap, anomali, koreksi. Pola standar seperti controller
master lain.

### 4.4 DTO

File baru `TerakarsaApp.Shared/Attendance/` — satu file per area, dipakai bersama oleh API,
Client, dan GateApp.

---

## 5. Project baru: `TerakarsaApp.GateApp`

**WPF + BlazorWebView (Blazor Hybrid)**, .NET 10, ditambahkan ke `TerakarsaApp.slnx`. UI ditulis
dalam `.razor` — XAML hanya untuk window pembungkus.

### 5.1 Window & ukuran layar

`MainWindow.xaml`: `WindowState="Maximized"`, `WindowStyle="None"`, `Topmost="True"`, satu
`BlazorWebView` memenuhi window. Tombol keluar aplikasi hanya dari dalam menu satpam.

Target perangkat: tablet 10 inci, 1920×1280 fisik, **skala tampilan Windows 150%** → UI dirancang
untuk **1280×853 CSS px**. Semua tombol dan baris daftar yang bisa disentuh **minimal 48 px
tinggi**; baris daftar karyawan 64 px. Tanpa scroll di layar utama; daftar panjang boleh digulir.

### 5.2 Konfigurasi `appsettings.json`

```json
{
  "GateService": {
    "ApiBaseUrl": "http://...",
    "ApiKey": "harus sama persis dengan GateService:ApiKey di API",
    "GateCode": "GATE-UTAMA",
    "CardSyncSeconds": 300,
    "QueueFlushSeconds": 10,
    "TapCooldownSeconds": 30,
    "ClockDriftWarningSeconds": 120,
    "MenuIdleTimeoutSeconds": 60
  }
}
```

### 5.3 SQLite lokal (`Microsoft.Data.Sqlite`, file `gate.db` di folder exe)

- `cards` dan `employees` — **cache murni**, ditimpa penuh tiap sync berhasil. Kalau korup:
  hapus file, sync ulang. Tidak pernah jadi sumber kebenaran.
- `tap_queue` — `tap_uid`, `card_uid`, `tapped_at`, `confirm_action`, `sent` (bit).
  Antrian dikirim **urut `tapped_at`**; baris yang sudah terkirim dibersihkan setelah 7 hari.

### 5.4 Services

- `GateApiClient` — HttpClient dengan header `X-Gate-Api-Key` (pola `PrintApiClient`).
- `CardSyncService` — background, tiap `CardSyncSeconds`. Sekaligus membandingkan `serverTime`
  dengan jam lokal; selisih > `ClockDriftWarningSeconds` → flag peringatan ke UI.
- `TapQueueService` — background, tiap `QueueFlushSeconds`. Kirim antrian berurutan; sukses →
  tandai `sent`. Gagal → biarkan, coba lagi siklus berikutnya. Tidak pernah crash.
- Status online/offline diturunkan dari keberhasilan panggilan terakhir.

### 5.5 Alur tap

1. Input tersembunyi selalu di-fokus; reader "mengetik" UID + Enter.
2. UID di-pad nol jadi 10 digit. Panjang/format tidak valid → layar tolak, tidak masuk antrian.
3. Cooldown 30 detik dicek **lokal** dulu (dari antrian), supaya tap dobel tidak membebani API.
4. Generate `tap_uid` (GUID), tulis ke `tap_queue`.
5. **Online** → kirim langsung, tampilkan hasil dari server.
   **Offline** → tampilkan nama + resource dari cache SQLite dan label "Tersimpan (offline)",
   **tanpa** menyatakan masuk/pulang — penentuan in/out milik server.
6. Layar hasil tampil **3 detik** lalu kembali ke layar tunggu. Tidak ada tombol OK.
7. `PERLU_KONFIRMASI` → layar konfirmasi, tidak auto-dismiss; ada tombol "Nanti saja" yang
   membiarkan sesi apa adanya supaya antrian pagi tidak macet.

### 5.6 Layar (`Pages/Gate.razor` + komponen)

Markup acuan untuk semua layar di bawah ada di `claude prompt/mockup_70_absensi_rfid.html`,
bagian `Gate 1`–`Gate 9`. Nomor di sini cocok dengan nomor di file itu.

1. **Tunggu** — jam besar, tanggal, indikator koneksi (hijau/kuning + jumlah antrian), tiga
   angka dari `SIS_Gate_Counts`, tombol "Menu".
2. **Check in berhasil** — latar hijau, nama besar, jabatan + kode, badge resource berwarna
   `color_hex`, jam masuk.
3. **Check out berhasil** — latar biru, nama, badge resource, jam masuk + jam pulang + durasi.
4. **Ditolak** — latar merah, pesan, UID yang terbaca (untuk didaftarkan satpam).
5. **Konfirmasi sesi panjang** — nama, jam ambil kartu, jam sekarang, durasi, tiga tombol:
   `LEMBUR — baru selesai kerja`, `KARTU LUPA DIKEMBALIKAN`, `Nanti saja`.
6. **Offline** — banner kuning di atas + jumlah antrian; layar hasil menampilkan nama, resource,
   jam, dan "TERSIMPAN (OFFLINE)".
7. **Menu satpam** — dibuka lewat tombol "Menu" lalu **tap kartu satpam**
   (`is_gate_operator = 1` dari cache). Kartu biasa ditolak. Menu tertutup sendiri setelah
   `MenuIdleTimeoutSeconds`. Isi:
   - **Daftar kartu** → layar 8
   - **Ubah data karyawan** → layar 9
   - Belum ambil kartu (`SIS_Gate_Pending` mode `BELUM_AMBIL`)
   - Belum kembalikan kartu (mode `BELUM_KEMBALI`)
   - Status koneksi & antrian, tombol sync paksa, tombol keluar aplikasi
8. **Daftar kartu** — dua kolom. Kiri: daftar karyawan **belum punya kartu aktif** (mode
   `BELUM_PUNYA_KARTU`), dikelompokkan per divisi/resource, baris 64 px. Kanan: karyawan yang
   dipilih, kotak "Tempelkan kartu baru" yang menampilkan UID begitu kartu di-tap, pilihan
   **Kartu tetap / Kartu sementara**, tombol Simpan.
   - Kalau karyawan terpilih **sudah punya kartu aktif**, munculkan pilihan tambahan:
     nonaktifkan kartu lama atau biarkan aktif juga (`@DeactivateOldCards`).
   - Ada kotak cari untuk karyawan yang sudah punya kartu (kasus ganti kartu), tapi daftar
     default-nya yang belum punya kartu — supaya rollout 150 kartu tinggal mengambil dari atas
     sampai daftar habis.
   - **Butuh online.** Kalau offline, layar ini menolak dengan pesan jelas (UID kembar harus
     dicek ke server, tidak bisa diantrekan).
9. **Ubah data karyawan** — pilih karyawan, ubah **nama** dan **no. telepon** saja. Divisi, line
   dan jabatan ditampilkan **terkunci** dengan keterangan "hanya bisa diubah dari admin panel".
   Butuh online.

Teks besar, kontras tinggi. Karena karyawan tidak melihat layar, jangan mengandalkan layar saja
untuk verifikasi — lihat bunyi di bawah.

### 5.7 Suara

File WAV di folder exe, diputar lewat `System.Media.SoundPlayer`. Bunyi **berbeda** per hasil.
Di perangkat 10 inci yang hanya dilihat satpam, ini lapis verifikasi utama: satpam sering
menunduk mencari kartu di rak dan tidak melihat layar.

| Hasil | Bunyi |
|---|---|
| CHECK_IN | bip pendek 1× |
| CHECK_OUT | bip pendek 2× |
| DUPLIKAT | bip pelan 1× |
| Ditolak / perlu konfirmasi | bip panjang rendah |

Kalau file WAV tidak ada, aplikasi tetap jalan (log warning saja).

Speaker bawaan tablet 10 inci kecil dan mudah tenggelam di keramaian pagi. Siapkan **speaker USB
atau 3,5 mm kecil** di meja satpam. Dari sisi aplikasi tidak ada yang berubah — Windows sudah
mengarahkan suara ke perangkat output yang dipilih — tapi sediakan **pengatur volume di menu
satpam** (Status & sinkronisasi) dan tombol **tes bunyi** untuk tiap hasil, supaya satpam bisa
memastikan speaker hidup tanpa harus menunggu ada yang tap.

### 5.8 `README.md` GateApp

Isi: cara setting `appsettings.json`, **cara menyetel skala tampilan Windows ke 150%**, cara
pasang auto-start, cara ganti `GateCode`, penjelasan `gate.db` (boleh dihapus kapan saja),
syarat **WebView2 Runtime** terpasang, catatan bahwa jam tablet harus benar (nyalakan Windows
time sync), dan catatan bahwa tablet sebaiknya selalu tercolok listrik — baterai hanya cadangan
saat padam.

---

## 6. UI Client — satu menu, tiga tab

Module baru, file `sql/seed_attendance_module.sql` (idempotent, pola
`seed_report_produksi_module.sql`):

```
Code = 'HR_ATTENDANCE', Name = 'Absensi', Category = 'Order', SubCategory = NULL,
Route = 'attendance', Icon = 'fe fe-clock'
```

Assign ke semua user `Role = 'Admin'`.

Halaman `Pages/Attendance.razor` (route `/attendance`), tiga tab. Tata letak dan isi kolom tiap
tab mengikuti `claude prompt/mockup_70_absensi_rfid.html` bagian `Admin 1`–`Admin 3` — tapi
dibangun dengan Bootstrap mengikuti halaman master TMOS yang sudah ada, bukan menyalin CSS
mockup.

**Tab 1 — Kartu Karyawan**
CRUD `employee_cards`. Kolom: UID, nama (badge "Sementara" di sebelah nama kalau
`card_type = 'SEMENTARA'`), kode, divisi, jabatan, resource, status. Filter: pencarian +
"hanya aktif". Form tambah punya **mode tap**: fokus ke input UID supaya kartu bisa langsung
di-tap pakai reader yang dicolok ke PC admin. Tombol Nonaktifkan terpisah dari Hapus.

**Tab 2 — Rekap Absensi**
Filter: rentang tanggal (default minggu berjalan), divisi, resource, karyawan. Tabel dari
`SIS_Attendance_Report`. Baris ANOMALI ditandai warna. Ringkasan di atas tabel: jumlah sesi,
jumlah anomali, total jam.

**Tab 3 — Koreksi Absensi**
Daftar `SIS_Attendance_Anomali`. Per baris: isi jam pulang, atau hapus sesi, atau tandai sudah
benar. Plus tombol "Tambah Absensi Manual" untuk karyawan yang kartunya hilang. Semua aksi
wajib isi `remarks` dan minta konfirmasi.

Master Jabatan (`positions`) ditambah checkbox **"Boleh buka menu gate"** (`is_gate_operator`).
Master Resource ditambah input **warna** (`color_hex`, color picker + preview).
Master Karyawan ditambah input **No. telepon** (`phone`).

---

## 7. Verifikasi

1. `dotnet build TerakarsaApp.slnx -v q` sukses. Lalu buka
   `claude prompt/mockup_70_absensi_rfid.html` berdampingan dengan hasil jadi: ke-9 layar gate
   harus cocok dalam struktur, ukuran teks, warna latar per hasil, dan kata-kata di layar.
2. Reader dicolok, tap kartu di Notepad → muncul 10 digit + Enter. Angka **sama persis** tiap
   kali kartu yang sama di-tap.
3. Tab Kartu Karyawan: daftarkan 3 kartu lewat mode tap. UID yang sama didaftarkan ke karyawan
   lain → ditolak dengan pesan menyebut nama pemilik lama.
4. GateApp online: tap kartu A → layar check in hijau, nama + badge resource benar, bunyi 1 bip.
   Tap lagi dalam 30 detik → DUPLIKAT. Tunggu lewat 30 detik, tap lagi → check out, bunyi 2 bip.
5. Matikan API. Tap kartu B dan C → layar tetap menampilkan nama dari cache, indikator jadi
   kuning, hitungan antrian naik. Nyalakan API → antrian terkirim, dan **jam tercatat adalah
   jam saat tap**, bukan jam pengiriman.
6. Kirim ulang `tap_uid` yang sama ke `POST taps` → tidak ada sesi ganda, hasil identik.
7. Buat sesi OPEN dengan `check_in_at` 16 jam lalu, lalu tap → layar konfirmasi muncul. Pilih
   LEMBUR → sesi CLOSED dengan jam pulang. Ulangi, pilih LUPA KEMBALIKAN → ANOMALI, jam pulang
   kosong, muncul di tab Koreksi.
8. Buat sesi OPEN kemarin, lalu tap di dalam jendela check-in (mis. 07:00, `start_time` 08:00)
   → sesi lama jadi ANOMALI, sesi baru hari ini terbuka, **tap tidak gagal**.
9. Tap kartu yang tidak terdaftar → layar merah + UID terbaca, dan barisnya tetap tercatat di
   `gate_taps`.
10. Menu satpam: tap kartu karyawan biasa → ditolak. Tap kartu jabatan `is_gate_operator = 1`
    → menu terbuka. Diamkan 60 detik → menu tertutup sendiri.
11. Daftar kartu dari gate: pilih karyawan dari daftar "belum punya kartu", tap kartu kosong,
    pilih **Kartu tetap**, simpan → kartu terdaftar, nama karyawan **hilang dari daftar**.
    Ulangi untuk satu karyawan yang sudah punya kartu, pilih **Kartu sementara** tanpa
    menonaktifkan kartu lama → karyawan itu punya 2 kartu aktif, **dua-duanya bisa dipakai tap
    dan tetap satu sesi**.
12. Matikan API, buka Daftar Kartu → ditolak dengan pesan jelas, tidak masuk antrian.
13. Ubah data karyawan dari gate: ganti no. telepon → tersimpan, dan ada baris baru di
    `employee_change_log` dengan nama satpam. Pastikan **tidak ada cara apa pun** mengubah
    resource/divisi/jabatan dari layar ini.
14. Majukan jam tablet 10 menit → peringatan selisih jam muncul di layar.
15. Divisi dengan `start_time` berbeda di `work_schedule_defaults` → jendela check-in ikut
    bergeser; uji minimal dua divisi dengan jam berbeda.
16. Jalankan di tablet pada skala 150%: semua tombol tersentuh nyaman dengan jari, tidak ada
    teks terpotong, tidak ada scroll di layar tunggu.

## Urutan deploy

1. `sql/alter_70_absensi_rfid.sql`
2. `sql/sp_EmployeeCard_Manage.sql`, `sql/sp_EmployeeCard_Select.sql`
3. `sql/sp_Gate.sql`, `sql/sp_Attendance.sql`
4. `sql/seed_attendance_module.sql`
5. Deploy API (isi `GateService:ApiKey` dan `Gate:SystemUserId`)
6. Deploy GateApp ke tablet gate

## Yang TIDAK boleh dilakukan

- Jangan menulis apa pun ke kartu RFID — **hanya baca UID**.
- Jangan menaruh logika penentuan masuk/pulang di GateApp. Semua keputusan di `SIS_Gate_Tap`.
  GateApp hanya mengantre dan menampilkan.
- Jangan memakai `SYSDATETIME()` untuk `check_in_at`/`check_out_at` — selalu `tapped_at`.
- Jangan membuat jalur apa pun untuk mengubah `resource_id`, `division_id`, atau `position_id`
  dari gate. Resource menentukan siapa dibayar di Laporan Hanca.
- Jangan mengantrekan pendaftaran kartu atau perubahan data karyawan saat offline.
- Jangan membuat tabel/kolom untuk izin, sakit, cuti, atau perhitungan terlambat/lembur
  bernilai upah. Prompt ini hanya mencatat jam mentah.
- Jangan menyambungkan `employees` ke `users`, dan jangan memakai `UserModules` untuk akses
  satpam.
- Jangan mengubah `TerakarsaApp.PrintService`, alur station (`X-Station-Token`), atau SP
  workflow log.
- Jangan auto-execute script SQL — developer menjalankan sendiri.

Akhiri dengan: daftar file dibuat/diubah + script SQL yang harus dijalankan manual.

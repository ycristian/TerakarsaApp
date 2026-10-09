# Prompt 58 — Absensi & Pegawai di Station

## Konteks

Belum ada RFID, jadi absensi harian diisi manual oleh PIC line lewat station. Tim kecil (per line/resource) yang bertanggung jawab atas data kehadiran dan status pegawainya sendiri. Nanti data RFID akan mengisi tabel yang sama (`source = 'RFID'`), dan PIC tinggal mengoreksi.

Station sudah punya konteks **divisi** (`CurrentStation.DivisionId`) dan **resource/line operator sesi** (`EffectiveResourceId`). Semua fitur di prompt ini memakai dua konteks itu — client tidak pernah mengirim `division_id`.

Mockup UI sudah disetujui (3 layar: Input, Rekap 4 hari, Pegawai). **Acuan tampilan: [`station_absensi_mockup.html`](station_absensi_mockup.html)** di folder yang sama — ikuti susunan, warna status, dan ukurannya, tapi tetap pakai Bootstrap & komponen yang sudah ada di station (bukan menyalin CSS mockup mentah-mentah). Data di mockup hanya contoh. Ringkasan perilakunya ada di bagian D.

---

## A. Skema — `sql/alter_58_station_absensi.sql` (idempotent, manual)

### 1. Kolom baru di `employees`

| Kolom | Tipe | Arti |
|---|---|---|
| `phone_no` | `varchar(20) NULL` | No. telp, disimpan **hanya digit** (normalisasi di SP) |
| `inactive_date` | `date NULL` | Tanggal terakhir kerja, diisi saat dinonaktifkan |
| `inactive_reason` | `varchar(20) NULL` | `RESIGN` / `HABIS_KONTRAK` / `DIBERHENTIKAN` / `PINDAH_DIVISI` |

Index filtered untuk pencarian no. telp: `(phone_no) WHERE deleted_at IS NULL AND phone_no IS NOT NULL` — **bukan unique** (keunikan dicek di SP supaya bisa menawarkan "aktifkan lagi").

### 2. Tabel baru `employee_attendances`

| Kolom | Tipe | Keterangan |
|---|---|---|
| `attendance_id` | int identity PK | |
| `employee_id` | int NOT NULL FK `employees` | |
| `attendance_date` | date NOT NULL | |
| `resource_id` | int NOT NULL FK `resources` | line tempat absen dicatat |
| `status` | char(1) NOT NULL | `H` Hadir, `I` Izin, `S` Sakit, `A` Alpa, `C` Cuti — CHECK constraint |
| `check_in` | time(0) NULL | hanya boleh terisi kalau `status = 'H'` |
| `check_out` | time(0) NULL | hanya boleh terisi kalau `status = 'H'` |
| `note` | varchar(200) NULL | keterangan (mis. "Surat dokter") |
| `source` | varchar(10) NOT NULL default `'MANUAL'` | `MANUAL` / `RFID` (RFID belum dipakai) |
| `station_id` | int NULL FK `stations` | station yang terakhir menyimpan |
| `recorded_by_resource_id` | int NOT NULL FK `resources` | operator sesi saat pertama diisi |
| `updated_by_resource_id` | int NULL FK `resources` | operator sesi saat terakhir diubah |
| kolom audit standar | | `created_by`/`updated_by` = user `station_system` |

- Unique filtered: `(employee_id, attendance_date) WHERE deleted_at IS NULL`
- CHECK: `status = 'H' OR (check_in IS NULL AND check_out IS NULL)`
- Index `(resource_id, attendance_date)` untuk list & rekap

Sinkronkan `sql/create_tables_tmos_final.sql` (kolom baru `employees` + tabel baru, beserta komentar singkat).

---

## B. Aturan bisnis (ditegakkan di SP)

### Tanggal
- Hanya boleh input/edit untuk **hari ini sampai 4 hari ke belakang** (`CAST(SYSDATETIME() AS date)` minus 4). Di luar itu → `RAISERROR('Absen hanya bisa diisi untuk hari ini sampai 4 hari ke belakang.', 16, 1)`. Tanggal masa depan ditolak.
- Tidak ada lock. Selama masih dalam 4 hari, data bebas diubah.

### Cakupan pegawai
- Yang tampil di Input & Rekap untuk sebuah tanggal = pegawai `is_active = 1` dengan `resource_id = @ResourceId`, **ditambah** pegawai yang sudah punya baris absen di resource itu pada tanggal tersebut (supaya riwayat tetap tampil walau orangnya sudah nonaktif/pindah).
- Simpan absen: pegawai wajib `resource_id = @ResourceId` (resource sesi) **atau** sudah punya baris absen di resource itu pada tanggal tsb. Selain itu → `RAISERROR('Pegawai ini bukan anggota line ini.', 16, 1)`.

### Jadwal kerja & telat
- Pakai `work_schedule_defaults` divisi station, `day_of_week` (1 = Senin … 7 = Minggu) dari tanggal absen. Hati-hati dengan `DATEFIRST` — hitung day_of_week tanpa bergantung setting sesi.
- **Telat** = `status = 'H'` dan `check_in > start_time`. Tidak disimpan, dihitung saat dibaca.
- Hari `is_working_day = 0` (atau tidak ada baris jadwal) = **Libur**. Input tetap boleh (mis. masuk di hari libur); di Rekap, hari libur tanpa data ditampilkan `–`, bukan "belum diisi".

### Simpan (upsert)
- Satu kali Simpan bisa berisi banyak baris → `@ItemsJson` + `OPENJSON` (pola yang sudah dipakai di repo, mis. `SIS_DailyPlan_Manage`).
- Baris ada → UPDATE (isi `updated_*` + `updated_by_resource_id`). Belum ada → INSERT. Satu transaksi; satu baris gagal = semua batal, pesan error menyebut nama pegawainya.
- Status selain `H` → `check_in`/`check_out` dipaksa NULL.
- `check_out` lebih kecil dari `check_in` **boleh** (lewat tengah malam) — jangan ditolak.

### Tombol "Belum → Hadir"
- Mengisi semua pegawai yang **belum punya baris** di tanggal itu menjadi `H` dengan `check_in = start_time` jadwal hari itu (kalau libur/tanpa jadwal → `check_in` NULL).
- Pegawai yang sudah diisi tidak disentuh.
- Dijalankan di UI sebagai perubahan lokal (belum tersimpan) — baru masuk DB saat Simpan. Tidak perlu SP terpisah.

### Pegawai baru
- Wajib: Nama, No. telp, Jabatan (`positions`, semua posisi aktif).
- Otomatis: `division_id` = divisi station, `resource_id` = resource sesi, `join_date` = hari ini, `is_active = 1`, `employee_code` = hasil `SIS_Employee_NextCode` divisi tsb (tanpa override di station).
- Normalisasi no. telp: buang semua non-digit; awalan `62` diubah jadi `0`. Kurang dari 9 digit → ditolak.
- Cek no. telp terhadap `employees` yang `deleted_at IS NULL`:
  - Sudah dipakai pegawai **aktif** → `RAISERROR('PHONE_ACTIVE|<nama>|<resource>', 16, 1)` → UI tampilkan "No. telp sudah dipakai <nama> (<line>)". Tidak bisa disimpan.
  - Sudah dipakai pegawai **nonaktif** → `RAISERROR('PHONE_INACTIVE|<employee_id>|<nama>|<resource>', 16, 1)` → UI tampilkan tawaran **"Aktifkan lagi?"**.

### Nonaktifkan
- Wajib `inactive_date` (tidak boleh di masa depan) dan `inactive_reason`.
- Hanya pegawai aktif dengan `resource_id = @ResourceId`.
- Data absen dan log lama tidak disentuh.

### Aktifkan lagi
- Boleh oleh PIC tanpa approval.
- Set `is_active = 1`, kosongkan `inactive_date` & `inactive_reason`, **pindahkan** `division_id` & `resource_id` ke divisi station & resource sesi.
- Kalau pindah divisi, `employee_code` **tidak** diubah.

### Jejak perubahan
Tidak ada notifikasi. Cukup tercatat: `created_by/updated_by` (station_system), `station_id`, dan `*_by_resource_id` di absen. Untuk create/nonaktif/aktifkan pegawai, catat ke activity log yang sudah ada (Prompt 47) kalau polanya mendukung pencatatan dari station; kalau tidak, laporkan di ringkasan akhir dan jangan buat mekanisme baru.

---

## C. SP & API

### SP baru

| SP | Isi |
|---|---|
| `SIS_StationAttendance_Manage` | `@Action = 'SAVE'`, `@ResourceId`, `@StationId`, `@AttendanceDate`, `@ItemsJson` (employee_id, status, check_in, check_out, note) |
| `SIS_StationAttendance_List` | `@DivisionId`, `@ResourceId`, `@AttendanceDate` → baris pegawai + absennya (boleh NULL = belum diisi) + `IsLate`; result kedua: jadwal hari itu (`IsWorkingDay`, `StartTime`, `EndTime`) + ringkasan (Hadir/Izin/Sakit/Alpa/Belum) |
| `SIS_StationAttendance_Recap` | `@DivisionId`, `@ResourceId`, `@EndDate` → grid 5 tanggal (EndDate−4 … EndDate) per pegawai: kode sel `H`/`T`(telat)/`I`/`S`/`A`/`C`/`?`(belum)/`–`(libur), jumlah hadir / hari kerja; plus ringkasan (% kehadiran, telat, alpa, belum diisi) |
| `SIS_StationAttendance_PendingDates` | `@DivisionId`, `@ResourceId` → tanggal dalam 4 hari terakhir yang masih ada pegawai belum diisi (hari kerja saja) + jumlahnya |
| `SIS_StationEmployee_Manage` | `@Action` = `CREATE` / `SETINACTIVE` / `REACTIVATE`, `@DivisionId`, `@ResourceId`, dll. |
| `SIS_StationEmployee_List` | `@ResourceId`, `@IsActive`, `@Search` (nama/no telp) → kode, nama, jabatan, no telp, tgl nonaktif, alasan |

`% kehadiran` = hari hadir (H + telat) ÷ hari kerja yang sudah lewat, untuk pegawai aktif di rentang itu.

### SP lama yang diubah
- `SIS_Employee_Manage` & `SIS_PpicEmployee_Manage`: tambah `@PhoneNo varchar(20) = NULL`, di UPDATE pakai `COALESCE` (default NULL — caller lama tidak menghapus no. telp). Normalisasi sama seperti di station.
- `SIS_Employee_GetAll/GetById` & `SIS_PpicEmployee_List/GetById`: expose `PhoneNo`, `InactiveDate`, `InactiveReason`.
- Form Master Karyawan & PPIC Karyawan: tambah field No. telp (opsional di sana).

### Endpoint (di `StationDeviceController`, `[RequireStationToken]`)
Semua memakai `CurrentStation.DivisionId` dan `EffectiveResourceId(resourceId)`; resource sesi wajib ada, kalau 0 → `BadRequest("Operator wajib dipilih.")`.

- `GET attendance?resourceId=&date=`
- `POST attendance` (simpan batch)
- `GET attendance/recap?resourceId=&endDate=`
- `GET attendance/pending-dates?resourceId=`
- `GET station-employees?resourceId=&isActive=&search=`
- `POST station-employees` (create)
- `POST station-employees/{id}/inactive`
- `POST station-employees/{id}/reactivate`
- `GET positions` (dropdown jabatan, kalau belum ada endpoint station-nya)

DTO di `TerakarsaApp.Shared`, satu file `StationAttendanceDtos.cs`.

---

## D. UI — tab baru **Absen** di `StationDevice.razor`

Tab "Absen" sejajar tab yang sudah ada, dengan **badge angka** = jumlah pegawai aktif yang belum diisi hari ini (hari kerja saja; libur → tanpa badge). Di dalamnya segmented toggle 3 sub-tab. Supaya `StationDevice.razor` tidak makin besar, buat komponen terpisah (mis. `Components/Station/AttendanceTab.razor` + 3 komponen sub-tab).

### 1. Input
- Chip tanggal: hari ini + 4 hari ke belakang (label hari + dd/MM). Tanggal yang masih ada yang belum diisi diberi warna kuning + titik, dengan keterangan di bawah ("29/09 masih ada 2 orang belum diisi"). Tanggal ke-5 ke belakang tampil abu-abu, tidak bisa dipilih.
- Ringkasan 5 kotak: Hadir / Izin / Sakit / Alpa / Belum.
- Cari nama + tombol **Belum → Hadir**.
- Per pegawai: nama, jabatan, 5 tombol status (H I S A C, min. 44px area sentuh). `H` → muncul input jam masuk & jam pulang; selain `H` → input keterangan. Jam masuk melewati jadwal → border kuning + teks "Telat N menit".
- Pegawai yang belum diisi berlatar abu muda dan tampil di bawah.
- Bar bawah sticky: "N perubahan belum disimpan" + tombol **Simpan**. Pindah tanggal/sub-tab/tab dengan perubahan belum disimpan → konfirmasi dulu.

### 2. Rekap 4 hari
- Grid nama × 5 tanggal (kolom hari ini disorot) + kolom "Hadir x/y". Sel berwarna sesuai kode (H hijau, T kuning, I biru, S oranye, A merah, ? abu bergaris putus, – abu).
- Tap sel → pindah ke sub-tab Input di tanggal itu, scroll ke pegawai tsb.
- Legenda + ringkasan (% kehadiran, telat, alpa, belum diisi).

### 3. Pegawai
- Toggle **Aktif (n) / Nonaktif (n)** + tombol **+ Pegawai**.
- Form pegawai baru (inline card): Nama, No. telp (`inputmode="tel"`), Jabatan; Divisi & Line tampil read-only dari station; keterangan "Langsung aktif dan bisa diabsen". Error `PHONE_INACTIVE` → kotak merah dengan link **Aktifkan lagi?** (memanggil reactivate, lalu form ditutup).
- Cari nama / no. telp.
- List aktif: nama, jabatan · no. telp, tombol **Nonaktifkan** → baris membuka form inline (Terakhir kerja = date, default hari ini; Alasan = dropdown) + Batal / Nonaktifkan (merah).
- List nonaktif: nama, jabatan, tgl nonaktif, alasan, tombol **Aktifkan lagi**.
- Keterangan di bawah: "Pegawai nonaktif tidak muncul di Input & Rekap. Data lamanya tetap tersimpan."

Setelah pegawai ditambah/dinonaktifkan/diaktifkan, dropdown penjahit di tab lain (Prompt 32, `employees/{resourceId}`) ikut ter-refresh.

---

## Yang TIDAK boleh dilakukan

- Menyentuh SP workflow/bundle/log (`SIS_WorkflowLog_Manage`, `SIS_Bundle_Manage`, dll.) atau logika lock/settlement tab OUT
- Membuat lock, approval, atau notifikasi untuk absensi
- Menghitung payroll/lembur dari absensi
- Integrasi RFID (cukup kolom `source`)
- Mengubah `[RequireModule]` atau cakupan module `MASTER_EMPLOYEE` / `PPIC_EMPLOYEE` selain tambahan field no. telp
- Menerima `division_id` dari client di endpoint station
- Hard delete pegawai atau absen
- Hardcode `division_id`, `resource_id`, atau `position_id`
- Filter `is_active` di report/riwayat yang sudah ada

---

## Urutan deploy

1. `sql/alter_58_station_absensi.sql`
2. SP baru: `SIS_StationAttendance_*`, `SIS_StationEmployee_*`
3. SP diubah: `SIS_Employee_Manage`, `SIS_Employee_Select`, `SIS_PpicEmployee_Manage`, `SIS_PpicEmployee_Select` (sesuaikan nama file yang ada)
4. Deploy API + Client
5. Pastikan `work_schedule_defaults` sudah terisi untuk divisi yang memakai station — kalau kosong, semua hari dianggap libur dan tidak ada tanda telat (perilaku benar, bukan bug)

---

## Verifikasi

1. Pilih tanggal 5 hari lalu lewat request manual → ditolak SP
2. Tambah pegawai baru → langsung muncul di Input, kode `<division_code>-NNNN`, divisi & line sesuai station
3. Tambah pegawai dengan no. telp `+62 812-…` → tersimpan `0812…`; tambah lagi dengan nomor sama → ditolak (aktif) / ditawari aktifkan lagi (nonaktif)
4. Aktifkan lagi pegawai dari line/divisi lain → pindah ke line station ini, kode tidak berubah
5. Belum → Hadir lalu Simpan → semua yang belum terisi jadi H dengan jam masuk = jadwal; yang sudah diisi tidak berubah
6. Isi jam masuk lewat jadwal → tampil telat di Input dan `T` di Rekap
7. Status Sakit dengan jam masuk dikirim lewat request manual → jam dikosongkan
8. Nonaktifkan pegawai → hilang dari Input hari ini, tapi absen yang sudah ada di tanggal lalu tetap tampil di Rekap; hilang dari dropdown penjahit
9. Request dengan `resourceId` lain pada station yang terkunci → tetap memakai resource default station
10. Update pegawai lewat Master Karyawan tanpa menyentuh no. telp → no. telp tidak hilang
11. Hari libur di jadwal → Rekap `–`, tanpa badge di tab Absen

---

## Output yang diharapkan

Daftar file dibuat/diubah, script SQL yang harus dijalankan manual berikut urutannya (markdown link), dan catatan apakah pencatatan activity log dari station bisa dipakai.

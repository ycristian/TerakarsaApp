# Prompt 36 — Fondasi Dashboard Target: Flag Divisi/Resource & Setting Jam Kerja Default

> Bagian 1 dari 3 (36 → 37 → 38). Prompt ini HANYA membuat skema, flag master, dan modul
> setting default. Halaman planning harian PPIC = Prompt 37. Dashboard TV = Prompt 38.
> Jangan kerjakan keduanya sekarang.

## Konteks

Akan dibangun dashboard target kerja harian yang ditampilkan di TV lantai produksi. Fondasinya
tiga hal:

1. **Flag di master divisi** — divisi mana yang tampil di dashboard, dan apakah tampilannya
   ringkas per divisi atau rinci per resource (line).
2. **Flag di master resource** — resource mana yang ikut dihitung/ditampilkan.
3. **Setting default** — jam kerja per divisi per hari (Senin–Minggu), jam istirahat, dan
   target pcs/orang/hari per divisi. Default ini HANYA dipakai untuk prefill form PPIC dan
   sebagai fallback tampilan bila PPIC belum input. Angka yang dipakai dashboard tetap angka
   yang di-save PPIC (Prompt 37).

Istilah tetap yang dipakai di seluruh rangkaian prompt ini:
- **Target** = total pcs yang harus dicapai = `target_per_person × headcount`.
- **Selisih** = capaian aktual dikurangi posisi seharusnya pada jam berjalan. Positif = surplus,
  negatif = defisit.
- **Jam efektif** = rentang jam masuk s.d. jam pulang dikurangi seluruh rentang istirahat.

## 1. Skema SQL

Buat `sql/alter_36_dashboard_target.sql` (manual, idempotent dengan `IF NOT EXISTS` /
`IF COL_LENGTH(...) IS NULL`) DAN perbarui `sql/create_tables_tmos_final.sql` agar tetap
mencerminkan skema terbaru.

### a. Tambahan kolom di `divisions`

```sql
 show_in_dashboard bit not null default 1,          -- tampil di dashboard TV atau tidak
 dashboard_mode varchar(20) not null default 'DIVISION',  -- DIVISION | RESOURCE
 dashboard_sort_order int not null default 0,       -- urutan kartu di dashboard
 default_target_per_person int not null default 0,  -- pcs/orang/hari, untuk prefill PPIC
```

`dashboard_mode` diberi CHECK constraint (`'DIVISION'`, `'RESOURCE'`).

### b. Tambahan kolom di `resources`

```sql
 include_in_dashboard bit not null default 1,       -- ikut dihitung & ditampilkan di dashboard
```

### c. Tabel baru `work_schedule_defaults`

Jam kerja default per divisi per hari dalam minggu.

```sql
CREATE TABLE work_schedule_defaults(
 work_schedule_default_id int primary key identity(1,1),
 division_id int not null
   constraint FK_wsd_divisions foreign key references divisions(division_id),
 day_of_week tinyint not null,              -- 1 = Senin ... 7 = Minggu
 is_working_day bit not null default 1,     -- 0 = libur default (mis. Minggu)
 start_time time(0) not null,
 end_time time(0) not null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

Filtered unique index `UX_wsd_division_day ON work_schedule_defaults(division_id, day_of_week)
WHERE deleted_at IS NULL`.

CHECK: `day_of_week BETWEEN 1 AND 7`. Validasi `end_time > start_time` di SP (bukan CHECK,
supaya pesan errornya bahasa Indonesia).

### d. Tabel baru `work_break_defaults`

Rentang istirahat. Berlaku sistem-wide, boleh dibatasi ke hari tertentu.

```sql
CREATE TABLE work_break_defaults(
 work_break_default_id int primary key identity(1,1),
 break_name varchar(150) not null,          -- mis. 'Istirahat Siang'
 day_of_week tinyint null,                  -- NULL = berlaku semua hari
 start_time time(0) not null,
 end_time time(0) not null,
 sort_order int not null default 0,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

### e. Seed awal — `sql/seed_36_work_schedule_defaults.sql` (idempotent, terpisah)

- Untuk setiap divisi hidup yang belum punya baris `work_schedule_defaults`: isi hari 1–6
  (Senin–Sabtu) `08:00–20:00` `is_working_day = 1`, hari 7 (Minggu) `08:00–20:00`
  `is_working_day = 0`. `created_by` pakai user admin pertama (`SELECT TOP 1 Id FROM Users
  WHERE Role = 'Admin' ORDER BY Id`).
- Dua baris `work_break_defaults` bila belum ada: `Istirahat Siang 12:00–13:00` dan
  `Istirahat Sore 17:00–18:00`, keduanya `day_of_week = NULL`.
- JANGAN mengisi `default_target_per_person` — biarkan 0, diisi manual lewat UI.

## 2. Stored Procedures

### `sql/sp_WorkScheduleDefault_Manage.sql` — `SIS_WorkScheduleDefault_Manage`

`@Action`:
- `SAVE_DIVISION` — simpan 7 baris jam kerja sekaligus untuk satu divisi. Parameter:
  `@DivisionId`, `@DaysJson NVARCHAR(MAX)`, `@UserId`. JSON array of
  `{ dayOfWeek, isWorkingDay, startTime, endTime }`. Pakai OPENJSON, upsert per
  `(division_id, day_of_week)` — update baris hidup yang ada, insert bila belum ada.
  Semua dalam satu transaksi. Validasi: 7 hari lengkap, `end_time > start_time` untuk hari
  yang `is_working_day = 1`.
- `SAVE_BREAK` (`@Id` NULL = insert), `DELETE_BREAK` (`@Id`, soft delete) untuk
  `work_break_defaults`. Validasi `end_time > start_time`.

### `sql/sp_WorkScheduleDefault_Select.sql`

- `SIS_WorkScheduleDefault_List` — semua divisi hidup (termasuk yang `show_in_dashboard = 0`,
  ditandai flag-nya) beserta 7 baris jam kerjanya dan `default_target_per_person`. Divisi yang
  belum punya baris tetap muncul dengan nilai kosong supaya bisa dilengkapi dari UI.
  Kembalikan dua result set: (1) divisi, (2) baris jam kerja.
- `SIS_WorkBreakDefault_List` — daftar istirahat hidup, urut `sort_order`, `start_time`.

### Perluasan SP master yang sudah ada

- `SIS_Division_Manage` — CREATE/UPDATE menerima `@ShowInDashboard`, `@DashboardMode`,
  `@DashboardSortOrder`, `@DefaultTargetPerPerson`. **Parameter baru wajib punya nilai default**
  (`= 1`, `= 'DIVISION'`, `= 0`, `= 0`) supaya pemanggil lama tidak pecah. Validasi
  `@DashboardMode` hanya menerima `DIVISION` / `RESOURCE`.
- `SIS_Division_GetAll` / `SIS_Division_GetById` — tambahkan keempat kolom ke SELECT.
- `SIS_Resource_Manage` — terima `@IncludeInDashboard bit = 1`.
- `SIS_Resource_GetAll` / `SIS_Resource_GetById` — tambahkan kolomnya.

## 3. API

### Perluasan controller master yang ada
- `DivisionController` / `DivisionService` / DTO di `TerakarsaApp.Shared` — tambahkan keempat
  properti baru. Tetap di module `MASTER_DIVISION`.
- `ResourceController` / `ResourceService` / DTO — tambahkan `IncludeInDashboard`. Tetap di
  module `MASTER_RESOURCE`.

### Controller baru `WorkScheduleController` (JWT, module `SETTING_JAM_KERJA`)
- `GET api/work-schedule/defaults` → daftar divisi + jam kerja per hari + target default.
- `PUT api/work-schedule/defaults/{divisionId}` → simpan 7 hari sekaligus.
- `GET api/work-schedule/breaks`, `POST`, `PUT`, `DELETE api/work-schedule/breaks/{id}`.

DTO di file baru `TerakarsaApp.Shared/WorkSchedules/WorkScheduleModels.cs`.

## 4. Blazor Client

### Halaman master yang sudah ada
- **Divisi**: tambahkan di form — checkbox "Tampilkan di Dashboard", dropdown "Mode Dashboard"
  (Per Divisi / Per Resource), input "Urutan Dashboard", input "Target Default (pcs/orang/hari)".
  Di list: kolom badge kecil mode dashboard + ikon bila tidak ditampilkan.
- **Resource**: checkbox "Ikut Dashboard" di form, badge di list.

### Halaman baru `/work-schedule` — "Jam Kerja & Target Default"
Satu halaman, dua section:

1. **Jam Kerja per Divisi** — tabel: baris = divisi, kolom = Senin s.d. Minggu. Tiap sel berisi
   toggle kerja/libur + dua input jam. Tombol simpan per baris divisi (bukan simpan global,
   supaya perubahan satu divisi tidak menimpa yang lain). Di kolom paling kanan input
   "Target default (pcs/orang/hari)" — ikut tersimpan bersama baris divisi lewat
   `SIS_Division_Manage` action UPDATE.
   Sediakan tombol "Salin ke semua hari" per divisi untuk mempercepat pengisian.
2. **Jam Istirahat** — tabel sederhana + modal tambah/edit: nama, hari (dropdown "Semua Hari" +
   Senin–Minggu), jam mulai, jam selesai, urutan. Tombol hapus dengan konfirmasi.

Beri catatan permanen di atas halaman (alert info, bahasa Indonesia): nilai di halaman ini hanya
dipakai sebagai isian awal di Planning Harian PPIC; dashboard selalu memakai angka yang sudah
di-save PPIC untuk tanggal bersangkutan.

## 5. Module

`sql/seed_36_module.sql` (idempotent, pola `seed_*_module.sql` yang sudah ada):
- Code `SETTING_JAM_KERJA`, Name "Jam Kerja & Target", Category `App Setting`,
  SubCategory `Master Data`, Route `work-schedule`, Icon `fe fe-clock`, SortOrder 180.
- Assign ke seluruh user Role = Admin.

## Aturan tetap berlaku

Prefix `SIS_`, pola `@Action` untuk CUD dan SP terpisah untuk read, soft delete +
`deleted_at IS NULL`, `@UserId` dari klaim JWT (bukan body), script SQL idempotent di `sql/`,
`create_tables_tmos_final.sql` ikut diperbarui, UI bahasa Indonesia, kode/API bahasa Inggris.

## Yang TIDAK boleh dilakukan

- Jangan membuat tabel/SP/halaman planning harian — itu Prompt 37.
- Jangan membuat dashboard, token kiosk, atau SP agregasi — itu Prompt 38.
- Jangan menyentuh `article_workflow_logs`, `SIS_WorkflowLog_Manage`, atau `SIS_Bundle_Manage`.
- Jangan mengubah signature SP master yang ada tanpa nilai default pada parameter baru.
- Jangan menjalankan script SQL secara otomatis.

## Urutan deploy

1. `sql/alter_36_dashboard_target.sql`
2. `sql/seed_36_work_schedule_defaults.sql`
3. SP: `sp_WorkScheduleDefault_Manage.sql`, `sp_WorkScheduleDefault_Select.sql`,
   `sp_Division_Manage.sql`, `sp_Division_Select.sql`, `sp_Resource_Manage.sql`,
   `sp_Resource_Select.sql`
4. `sql/seed_36_module.sql`
5. Deploy aplikasi

## Verifikasi

1. `dotnet build TerakarsaApp.slnx -v q` sukses.
2. Buka halaman Divisi → set satu divisi ke mode RESOURCE, satu divisi
   `show_in_dashboard = 0` → simpan → buka ulang, nilai tersimpan.
3. Buka `/work-schedule` → ubah jam Sabtu satu divisi jadi 08:00–15:00 → simpan → reload,
   nilai tetap. Divisi lain tidak berubah.
4. Tambah satu istirahat baru, edit, hapus → daftar konsisten.
5. Jalankan ulang `alter_36` dan `seed_36` → tidak error, tidak menduplikasi baris.
6. Di akhir: daftar file dibuat/diubah + daftar script SQL yang harus dijalankan manual,
   berurutan.

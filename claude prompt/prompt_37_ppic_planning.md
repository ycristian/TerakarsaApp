# Prompt 37 — Planning Harian PPIC: Jadwal, Jumlah Orang, Target

> Bagian 2 dari 3. **Prasyarat: Prompt 36 sudah dijalankan** (kolom `dashboard_mode`,
> `default_target_per_person` di `divisions`, `include_in_dashboard` di `resources`, tabel
> `work_schedule_defaults` dan `work_break_defaults` sudah ada).
> Dashboard TV = Prompt 38, jangan dikerjakan sekarang.

## Konteks

PPIC mengisi rencana kerja harian per divisi: jam masuk, target pulang, jumlah orang yang hadir,
dan target pcs per orang. Satu halaman untuk semua divisi sekaligus, dengan pemilih tanggal —
PPIC bisa mengisi tanggal hari ini maupun tanggal ke depan (planning mingguan).

Aturan pokok:
- Setting default (Prompt 36) hanya **mengisi form**, tidak pernah menjadi data tersimpan.
  PPIC wajib menekan simpan agar tanggal itu dianggap sudah direncanakan.
- Divisi `dashboard_mode = 'DIVISION'` → satu baris angka untuk seluruh divisi.
- Divisi `dashboard_mode = 'RESOURCE'` → angka diisi per resource (line). Tiap line boleh punya
  target/orang yang berbeda; PPIC menaikkan/menurunkan sesuai orderan.
- Jam kerja diisi di level divisi. Bila ada line yang lembur atau masuk lebih siang, PPIC boleh
  menambahkan **override jam per resource** — baris override hanya dibuat bila ada pengecualian.
  Kosong = ikut jam divisi.
- Divisi boleh ditandai **Libur** untuk tanggal itu.
- Divisi yang tidak punya target (mis. Bundling) boleh disimpan dengan target 0 — dashboard akan
  menampilkan hasilnya tanpa bar dan tanpa persentase.

## 1. Skema SQL

Buat `sql/alter_37_daily_plan.sql` (manual, idempotent) + perbarui
`sql/create_tables_tmos_final.sql`.

### `daily_division_plans`

```sql
CREATE TABLE daily_division_plans(
 daily_division_plan_id int primary key identity(1,1),
 plan_date date not null,
 division_id int not null
   constraint FK_ddp_divisions foreign key references divisions(division_id),
 is_holiday bit not null default 0,         -- 1 = divisi libur pada tanggal ini
 start_time time(0) null,                   -- NULL bila libur
 end_time time(0) null,
 headcount int null,                        -- dipakai bila dashboard_mode = DIVISION
 target_per_person int null,                -- dipakai bila dashboard_mode = DIVISION
 remark varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

Filtered unique index `UX_ddp_date_division ON daily_division_plans(plan_date, division_id)
WHERE deleted_at IS NULL`.
Index bantu `IX_ddp_plan_date ON daily_division_plans(plan_date) WHERE deleted_at IS NULL`.

### `daily_resource_plans`

```sql
CREATE TABLE daily_resource_plans(
 daily_resource_plan_id int primary key identity(1,1),
 daily_division_plan_id int not null
   constraint FK_drp_daily_division_plans foreign key references daily_division_plans(daily_division_plan_id),
 resource_id int not null
   constraint FK_drp_resources foreign key references resources(resource_id),
 headcount int not null default 0,
 target_per_person int not null default 0,
 start_time time(0) null,                   -- override; NULL = ikut jam divisi
 end_time time(0) null,                     -- override; NULL = ikut jam divisi
 remark varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

Filtered unique index `UX_drp_plan_resource ON daily_resource_plans(daily_division_plan_id,
resource_id) WHERE deleted_at IS NULL`.

Catatan desain override: `start_time` dan `end_time` diisi berpasangan — bila salah satu terisi,
keduanya wajib terisi (validasi di SP). Ini menutup kasus lembur (jam pulang lebih malam) dan
masuk siang sekaligus tanpa tabel tambahan.

## 2. Stored Procedures

### `sql/sp_DailyPlan_Manage.sql` — `SIS_DailyPlan_Manage`

`@Action`:

**`SAVE`** — simpan rencana satu tanggal untuk SATU divisi beserta seluruh resource-nya.
Parameter: `@PlanDate DATE`, `@DivisionId INT`, `@IsHoliday BIT`, `@StartTime TIME(0)`,
`@EndTime TIME(0)`, `@Headcount INT`, `@TargetPerPerson INT`, `@Remark VARCHAR(500)`,
`@ResourcesJson NVARCHAR(MAX)`, `@UserId INT`.

`@ResourcesJson` = array of
`{ resourceId, headcount, targetPerPerson, startTime, endTime, remark }` (startTime/endTime
boleh null). Diabaikan bila divisi bermode `DIVISION`.

Logika, seluruhnya dalam satu transaksi:
1. Divisi harus hidup. Ambil `dashboard_mode` dari `divisions`.
2. Bila `@IsHoliday = 1` → simpan header dengan jam & angka NULL, dan soft delete seluruh baris
   `daily_resource_plans` milik header itu. Lewati validasi jam/target.
3. Bila tidak libur:
   - `@StartTime` dan `@EndTime` wajib, `@EndTime > @StartTime` →
     RAISERROR `'Jam pulang harus lebih besar dari jam masuk.'`
   - Mode `DIVISION`: `@Headcount` wajib `>= 0`, `@TargetPerPerson` wajib `>= 0`.
   - Mode `RESOURCE`: `@ResourcesJson` wajib berisi minimal satu baris. Tiap `resourceId` harus
     resource hidup milik divisi ini dan `include_in_dashboard = 1` → bila tidak,
     RAISERROR `'Resource bukan milik divisi ini atau tidak ikut dashboard.'`
     Override jam: bila salah satu dari start/end terisi, keduanya wajib dan `end > start` →
     RAISERROR `'Jam override resource tidak lengkap atau tidak valid.'`
4. Upsert header berdasarkan `(plan_date, division_id)` baris hidup: ada → UPDATE
   (`updated_at`/`updated_by`), belum ada → INSERT (`created_at`/`created_by`).
5. Mode `RESOURCE`: upsert detail per `resource_id`; resource yang tidak ada di JSON dan masih
   punya baris hidup → soft delete.
6. Kembalikan `daily_division_plan_id`.

**`DELETE`** (`@PlanDate`, `@DivisionId`, `@UserId`) — soft delete header + seluruh detailnya.
Dipakai bila PPIC ingin mengembalikan divisi ke keadaan "belum direncanakan".

**`COPY_FROM_DATE`** (`@SourceDate`, `@TargetDate`, `@UserId`) — salin seluruh rencana satu
tanggal ke tanggal lain (header + detail) untuk mempercepat planning mingguan. Divisi yang sudah
punya rencana di `@TargetDate` **dilewati**, tidak ditimpa. Kembalikan jumlah divisi tersalin.

### `sql/sp_DailyPlan_Select.sql`

**`SIS_DailyPlan_GetByDate`** (`@PlanDate DATE`) — sumber data form PPIC. Tiga result set:

1. **Divisi** — semua divisi hidup dengan `show_in_dashboard = 1`, urut `dashboard_sort_order`,
   `division_name`. Kolom: `DivisionId`, `DivisionName`, `DashboardMode`,
   `DefaultTargetPerPerson`, `IsSaved` (bit: ada baris hidup di `daily_division_plans`),
   `DailyDivisionPlanId`, `IsHoliday`, `StartTime`, `EndTime`, `Headcount`, `TargetPerPerson`,
   `Remark`, `UpdatedAt`, `SavedByName`.
   **Prefill**: bila belum ada baris tersimpan, `StartTime`/`EndTime`/`IsHoliday` diisi dari
   `work_schedule_defaults` untuk `DATEPART(WEEKDAY)`-nya `@PlanDate` (pakai perhitungan tahan
   `DATEFIRST`, mis. `((DATEPART(WEEKDAY, @PlanDate) + @@DATEFIRST - 2) % 7) + 1` agar 1 = Senin),
   `is_working_day = 0` → `IsHoliday = 1`. `TargetPerPerson` diisi dari
   `divisions.default_target_per_person`. `Headcount` dibiarkan NULL — PPIC wajib mengisi angka
   kehadiran setiap hari, tidak boleh ada default.
   Baris hasil prefill tetap `IsSaved = 0`.

2. **Resource** — untuk divisi bermode `RESOURCE`: seluruh resource hidup + `is_active = 1` +
   `include_in_dashboard = 1` milik divisi tersebut (bukan hanya yang sudah tersimpan), LEFT JOIN
   ke `daily_resource_plans` baris hidup. Kolom: `DivisionId`, `ResourceId`, `ResourceName`,
   `Headcount`, `TargetPerPerson`, `StartTime`, `EndTime`, `Remark`, `IsSaved`.
   Prefill `TargetPerPerson` dari `divisions.default_target_per_person` bila belum tersimpan;
   `Headcount` NULL; jam override NULL.
   **Penting**: LEFT JOIN dan filter `deleted_at IS NULL` untuk `daily_resource_plans` diletakkan
   di klausa `ON`, bukan `WHERE`, supaya resource tanpa rencana tetap muncul.

3. **Istirahat** — `work_break_defaults` hidup yang berlaku pada hari itu
   (`day_of_week IS NULL OR day_of_week = <hari>`), urut `sort_order`, `start_time`.
   Dipakai untuk menampilkan total jam efektif di UI.

**`SIS_DailyPlan_ListDates`** (`@FromDate`, `@ToDate`) — ringkasan status per tanggal untuk
navigasi: `PlanDate`, `TotalDivision`, `SavedDivision`, `HolidayDivision`. Dipakai menandai
tanggal yang sudah/belum lengkap di pemilih tanggal.

## 3. API

`DailyPlanController` (JWT, `[RequireModule("PPIC_PLANNING")]`):
- `GET api/daily-plan?date=yyyy-MM-dd` → tiga result set di atas dalam satu DTO gabungan.
- `PUT api/daily-plan/{divisionId}?date=yyyy-MM-dd` → action `SAVE`.
- `DELETE api/daily-plan/{divisionId}?date=yyyy-MM-dd` → action `DELETE`.
- `POST api/daily-plan/copy` body `{ sourceDate, targetDate }` → action `COPY_FROM_DATE`.
- `GET api/daily-plan/dates?from=&to=` → `SIS_DailyPlan_ListDates`.

`@UserId` selalu dari klaim JWT. DTO di file baru
`TerakarsaApp.Shared/DailyPlans/DailyPlanModels.cs`.

## 4. Blazor Client — halaman `/ppic-planning`

Judul "Planning Harian". Satu halaman untuk semua divisi.

**Header halaman**
- Pemilih tanggal (default hari ini) + tombol panah hari sebelumnya/berikutnya.
- Ringkasan status: "X dari Y divisi sudah disimpan".
- Tombol "Salin dari tanggal lain…" → modal pilih tanggal sumber → panggil endpoint copy →
  reload. Beri keterangan di modal bahwa divisi yang sudah punya rencana tidak akan ditimpa.
- Peringatan bila tanggal yang dibuka tanggal lampau (informasi saja, tetap boleh disimpan).

**Kartu per divisi** (urut `dashboard_sort_order`), tiap kartu berdiri sendiri dengan tombol
simpannya sendiri:
- Judul: nama divisi + badge mode (Per Divisi / Per Line) + badge status
  **"Belum disimpan"** (abu) atau **"Tersimpan HH:mm"** (hijau).
- Toggle **Libur**. Aktif → seluruh input jam & angka di kartu itu disembunyikan/nonaktif.
- Input jam masuk & target pulang.
- Tampilkan **jam efektif hasil hitung** di kartu (mis. "10 jam efektif — istirahat 12:00–13:00,
  17:00–18:00"), dihitung di client dari jam kerja dikurangi rentang istirahat yang beririsan.
- Mode `DIVISION`: dua input — Jumlah Orang, Target/Orang. Tampilkan **Total Target** hasil
  perkalian secara live (read-only).
- Mode `RESOURCE`: tabel per line — Nama Line, Jumlah Orang, Target/Orang, Total (live),
  dan kolom "Override Jam" (default kosong, tombol kecil "atur" membuka dua input jam;
  bila terisi ditampilkan sebagai teks "09:00–22:00" + tombol hapus override).
  Baris total di kaki tabel: jumlah orang total dan total target divisi.
  Sediakan input massal di atas tabel: "Isi semua target/orang" dan "Isi semua jumlah orang"
  untuk mempercepat.
- Tombol **Simpan** per kartu. Setelah sukses, badge berubah jadi Tersimpan tanpa reload halaman.
- Tombol **Hapus Rencana** (hanya tampil bila sudah tersimpan) dengan konfirmasi.

**Validasi di client** (selain validasi SP): jam pulang > jam masuk; jumlah orang wajib diisi
(tidak boleh dibiarkan kosong) bila tidak libur; angka tidak boleh negatif.

Beri alert info permanen: nilai yang terisi otomatis berasal dari setting default dan **belum
tersimpan** sampai tombol Simpan ditekan.

## 5. Module

`sql/seed_37_module.sql` (idempotent):
- Code `PPIC_PLANNING`, Name "Planning Harian", Category `Production`, Route `ppic-planning`,
  Icon `fe fe-calendar`, SortOrder 60.
- Assign ke seluruh user Role = Admin.

## Aturan tetap berlaku

Prefix `SIS_`, `@Action` untuk CUD + SP read terpisah, soft delete, `deleted_at IS NULL`,
filter deleted di klausa `ON` untuk LEFT JOIN, `@UserId` dari JWT, JSON/OPENJSON untuk
master-detail, script SQL idempotent dan dijalankan manual,
`create_tables_tmos_final.sql` diperbarui, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan membuat dashboard, halaman TV, token kiosk, atau SP agregasi — itu Prompt 38.
- Jangan menyentuh `article_workflow_logs` atau SP workflow/bundle mana pun.
- Jangan memakai setting default sebagai data tersimpan — default hanya untuk prefill form.
- Jangan mengisi `Headcount` secara otomatis dari nilai apa pun.
- Jangan menjalankan script SQL secara otomatis.

## Urutan deploy

1. `sql/alter_37_daily_plan.sql`
2. `sql/sp_DailyPlan_Manage.sql`, `sql/sp_DailyPlan_Select.sql`
3. `sql/seed_37_module.sql`
4. Deploy aplikasi

## Verifikasi

1. `dotnet build TerakarsaApp.slnx -v q` sukses.
2. Buka `/ppic-planning` tanggal hari ini → semua divisi `show_in_dashboard = 1` muncul, jam
   terisi otomatis dari default, badge semuanya "Belum disimpan", jumlah orang kosong.
3. Simpan satu divisi mode DIVISION → badge berubah Tersimpan; reload halaman, nilai tetap.
4. Simpan satu divisi mode RESOURCE dengan target berbeda antar line + satu line diberi override
   jam sampai 22:00 → reload, override tetap tampil hanya di line itu.
5. Tandai satu divisi Libur → simpan → reload, toggle libur tetap aktif dan detail resource-nya
   hilang.
6. Buka tanggal 3 hari ke depan → form kosong dengan prefill default; simpan → tanggal hari ini
   tidak ikut berubah.
7. "Salin dari tanggal lain" dari tanggal yang sudah terisi → divisi yang sudah punya rencana di
   tanggal tujuan tidak berubah, sisanya tersalin.
8. Hapus rencana satu divisi → kembali ke status "Belum disimpan".
9. Jalankan ulang `alter_37` → tidak error.
10. Di akhir: daftar file dibuat/diubah + script SQL manual berurutan.

# Prompt 38 — Dashboard Target Harian: Agregasi, Token Kiosk, Layar TV

> Bagian 3 dari 3. **Prasyarat: Prompt 36 dan 37 sudah dijalankan.**

## Konteks

Layar TV di lantai produksi menampilkan progres seluruh divisi terhadap target harian dalam
**satu layar tanpa scroll**. Perangkat TV mengaksesnya lewat browser tanpa login, memakai token
kiosk khusus. Boleh ada lebih dari satu TV — tiap TV punya token sendiri sehingga bisa dicabut
satu per satu.

### Definisi perhitungan (WAJIB diikuti persis)

Untuk tanggal `@PlanDate` dan waktu evaluasi `@Now`:

- **Qty Ok** = `SUM(qty_ok)` dari `article_workflow_logs` hidup dengan
  `CAST(created_at AS date) = @PlanDate`, dikelompokkan per `division_id` (mode DIVISION) atau
  per `resource_id` (mode RESOURCE). **Basis `created_at`, bukan `received_at`** — angka tidak
  boleh menunggu divisi berikutnya menerima. Tidak ada pengelompokan per step: seluruh log divisi
  itu dijumlahkan apa adanya.
- **Qty Reject** = `SUM(qty_reject_print + qty_reject_fabric + qty_reject_sewing)`, sumber dan
  pengelompokan sama.
- **WIP** = pekerjaan yang sudah diterima divisi/resource ini tetapi belum diselesaikan.
  **Gunakan ulang logika yang sudah ada di `SIS_Report_DivisionWip` (Prompt 22)** — jangan
  membuat definisi WIP baru. Bila perlu, tambahkan parameter/varian ke SP itu; jangan menyalin
  logikanya mentah-mentah ke SP baru.
- **Target Total** = `target_per_person × headcount` dari `daily_division_plans` (mode DIVISION)
  atau `daily_resource_plans` (mode RESOURCE).
- **Jam efektif total** = menit antara `start_time` dan `end_time` dikurangi total irisan dengan
  seluruh rentang `work_break_defaults` yang berlaku pada hari itu.
  Mode RESOURCE: bila baris resource punya override jam, pakai override; bila NULL, pakai jam
  divisi.
- **Jam efektif berjalan** = menit efektif antara `start_time` dan `MIN(@Now, end_time)`.
  Bila `@Now < start_time` → 0. Bila `@PlanDate` bukan hari ini → jam berjalan = jam efektif
  total (hari sudah lewat).
- **Persen seharusnya** = jam efektif berjalan ÷ jam efektif total.
- **Persen aktual** = Qty Ok ÷ Target Total.
- **Selisih pcs** = Qty Ok − (Target Total × persen seharusnya). Positif = surplus,
  negatif = defisit.
- **Selisih persen** = persen aktual − persen seharusnya (dalam poin persen).
- **Sisa** = Target Total − Qty Ok, minimum 0.
- **Rata-rata per orang per jam** = Qty Ok ÷ headcount ÷ jam efektif berjalan (dalam jam,
  desimal). Bila headcount atau jam berjalan 0 → NULL.

**Pembagian nol**: setiap pembagian harus dijaga (`NULLIF`). Target 0 atau belum direncanakan →
seluruh field turunan (persen, selisih, sisa) dikembalikan NULL, dan `HasTarget = 0`.

### Status tampilan per divisi/resource

- `HasPlan = 0` (PPIC belum simpan untuk tanggal itu) → tampilkan Qty Ok, Reject, WIP saja.
  Jam kerja diambil dari `work_schedule_defaults` sebagai fallback tampilan, tetapi target NULL
  dan diberi badge "Belum di-set".
- `IsHoliday = 1` → badge "Libur", tanpa bar dan tanpa persen.
- `HasTarget = 0` (target 0, mis. divisi Bundling) → tampilkan angka hasil tanpa bar/persen.

## 1. Skema SQL

`sql/alter_38_dashboard_token.sql` (idempotent) + perbarui `create_tables_tmos_final.sql`.

```sql
CREATE TABLE dashboard_tokens(
 dashboard_token_id int primary key identity(1,1),
 token_name varchar(150) not null,          -- mis. 'TV Line Jahit 1'
 dashboard_token varchar(64) not null,      -- GUID tanpa strip, digenerate server
 is_active bit not null default 1,
 refresh_interval_minutes int not null default 30,  -- harus habis membagi 60

 last_seen_at datetime2 null,               -- diperbarui saat token dipakai
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

Filtered unique index pada `dashboard_token` dan pada `token_name`, keduanya
`WHERE deleted_at IS NULL`.

Berbeda dari `stations`, tabel ini **tidak terikat divisi** — dashboard menampilkan seluruh
divisi, dan boleh ada banyak token aktif bersamaan.

### Aturan interval refresh (WAJIB)

- Nilai yang diizinkan hanya yang **habis membagi 60**: `5, 10, 15, 20, 30, 60`. Tegakkan lewat
  CHECK constraint dan validasi di SP (RAISERROR `'Interval refresh harus salah satu dari 5, 10,
  15, 20, 30, atau 60 menit.'`). Di UI berupa dropdown, bukan input bebas.
- Refresh **selaras jam dinding (wall-clock aligned)**, bukan hitung mundur dari saat halaman
  dibuka. Refresh terjadi tepat pada menit kelipatan interval dalam satu jam, selalu termasuk
  menit `:00`.
  Contoh interval 15 → `:00, :15, :30, :45`. Interval 30 → `:00, :30`. Interval 60 → `:00`.
- Konsekuensinya: seluruh TV dengan interval sama akan menampilkan angka yang sama pada waktu
  yang sama, tidak peduli kapan masing-masing dinyalakan.

## 2. Stored Procedures

### `sql/sp_DashboardToken_Manage.sql` — `SIS_DashboardToken_Manage`
`@Action`: `CREATE` (generate token baru, kembalikan penuh), `UPDATE` (nama, is_active, dan
`refresh_interval_minutes` — tidak menyentuh token), `REGENERATE` (token baru, token lama
langsung mati), `DELETE` (soft delete), `TOUCH` (`@Token`, set `last_seen_at = SYSDATETIME()`).

`CREATE` dan `UPDATE` menerima `@RefreshIntervalMinutes INT = 30` dan memvalidasi nilainya
sesuai daftar yang diizinkan.

### `sql/sp_DashboardToken_Select.sql`
- `SIS_DashboardToken_List` — paged + search nama. **Jangan kembalikan token penuh** — cukup
  8 karakter awal + `…`, plus `last_seen_at`, status aktif, dan `refresh_interval_minutes`.
- `SIS_DashboardToken_GetByToken` (`@Token`) — untuk autentikasi: baris hidup + `is_active = 1`.
  Kembalikan `DashboardTokenId`, `TokenName`, `RefreshIntervalMinutes`.

### `sql/sp_Dashboard_TargetHarian.sql` — `SIS_Dashboard_TargetHarian`

Parameter: `@PlanDate DATE`. Waktu evaluasi = `SYSDATETIME()` di dalam SP (jangan diterima dari
client).

**Result set 1 — Header**: `PlanDate`, `ServerTime`, `TotalDivision`, `PlannedDivision`.

**Result set 2 — Divisi**: seluruh divisi hidup `show_in_dashboard = 1`, urut
`dashboard_sort_order`, `division_name`. Kolom:
`DivisionId`, `DivisionName`, `DashboardMode`, `HasPlan`, `IsHoliday`, `HasTarget`,
`StartTime`, `EndTime`, `Headcount`, `TargetPerPerson`, `TargetTotal`,
`QtyOk`, `QtyReject`, `Wip`,
`EffectiveMinutesTotal`, `EffectiveMinutesElapsed`, `ExpectedPercent`, `ActualPercent`,
`DiffQty`, `DiffPercent`, `RemainingQty`, `OutputPerPersonPerHour`.
Untuk divisi mode RESOURCE, nilai-nilai ini adalah **agregat seluruh line**-nya.

**Result set 3 — Resource**: hanya untuk divisi mode RESOURCE. Kolom sama dengan result set 2
ditambah `ResourceId`, `ResourceName`, dan `HasTimeOverride` (bit). Hanya resource hidup,
`is_active = 1`, `include_in_dashboard = 1`.

Catatan implementasi:
- Hitung menit istirahat lewat CTE irisan rentang:
  `SUM(DATEDIFF(MINUTE, <max mulai>, <min selesai>))` untuk baris `work_break_defaults` yang
  beririsan dengan rentang kerja; irisan negatif dijadikan 0.
- Agregat Qty Ok/Reject dari `article_workflow_logs` dihitung sekali ke tabel temp/CTE lalu
  di-LEFT JOIN, bukan sub-query berulang per baris.
- Semua LEFT JOIN ke `daily_division_plans` / `daily_resource_plans` menaruh
  `deleted_at IS NULL` di klausa `ON`.
- SP ini **read-only**: tidak boleh ada INSERT/UPDATE/DELETE ke tabel mana pun.

## 3. API

### Admin — `DashboardTokenController` (JWT, `[RequireModule("DASHBOARD_TARGET")]`)
- `GET api/dashboard-tokens` (paged), `POST`, `PUT {id}`, `DELETE {id}`,
  `POST {id}/regenerate`.
- Response CREATE dan REGENERATE mengembalikan token penuh **sekali saja** beserta
  `link` siap salin, dirakit dari `PublicBaseUrl` yang sudah ada di konfigurasi:
  `{PublicBaseUrl}/tv-dashboard/{token}`.
- `GET api/dashboard-tokens/{id}/link` → mengembalikan link lengkap untuk token yang sudah ada
  (dipakai tombol Salin Link di list, supaya admin tidak perlu regenerate hanya untuk menyalin).

### Kiosk — tanpa JWT
- Buat `RequireDashboardTokenAttribute`, pola sama dengan `RequireStationTokenAttribute`: baca
  header `X-Dashboard-Token`, validasi lewat `SIS_DashboardToken_GetByToken`, simpan info di
  `HttpContext.Items`, 401 bila tidak valid/nonaktif. Panggil action `TOUCH` untuk memperbarui
  `last_seen_at` (cukup sekali per beberapa menit — beri throttle sederhana di memori supaya
  tidak menulis tiap request).
- `GET api/dashboard/target-harian?date=yyyy-MM-dd` `[RequireDashboardToken]` → hasil
  `SIS_Dashboard_TargetHarian`. Tanpa parameter tanggal → hari ini.
- `GET api/dashboard/me` `[RequireDashboardToken]` → `{ tokenName, refreshIntervalMinutes }`,
  untuk validasi saat aktivasi perangkat dan menentukan irama refresh.

Endpoint kiosk **tidak** memakai `[Authorize]` — pastikan tidak bentrok dengan konfigurasi auth
global (ikuti persis cara endpoint station dikecualikan).

DTO di `TerakarsaApp.Shared/Dashboards/DashboardModels.cs`.

## 4. Blazor Client

### Halaman admin `/dashboard-tokens` — "Dashboard TV"
Halaman tersendiri (bukan bagian dari Kelola Stasiun). List: nama, token terpotong, badge Aktif,
kolom **Interval Refresh** (mis. "30 menit"), "Terakhir aktif: …". Aksi per baris: **Salin Link**,
Edit, Aktif/Nonaktif, **Generate Ulang Token** (konfirmasi + peringatan TV yang memakai token lama
akan berhenti), Hapus.

Modal tambah/edit berisi: nama TV, dropdown **Interval Refresh** (5 / 10 / 15 / 20 / 30 / 60
menit, default 30), checkbox Aktif. Di bawah dropdown tampilkan keterangan dinamis berisi jadwal
refresh yang dihasilkan, mis. interval 15 → "Refresh tiap menit :00, :15, :30, :45".
Setelah simpan token baru, tampilkan link penuh + tombol salin.

### Halaman kiosk `/tv-dashboard` (+ rute `/tv-dashboard/{Token}`)
`@layout BlankLayout`, tanpa `AuthorizeView`, **tidak muncul di sidebar**.

- Rute dengan `{Token}` → simpan token ke localStorage lewat JS Interop (pola `TokenKey` yang
  sudah ada, kunci terpisah dari station), lalu bersihkan URL ke `/tv-dashboard` tanpa reload.
- Tanpa token tersimpan → layar aktivasi sederhana: input tempel token + tombol Aktifkan.
- Token ditolak server (401) → hapus localStorage, kembali ke layar aktivasi dengan pesan
  "Token dashboard tidak berlaku. Minta link baru ke admin."
- HttpClient terpisah yang menyertakan header `X-Dashboard-Token` — jangan pakai handler JWT.
- **Auto refresh selaras jam dinding**, interval diambil dari `api/dashboard/me`. Jangan memakai
  `Timer` berulang dengan periode tetap sejak halaman dibuka — itu akan menggeser jadwal.
  Pola yang dipakai: setelah tiap refresh, hitung waktu menuju kelipatan interval berikutnya
  dalam jam berjalan, lalu pasang timer sekali-jalan sepanjang jeda itu; ulangi.
  ```
  menitBerikut = ((menitSekarang / interval) + 1) * interval   // pembagian bulat
  jeda = waktu menuju menitBerikut, detik & milidetik dinolkan
  ```
  `menitBerikut = 60` berarti menit `:00` jam berikutnya. Tambahkan jitter kecil (0–3 detik)
  sebelum memanggil API agar banyak TV tidak menembak server pada milidetik yang sama.
- Tombol refresh manual kecil di pojok — tidak menggeser jadwal refresh otomatis berikutnya.
- Tampilkan "Update terakhir HH:mm" dan "Berikutnya HH:mm" di header. Timer di-dispose dengan
  benar (`IDisposable`).

### Tata letak layar TV (wajib muat satu layar, tanpa scroll)

Ukuran acuan 1920×1080, semua konten dalam satu viewport (`height: 100vh`, tanpa scrollbar).

**Header** — satu baris: judul + tanggal, pemilih tanggal (kecil, untuk review dari PC; di TV
biarkan hari ini), "Update terakhir HH:mm", dan legenda warna.

**Baris atas** — grid kartu untuk divisi mode `DIVISION`, lebar merata (4 kolom bila 4 divisi).
Isi tiap kartu:
- Nama divisi + jam masuk–pulang di kanan atas
- Qty Ok besar + `/ Target` + jumlah orang
- Bar progres **dua lapis**: lapisan abu = persen seharusnya, lapisan warna = persen aktual
  (ditumpuk di posisi kiri yang sama, bukan bersebelahan)
- Baris: **Selisih** (hijau `+155 (+10%)` / merah `−20 (−1%)`) di kiri, **persen aktual** di kanan
- Baris kecil: `x org/jam`, `sisa N`, `WIP N`, `Rjk N`

**Baris bawah** — satu panel per divisi mode `RESOURCE`, disusun berdampingan. Tiap panel berisi
judul divisi + agregat, lalu tabel line dengan kolom berurutan:
`Line | Org | OK | Progress (bar + % di kanan bar) | Target | org/jam | Sisa | Selisih`
Kaki panel: `WIP total N · Reject N`.

**Warna** (pakai variabel CSS/tema yang sudah ada bila tersedia; jangan hardcode di banyak
tempat — definisikan sekali):
- Abu = posisi seharusnya
- Hijau = selisih ≥ 0 (surplus)
- Kuning = defisit < 10 poin persen
- Merah = defisit ≥ 10 poin persen

**Keterbacaan dari jauh**: ukuran font minimal 14px untuk baris tabel, angka utama kartu ≥ 28px.
Bila jumlah line bertambah sehingga tabel tidak muat, perkecil tinggi baris secara proporsional
(hitung dari jumlah baris) — **jangan** memunculkan scrollbar dan **jangan** memotong data.

**Kondisi khusus**: badge "Belum di-set" (abu) bila `HasPlan = 0`, badge "Libur" bila
`IsHoliday = 1`, kartu tanpa bar/persen bila `HasTarget = 0`. Line dengan `HasTimeOverride = 1`
menampilkan jam override kecil di sebelah nama line.

## 5. Module

`sql/seed_38_module.sql` (idempotent):
- Code `DASHBOARD_TARGET`, Name "Dashboard TV", Category `App Setting`, Route
  `dashboard-tokens`, Icon `fe fe-monitor`, SortOrder 190. Assign ke seluruh user Role = Admin.

Module ini mengatur **halaman admin token**, bukan halaman kiosk — halaman kiosk selalu publik
dan diamankan oleh token.

## Catatan keamanan (tulis sebagai komentar di kode)

Token ada di dalam URL agar bisa disalin sekali ke browser TV. Ini disengaja dan dapat diterima
karena: endpoint kiosk **read-only** (tidak ada aksi mutasi), token tidak memberi akses ke data
selain agregat dashboard, dan token bisa dicabut kapan saja per perangkat. Token disimpan di
localStorage dan URL dibersihkan segera setelah aktivasi supaya tidak tertinggal di riwayat
browser atau tampil di layar.

## Aturan tetap berlaku

Prefix `SIS_`, `@Action` untuk CUD + SP read terpisah, soft delete, `deleted_at IS NULL`,
filter deleted di klausa `ON` untuk LEFT JOIN, script SQL idempotent dijalankan manual,
`create_tables_tmos_final.sql` diperbarui, JS Interop localStorage (bukan Blazored),
UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan memakai `received_at` sebagai basis Qty Ok.
- Jangan membuat definisi WIP baru — pakai ulang `SIS_Report_DivisionWip`.
- Jangan menyentuh `article_workflow_logs`, `SIS_WorkflowLog_Manage`, atau `SIS_Bundle_Manage`.
- Jangan menambahkan mutasi apa pun ke `SIS_Dashboard_TargetHarian` (selain `TOUCH` yang berdiri
  sendiri di SP token).
- Jangan menampilkan token penuh di list admin atau di response GetAll.
- Jangan menaruh pengelolaan token dashboard di halaman Kelola Stasiun.
- Jangan memberi masa berlaku otomatis pada token — pencabutan manual saja.
- Jangan hardcode interval refresh di client, dan jangan memakai timer periodik yang dihitung
  sejak halaman dibuka.
- Jangan mengizinkan nilai interval di luar 5/10/15/20/30/60.
- Jangan membuat halaman kiosk bisa di-scroll.
- Jangan menjalankan script SQL secara otomatis.

## Urutan deploy

1. `sql/alter_38_dashboard_token.sql`
2. `sql/sp_DashboardToken_Manage.sql`, `sql/sp_DashboardToken_Select.sql`,
   `sql/sp_Dashboard_TargetHarian.sql` (+ perubahan pada SP WIP bila ada)
3. `sql/seed_38_module.sql`
4. Deploy aplikasi

## Verifikasi

1. `dotnet build TerakarsaApp.slnx -v q` sukses.
2. Buat 2 token TV → salin link masing-masing → buka di dua tab browser → keduanya jalan
   bersamaan.
3. Nonaktifkan salah satu token → tab itu kembali ke layar aktivasi pada refresh berikutnya,
   tab satunya tetap jalan.
4. Divisi mode DIVISION dan mode RESOURCE tampil di layout yang benar dan muat satu layar pada
   1920×1080 tanpa scrollbar (uji dengan 10 line di dua divisi).
5. Divisi yang PPIC belum simpan → badge "Belum di-set", angka Qty Ok tetap tampil.
6. Divisi ditandai Libur → badge Libur, tanpa bar.
7. Divisi dengan target 0 → angka tampil, tanpa bar dan tanpa persen.
8. Line dengan override jam sampai 22:00 → persen seharusnya-nya lebih rendah dari line lain
   pada jam yang sama, dan jam override tampil di baris itu.
9. Bandingkan Qty Ok satu divisi dengan query manual
   `SUM(qty_ok) WHERE CAST(created_at AS date) = <tgl>` → harus sama persis.
10. Buka dashboard dengan tanggal kemarin → persen seharusnya = 100%, selisih dihitung terhadap
    target penuh.
11. Tunggu/paksa siklus refresh → "Update terakhir" berubah, `last_seen_at` token ikut terbarui.
12. Set satu token ke interval 15 menit → buka pada menit acak (mis. 13:07) → refresh pertama
    terjadi pada 13:15, bukan 13:22. Buka tab kedua pada 13:11 → tab itu juga refresh pada 13:15.
13. Set interval 60 menit → refresh berikutnya jatuh tepat di menit :00 jam berikutnya.
14. Tekan refresh manual di tengah jeda → data terbarui, tetapi jadwal otomatis berikutnya tidak
    bergeser.
15. Di akhir: daftar file dibuat/diubah + script SQL manual berurutan.

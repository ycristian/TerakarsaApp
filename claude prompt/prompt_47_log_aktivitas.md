# Prompt 47 — Modul Log Aktivitas (Riwayat Serah-Terima Mentah)

## Konteks

Supervisor/operator sering bertanya "kemarin saya ngerjain apa saja?". Saat ini tidak ada
satu tempat untuk melihat baris `article_workflow_logs` **apa adanya**: laporan yang ada
(`REPORT_WIP`, `REPORT_PRODUKSI`) semuanya sudah teragregasi.

Modul ini murni **read-only listing**: satu baris tabel = satu baris `article_workflow_logs`
hidup, tanpa grouping, tanpa agregasi, urut waktu. Filter rentang tanggal **beserta jamnya**,
plus filter divisi → resource → employee.

Prompt ini TIDAK mengubah logika bisnis apa pun — tidak ada perubahan pada
`SIS_WorkflowLog_Manage`, alur stasiun, bundle, atau print.

## Keputusan yang sudah dikunci

1. **1 baris per log**, dengan dua kolom waktu terpisah: Waktu Serah (`created_at`) dan
   Waktu Terima (`received_at`). Bukan dua baris event.
2. **Employee diambil dari `bundles.employee_id`** (penjahit yang ditugaskan ke bundle,
   hasil Prompt 32). `article_workflow_logs.employee_id` TIDAK dipakai dan TIDAK diisi —
   jangan ubah SP mutasi untuk mengisinya.
3. **Klik baris** → navigasi ke `/b/{serial}`. Baris non-bundle (`bundle_id IS NULL`,
   mis. Cutting) **tidak bisa diklik** (tanpa cursor pointer, tanpa hover effect).

## 1. Module & SQL seed

`sql/seed_47_report_activity_module.sql` (idempotent, pola seed module yang sudah ada):

- Code `REPORT_ACTIVITY`, Name "Log Aktivitas", Route `activity-log`, icon yang cocok
  (mis. `fe fe-list`), grup/kategori **sama dengan module laporan lain** (ikuti penempatan
  `REPORT_WIP` / `REPORT_PRODUKSI`), SortOrder setelahnya.
- Assign otomatis ke semua user Role = Admin.

## 2. Index penunjang

`sql/alter_47_activity_log_index.sql` (idempotent, `IF NOT EXISTS` pada `sys.indexes`):

```sql
CREATE INDEX IX_awl_created_at ON article_workflow_logs(created_at) WHERE deleted_at IS NULL;
CREATE INDEX IX_awl_received_at ON article_workflow_logs(received_at) WHERE deleted_at IS NULL;
```

Sesuaikan/skip jika index dengan leading column yang sama sudah ada — periksa dulu
`sql/create_tables_tmos_final.sql` dan script alter sebelumnya, jangan bikin duplikat.

## 3. Stored Procedure

Buat `sql/sp_Report_ActivityLog.sql` berisi SATU SP: `SIS_Report_ActivityLog`
(read-only, pola `@Action = 'LIST' | 'COUNT'` seperti SP paged lain).

### Parameter

| Param | Tipe | Ket |
|---|---|---|
| `@Action` | VARCHAR(10) = 'LIST' | LIST atau COUNT |
| `@DateFrom` | DATETIME2 | wajib, inklusif |
| `@DateTo` | DATETIME2 | wajib, inklusif |
| `@TimeBasis` | VARCHAR(10) = 'ANY' | 'ANY' / 'CREATED' / 'RECEIVED' — lihat di bawah |
| `@DivisionId` | INT = NULL | divisi terlibat (asal ATAU tujuan) |
| `@ResourceId` | INT = NULL | resource terlibat (pelaksana ATAU penerima) |
| `@EmployeeId` | INT = NULL | penjahit bundle (`bundles.employee_id`) |
| `@ProjectId` | INT = NULL | opsional |
| `@SearchTerm` | VARCHAR(150) = NULL | serial / nama project / nama artikel / nama step |
| `@PageNumber` | INT = 1 | |
| `@PageSize` | INT = 50 | |

### Aturan filter

- **`@TimeBasis`**:
  - `CREATED` → `created_at BETWEEN @DateFrom AND @DateTo`
  - `RECEIVED` → `received_at BETWEEN @DateFrom AND @DateTo` (baris belum diterima tidak muncul)
  - `ANY` (default) → `created_at` masuk range **ATAU** `received_at` masuk range.
    Ini yang paling menjawab pertanyaan operator, karena dalam sehari dia melakukan dua
    jenis aksi: menerima dan menyerahkan.
- **`@DivisionId`**: cocok bila `awl.division_id = @DivisionId` **ATAU**
  `awl.target_division_id = @DivisionId`. Divisi yang menyerahkan dan yang menerima
  dua-duanya "terlibat" di baris itu.
- **`@ResourceId`**: cocok bila `awl.resource_id = @ResourceId` **ATAU**
  `awl.received_by_resource_id = @ResourceId`.
- **`@EmployeeId`**: `b.employee_id = @EmployeeId` (baris non-bundle otomatis tidak cocok).
- Selalu `awl.deleted_at IS NULL`. Baris terhapus TIDAK ditampilkan.
- Filter NULL = tidak memfilter (semua).

### Result set LIST

Satu baris per `workflow_log_id`, kolom:

- `WorkflowLogId`, `LogType` (bila kolom `log_type` sudah ada — hasil Prompt 28/29)
- `CreatedAt` (Waktu Serah), `ReceivedAt` (Waktu Terima), `UpdatedAt`
- `ProjectId`, `ProjectName`, `ArticleId`, `ArticleName`, `Style`, `Color`
- `StepName`, `SortOrder`
- `BundleId`, `BundleSerial`, `BundleNo`, kode huruf bundle (Prompt 27) — tampilkan
  identitas bundle dengan **konvensi yang sama persis** seperti di WIP Dashboard,
  jangan bikin format baru
- `SizeName` (dari bundle untuk baris ber-bundle; dari `article_size_id` untuk baris non-bundle)
- `DivisionId`, `DivisionName` (asal), `TargetDivisionId`, `TargetDivisionName` (tujuan)
- `ResourceId`, `ResourceName` (pelaksana), `ReceivedByResourceId`, `ReceivedByResourceName`
- `EmployeeId`, `EmployeeName` (dari bundle; "-" bila kosong)
- **Semua kolom qty yang ada di tabel** (`qty_ok`, `qty_reject_print`, `qty_reject_fabric`,
  `qty_reject_sewing`, dan bila sudah ada: `qty_reject_rework`, `qty_lost`) — cek skema
  aktual dulu, jangan asumsi
- `Remark`, `ReceivedRemark`
- `CreatedByName` (pencatat, JOIN users)
- `Status` — turunan: `received_at IS NULL` → 'MENUNGGU', selain itu 'DITERIMA'
- `CanNavigate` bit — `1` bila `bundle_id IS NOT NULL` (client pakai ini untuk klik baris)

Urutan: default waktu terbaru dulu. Kolom urut yang boleh dipilih client: waktu serah,
waktu terima. Tiebreak `workflow_log_id DESC`.

Semua JOIN ke tabel yang boleh kosong pakai LEFT JOIN, dan **filter `deleted_at` letakkan
di klausa `ON`, bukan `WHERE`** (aturan yang sudah berlaku — supaya baris log lama tidak
hilang gara-gara master-nya sudah dihapus).

### Result set COUNT

`TotalCount` saja (filter identik dengan LIST). Boleh sekalian `TotalQtyOk` sebagai info
footer — ini satu-satunya angka agregat yang boleh ada di modul ini.

## 4. API

- Controller baru atau tempel di controller laporan yang sudah ada, `[Authorize]` +
  `RequireModule("REPORT_ACTIVITY")`.
- GET `api/reports/activity-log` — semua filter di atas sebagai query string, kembalikan
  paged result (pola `PagedResult` yang sudah dipakai modul lain).
- **Lookup dropdown**: pakai ulang endpoint yang sudah ada — divisi (list divisi hidup) dan
  resource per divisi (`SIS_Resource_GetActiveByDivision`). Untuk employee per divisi:
  cari dulu apakah sudah ada endpoint/SP lookup employee (Prompt 32 membuat cascading
  line → employee). Kalau sudah ada, **pakai itu**. Kalau belum, tambahkan SP kecil
  `SIS_Employee_GetActiveByDivision` (@DivisionId → Id, EmployeeName) + endpoint-nya.
  Jangan bikin lookup duplikat.

## 5. Blazor Client — halaman `/activity-log`

Judul: "Log Aktivitas". Pola halaman list standar (page-header, breadcrumb, cek module,
`PageSizeSelector`, `SortableHeader`, paging) — ikut konvensi halaman yang sudah ada.

### Panel filter (di atas tabel, dalam satu card)

1. **Dari** dan **Sampai**: input `datetime-local` (tanggal + jam). Default: hari ini
   `00:00` → hari ini `23:59`.
2. Tombol cepat: **Hari Ini**, **Kemarin**, **7 Hari Terakhir** — hanya mengisi ulang
   kedua input di atas.
3. **Basis waktu**: radio/select — "Serah & Terima" (default, `ANY`) / "Waktu Serah" /
   "Waktu Terima".
4. **Divisi** (dropdown, default "Semua Divisi").
5. **Resource** — cascading dari Divisi, disabled sampai divisi dipilih, reset kalau
   divisi berubah.
6. **Employee** — cascading dari Divisi juga (bukan dari Resource), perlakuan sama.
7. **Pencarian**: serial / project / artikel / step.
8. Tombol **Terapkan** dan **Reset**.

Filter dikirim ke server saat Terapkan ditekan (bukan on-change), supaya tidak menembak
API tiap ketikan. Kembali ke halaman 1 setiap kali filter berubah.

### Tabel

Kolom (kiri ke kanan): Waktu Serah · Waktu Terima · Bundle · Project · Artikel · Size ·
Step · Divisi Asal → Divisi Tujuan · Pelaksana · Penerima · Penjahit · Qty OK · Reject/Lost
(gabung jadi satu kolom ringkas, detail di tooltip/kolom terpisah — pilih yang paling
kebaca) · Status (badge Menunggu/Diterima) · Remark · Pencatat.

- Format waktu: `dd/MM/yy HH:mm`. Kolom waktu terima kosong → "-".
- Baris dengan `CanNavigate = 1`: `cursor: pointer`, hover highlight, klik →
  `NavigationManager.NavigateTo($"/b/{serial}")`. Baris lain: tanpa efek apa pun.
- Footer: jumlah baris hasil filter (dan total Qty OK bila dipakai).
- Kosong → "Tidak ada aktivitas pada rentang waktu ini."
- Default page size 50.

## Aturan tetap berlaku

Soft delete + filter `deleted_at IS NULL`, prefix SP `SIS_`, SP read terpisah dari SP
mutasi, UI bahasa Indonesia, kode/API bahasa Inggris, script SQL dijalankan manual.

## Yang TIDAK boleh dilakukan

- Jangan ubah `SIS_WorkflowLog_Manage`, SP stasiun, SP bundle, atau SP laporan lain.
- Jangan mengisi/memakai `article_workflow_logs.employee_id` — employee datang dari bundle.
- Jangan menambahkan grouping, subtotal per divisi/operator, atau chart apa pun. Modul ini
  sengaja data mentah; agregasi sudah ada di `REPORT_PRODUKSI`.
- Jangan tampilkan baris yang sudah di-soft-delete.
- Jangan bikin komponen dropdown/lookup baru kalau yang setara sudah ada.
- Jangan tambah kolom baru di tabel mana pun — prompt ini hanya SP read, API, dan UI.

## Verifikasi

1. Jalankan `sql/alter_47_activity_log_index.sql`, `sql/sp_Report_ActivityLog.sql`,
   `sql/seed_47_report_activity_module.sql` (urutan ini).
2. `dotnet build` sukses.
3. Uji: rentang 1 hari penuh → baris muncul; filter divisi Sewing → baris yang diserahkan
   Sewing dan yang diterima Sewing dua-duanya muncul; filter employee → hanya baris
   ber-bundle milik penjahit itu; klik baris ber-bundle → `/b/{serial}` terbuka; baris
   Cutting tidak bereaksi saat diklik.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

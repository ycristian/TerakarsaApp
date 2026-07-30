# Prompt 32 — Penjahit Bundle: Teks Bebas → Master Employee

## Konteks

Kolom `bundles.resource_person_name` (teks bebas) menyebabkan data penjahit tidak
konsisten. Penjahit kini diambil dari master `employees` (sudah ada CRUD-nya,
Prompt 04) yang tertaut ke line lewat `employees.resource_id`. Struktur relasi:

```
resources (line)  ←  employees.resource_id  ←  bundles.employee_id (BARU)
```

**Transisi**: kolom `resource_person_name` TIDAK dihapus dulu — data lama tetap
tampil sebagai fallback sampai mapping manual ke employee selesai. Drop kolom
akan jadi prompt terpisah nanti.

## 1. Skema SQL

Perbarui `sql/create_tables_tmos_final.sql` (tabel bundles) dan buat
`sql/alter_32_bundle_employee.sql` (idempotent):

- ADD `employee_id int null`
  + `FK_bundles_employees` → employees(employee_id)
- Komentar di kolom `resource_person_name`: "DEPRECATED — hanya data lama,
  form tidak lagi mengisi; akan di-drop setelah mapping ke employee_id selesai."

## 2. Stored Procedures

### SIS_Employee_GetActiveByResource (baru, Read)

@ResourceId → employee hidup dengan `resource_id = @ResourceId`, kolom:
employee_id AS Id, employee_name AS EmployeeName. Urut employee_name ASC.
Pola meniru `SIS_Resource_GetActiveByDivision`.

### SIS_Bundle_Manage (ubah)

- Parameter baru: `@EmployeeId INT = NULL`.
- Parameter `@ResourcePersonName` TETAP ADA di signature (default NULL) tapi
  DIABAIKAN — tidak dipakai di INSERT/UPDATE mana pun. Ini menjaga SP tetap
  kompatibel bila dipanggil API versi lama selama jendela deploy; penghapusan
  parameter dilakukan di prompt drop kolom nanti.
- Validasi (CREATE dan UPDATE), hanya bila @EmployeeId diisi:
  - @ResourceId wajib ikut diisi ('Pilih line terlebih dahulu.').
  - Employee harus hidup dan `resource_id = @ResourceId`
    ('Penjahit bukan anggota line ini.').
  - Khusus UPDATE: validasi kecocokan line HANYA bila @EmployeeId berbeda dari
    `employee_id` tersimpan. Jadi bundle lama yang employee-nya sudah pindah
    line tetap bisa disimpan selama penjahitnya tidak diganti.
- **CREATE**: insert `employee_id`; `resource_person_name` selalu NULL untuk
  bundle baru.
- **UPDATE**: set `employee_id = @EmployeeId`; kolom `resource_person_name`
  TIDAK disentuh (nilai lama dibiarkan apa adanya).

### SIS_Bundle_ListByArticle (ubah)

LEFT JOIN employees → tambah kolom EmployeeId, EmployeeName.
ResourcePersonName tetap dikembalikan (fallback tampilan).

### SP tampilan lain yang menampilkan penjahit bundle

Cari semua SP yang membaca `bundles.resource_person_name` (minimal:
`SIS_Report_BundleWip` / SP di sp_Report_Bundle.sql, SP station in-progress
di prompt 12e, `SIS_Bundle_ScanInfo`). Di masing-masing: LEFT JOIN employees,
tambah EmployeeName; ResourcePersonName tetap ada. JANGAN mengubah logika lain
SP tersebut.

**Aturan JOIN wajib** (agar tidak ada baris hilang selama transisi):
- Selalu **LEFT JOIN** — `employee_id` NULL di semua bundle lama.
- Filter soft delete employee ditaruh di klausa **ON**, bukan WHERE
  (`LEFT JOIN employees e ON e.employee_id = b.employee_id AND e.deleted_at IS NULL`).
  Kalau di WHERE, bundle tanpa employee ikut terfilter hilang.
- Jangan menambah/menghapus kolom lain dan jangan mengubah urutan kolom hasil
  yang sudah ada — hanya MENAMBAH kolom EmployeeId/EmployeeName di akhir SELECT.

## 3. API

- Endpoint baru GET `api/employees/lookup?resourceId={id}` →
  SIS_Employee_GetActiveByResource. [Authorize], module sama dengan endpoint
  lookup resource yang sudah dipakai BundleManager.
- `BundleCreateRequest` / `BundleUpdateRequest`: hapus `ResourcePersonName`,
  tambah `EmployeeId (int?)`.
- `BundleDto` (dan DTO tampilan lain yang tersentuh): tambah `EmployeeId`,
  `EmployeeName`; `ResourcePersonName` dipertahankan.

## 4. Blazor Client

### BundleManager.razor (form tambah + form edit)

- Input teks bebas "Nama Penjahit (bebas)" DIHILANGKAN dari kedua form.
- Dropdown baru "Penjahit" (SearchableSelect, AllowNone "- Tidak ada -")
  **cascading ketat** di bawah dropdown line:
  - Disabled/kosong selama line belum dipilih.
  - Pilih line → load opsi dari `api/employees/lookup?resourceId=`.
  - Ganti line → pilihan penjahit di-reset.
- Form edit: prefill EmployeeId; bila bundle lama hanya punya
  ResourcePersonName, tampilkan teks kecil info di bawah dropdown:
  "Data lama: {ResourcePersonName}".

### Tampilan penjahit (FormatPenjahit dan sejenisnya)

Prioritas tampilan di semua tempat (list bundle, report, station, scan):
1. EmployeeName terisi → `{ResourceName} - {EmployeeName}`
2. Hanya ResourcePersonName (data lama) → `{ResourceName} - {ResourcePersonName}`
3. Hanya ResourceName → `{ResourceName}`
4. Kosong semua → "-"

## 5. Keamanan Transisi & Urutan Deploy

Setiap langkah di bawah TIDAK boleh merusak aplikasi yang sedang berjalan:

1. **Jalankan `alter_32_bundle_employee.sql`** — hanya ADD kolom nullable + FK.
   Aplikasi lama tetap jalan normal (kolom baru diabaikan).
2. **Jalankan script SP** — SP baru tetap menerima `@ResourcePersonName`
   (diabaikan), jadi API lama yang masih mengirim parameter itu tidak error.
   SELECT hanya menambah kolom di akhir, Dapper API lama tidak terganggu.
3. **Deploy API + Client** versi baru.

Checklist yang harus dipastikan Claude Code sebelum selesai:
- Tidak ada SP yang kehilangan parameter yang masih dikirim kode lama.
- Semua SELECT bundle tetap mengembalikan kolom `ResourcePersonName`.
- Bundle lama (`employee_id` NULL, `resource_person_name` terisi) tetap tampil
  benar di: list bundle, edit form, report WIP, station, scan info.
- Edit bundle lama lalu simpan TANPA memilih penjahit → tidak error, dan
  `resource_person_name` lama tidak terhapus.
- Build solution sukses.

## Aturan tetap berlaku

Soft delete, filter deleted_at IS NULL, UserId dari JWT, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- JANGAN drop / rename kolom `resource_person_name` — prompt terpisah nanti.
- Jangan ubah CRUD master employees / resources.
- Jangan ubah payload label, TSPL, atau print service — nama penjahit tidak
  ada di label.
- Jangan tambah kolom employee di article_workflow_logs (aturan 12d tetap).
- Jangan buat migrasi/backfill data resource_person_name → employees.

Setelah selesai: daftar file dibuat/diubah + script SQL yang harus dijalankan
manual (alter_32_bundle_employee.sql, SP yang berubah).

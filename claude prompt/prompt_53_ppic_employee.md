# Prompt 53 — Module PPIC Karyawan + Status Aktif/Nonaktif + Kode Karyawan Otomatis

## Konteks

PPIC perlu bisa menambah/mengubah penjahit sendiri tanpa diberi akses penuh ke Master Karyawan. Karena guard di aplikasi ini adalah **module-level** (`[RequireModule]` di controller, tidak ada permission per-action), memberi `MASTER_EMPLOYEE` ke PPIC otomatis memberi akses ke seluruh divisi + hak hapus. Solusinya: **module, controller, dan SP terpisah** — pola yang sama seperti `WorkflowInputController` dan `SIS_SuperAdmin_Manage`, yaitu pintu masuk mandiri tanpa mengubah guard yang lama.

Prompt ini punya tiga bagian:
- **A.** Perubahan skema (2 kolom baru)
- **B.** Module PPIC baru (`PPIC_EMPLOYEE`)
- **C.** Dampak ke module yang sudah ada (Master Divisi, Master Karyawan, seluruh dropdown employee)

---

## A. Skema

### `sql/alter_53_ppic_employee.sql` (dijalankan manual)

```sql
-- Prompt 53: divisi yang boleh dikelola PPIC
ALTER TABLE divisions
  ADD ppic_managed bit NOT NULL CONSTRAINT DF_divisions_ppic_managed DEFAULT 0;
GO

-- Prompt 53: status aktif karyawan (nonaktif = tidak muncul di dropdown, data lama tetap utuh)
ALTER TABLE employees
  ADD is_active bit NOT NULL CONSTRAINT DF_employees_is_active DEFAULT 1;
GO
```

Sinkronkan juga definisi kedua tabel di `sql/create_tables_tmos_final.sql` berikut komentar singkat arti kolomnya.

**Tidak ada backfill kode karyawan.** Kode lama berformat `EM0001` (tanpa strip) dibiarkan apa adanya — format baru hanya berlaku untuk kode yang di-generate setelah ini.

---

## B. Kode karyawan otomatis

### Format

`{division_code}-{4 digit}` — contoh `EM-0001`, `TR-0001`. Nomor urut **berjalan per divisi**, bukan global.

### SP baru: `SIS_Employee_NextCode`

```
@DivisionId INT
```

- Ambil `division_code` divisi tsb (kalau divisi tidak ada / sudah dihapus → kembalikan NULL, bukan error)
- Cari nomor tertinggi dari `employees` yang `employee_code LIKE division_code + '-[0-9][0-9][0-9][0-9]'`
  — **termasuk baris yang nonaktif dan yang sudah soft-delete**, supaya nomor tidak pernah dipakai ulang
- Kembalikan `division_code + '-' + RIGHT('0000' + CAST(max+1 AS varchar), 4)`. Kalau sudah lewat 9999, jangan dipotong — biarkan jadi 5 digit
- Kembalikan satu kolom `SuggestedCode`

SP ini **hanya memberi saran**. Keunikan tetap divalidasi di SP CREATE/UPDATE seperti sekarang (`RAISERROR` dengan pesan yang sudah ada).

### Perilaku di form

- Field Kode terisi otomatis saat divisi dipilih, **tapi tetap bisa diedit** (override)
- Saat divisi diganti di form edit, kode di-regenerate mengikuti prefix divisi baru — kalau field kode sudah pernah diketik manual oleh user, **minta konfirmasi dulu** sebelum menimpa
- Kalau simpan gagal karena kode bentrok (dua orang menyimpan bersamaan), tampilkan pesan errornya + tombol **"Ambil kode berikutnya"** yang memanggil ulang `SIS_Employee_NextCode`

---

## C. Module PPIC (`PPIC_EMPLOYEE`)

### Registrasi module — `sql/seed_53_ppic_employee_module.sql` (idempotent)

| Field | Nilai |
|---|---|
| Code | `PPIC_EMPLOYEE` |
| Name | `Karyawan (PPIC)` |
| Category | `Production` |
| Route | `ppic/karyawan` |
| Icon | `fe fe-user-plus` |
| SortOrder | 200 |

Assign ke user Role = Admin (untuk pengujian). User PPIC-nya di-assign manual lewat halaman Module Access.

### Controller

`PpicEmployeeController`, route `api/ppic-employee`, `[Authorize]` + `[RequireModule("PPIC_EMPLOYEE")]`. `@UserId` dari claim JWT.

### SP baru

| SP | Isi |
|---|---|
| `SIS_PpicEmployee_Manage` | `@Action` = CREATE / UPDATE / DELETE / SETACTIVE |
| `SIS_PpicEmployee_List` | paged + search + sort, hanya divisi `ppic_managed = 1` |
| `SIS_PpicEmployee_GetById` | hanya kalau divisinya `ppic_managed = 1` |
| `SIS_Division_GetPpicManaged` | lookup dropdown divisi: `ppic_managed = 1 AND deleted_at IS NULL` |

**Guard ada di SP, bukan hanya di controller** — supaya `division_id` dari client tidak bisa dipakai menembus batasan:

- **CREATE / UPDATE**: `@DivisionId` yang dikirim wajib `ppic_managed = 1`, kalau tidak → `RAISERROR('Divisi ini tidak dikelola PPIC.', 16, 1)`
- **UPDATE / DELETE / SETACTIVE**: divisi karyawan **yang tersimpan sekarang** juga wajib `ppic_managed = 1`, kalau tidak → `RAISERROR('Karyawan ini di luar wewenang PPIC.', 16, 1)`
- `SIS_PpicEmployee_List` dan `GetById` ikut aturan yang sama

### Aturan DELETE

Soft delete hanya boleh kalau karyawan **belum pernah dipakai di transaksi apa pun**.

Jangan hardcode daftar tabelnya. Telusuri dulu seluruh FK yang menunjuk `employees(employee_id)` lewat `sys.foreign_keys`, lalu tulis pengecekan eksplisit untuk setiap tabel yang ketemu (per hari ini setidaknya: `article_workflow_logs.employee_id`, `bundles.employee_id`, `projects.project_md`, `projects.project_pic`, `material_movement.giver_employee_id`, `material_movement.received_employee_id`) — konfirmasi hasil penelusuran di ringkasan akhir.

Kalau ada referensi:
```
RAISERROR('Karyawan "%s" sudah dipakai di transaksi dan tidak bisa dihapus. Nonaktifkan saja.', 16, 1, @EmployeeName)
```

### Aturan SETACTIVE

Toggle `is_active`, isi `updated_at` / `updated_by`. Tidak ada pengecekan referensi — nonaktifkan selalu boleh.

### Halaman Blazor `/ppic/karyawan`

- List: pagination + search + sorting (pakai `TablePagination`, `SortableHeader`, `PageSizeSelector`)
- Kolom: Kode, Nama, Divisi, Posisi, Line, Tgl Masuk, **Status** (badge Aktif / Nonaktif)
- Karyawan nonaktif **tetap tampil di list** ini (dengan badge), tidak disembunyikan
- Form: Kode (auto + override), Nama, Divisi (dropdown terbatas), Posisi, Line/Resource (cascading dari divisi, sama seperti Master Karyawan), Tanggal masuk
- Tombol per baris: Edit, Aktifkan/Nonaktifkan, Hapus (dengan konfirmasi)

---

## D. Dampak ke module yang sudah ada

### 1. Master Divisi

- Checkbox **"Dikelola PPIC"** di form
- Kolom Status di list
- `SIS_Division_Manage`: tambah `@PpicManaged bit = NULL`, pakai `COALESCE(@PpicManaged, ppic_managed)` di UPDATE — **default NULL, bukan 0**, supaya caller lama tidak diam-diam mematikan flag
- `SIS_Division_GetAll` / `GetById`: expose `ppic_managed AS PpicManaged`

### 2. Master Karyawan (admin, `MASTER_EMPLOYEE`)

- Kolom Status + tombol Aktifkan/Nonaktifkan di list
- Cakupannya **tidak berubah** — admin tetap melihat & mengelola semua divisi
- `SIS_Employee_Manage`: tambah `@IsActive bit = NULL` dan action `SETACTIVE`
  - Di UPDATE pakai `COALESCE(@IsActive, is_active)` — **wajib default NULL**, kalau default-nya `1` maka setiap update dari caller lama akan mengaktifkan ulang orang yang sudah dinonaktifkan
- `SIS_Employee_GetAll` / `GetById`: expose `is_active AS IsActive`
- Field kode di form Master Karyawan ikut memakai auto-generate yang sama (`SIS_Employee_NextCode`), tetap bisa di-override

### 3. Dropdown employee di seluruh aplikasi

Karyawan nonaktif **hilang dari semua dropdown employee** (MD project, PIC project, penjahit per line dari Prompt 32, dan lainnya).

- Telusuri sendiri semua SP/endpoint yang melayani dropdown employee — jangan menebak nama SP, cari dulu di `sql/` dan di service layer
- Tambahkan filter `is_active = 1` **hanya di SP lookup/dropdown**
- **Pengecualian penting:** nilai yang sudah tersimpan tetap harus muncul di form edit walaupun orangnya sudah nonaktif, ditandai `(nonaktif)`. Kalau tidak, membuka lalu menyimpan ulang project/bundle lama akan menghapus MD/PIC/penjahitnya diam-diam
- **JANGAN** menambahkan filter `is_active` di list, report (`SIS_Report_ProduksiAgg`, `SIS_Report_ProduksiDetail`, WIP dashboard), riwayat log, atau JOIN tampilan mana pun — data historis harus tetap utuh

---

## Yang TIDAK boleh dilakukan

- Mengubah `[RequireModule]` atau logika `EmployeeController` / `SIS_Employee_Manage` selain penambahan `@IsActive` dan `SETACTIVE` di atas
- Membuat tabel karyawan baru — tetap pakai `employees`
- Hardcode `division_id` di mana pun; batasan selalu lewat `ppic_managed`
- Mempercayai `division_id` dari client tanpa validasi `ppic_managed` **di dalam SP**
- Hard delete
- Backfill atau normalisasi kode karyawan lama
- Memakai nomor urut yang pernah terpakai (termasuk milik karyawan yang sudah dihapus)

---

## Urutan deploy

1. Jalankan `sql/alter_53_ppic_employee.sql`
2. Jalankan SP baru + SP yang diubah (`SIS_PpicEmployee_*`, `SIS_Employee_NextCode`, `SIS_Employee_Manage`, `SIS_Employee_Select`, `SIS_Division_Manage`, `SIS_Division_Select`, SP dropdown employee)
3. Jalankan `sql/seed_53_ppic_employee_module.sql`
4. Deploy aplikasi
5. Centang **"Dikelola PPIC"** di Master Divisi untuk divisi yang relevan
6. Buat user PPIC, assign module `PPIC_EMPLOYEE` lewat Module Access

Langkah 5 belum dilakukan = list PPIC kosong dan dropdown divisinya kosong. Itu perilaku yang benar, bukan bug.

---

## Verifikasi

1. User PPIC login → hanya melihat menu Karyawan (PPIC), tidak melihat Master Karyawan
2. User PPIC hit `POST /api/employee` langsung (mis. lewat curl) → **403**
3. User PPIC kirim `division_id` divisi yang `ppic_managed = 0` lewat request manual → ditolak SP dengan pesan jelas
4. Pilih divisi berkode `EM` di form → kode terisi `EM-0001`; simpan; buat lagi → `EM-0002`
5. Ganti divisi jadi `TR` di form edit → kode berubah jadi `TR-0001` setelah konfirmasi
6. Timpa kode manual → tersimpan apa adanya; timpa dengan kode yang sudah ada → error jelas
7. Hapus karyawan yang belum pernah dipakai → berhasil; hapus yang sudah punya log → ditolak, diarahkan nonaktifkan
8. Nonaktifkan penjahit → hilang dari dropdown penjahit per line; bundle lama yang memakai dia **tetap** menampilkan namanya di list, report, dan riwayat
9. Buka form edit project lama yang MD-nya sudah nonaktif → nama tetap muncul dengan tanda `(nonaktif)`; simpan tanpa mengubah apa pun → MD tidak hilang
10. Admin update karyawan lewat Master Karyawan tanpa menyentuh status → status tidak berubah

---

## Output yang diharapkan

Daftar file yang dibuat/diubah, daftar script SQL yang harus dijalankan manual berikut urutannya, dan hasil penelusuran FK ke `employees(employee_id)` serta daftar SP dropdown employee yang ditemukan dan diubah.

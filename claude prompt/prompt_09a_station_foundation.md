# Prompt 9a — Fondasi Stasiun: Skema, Admin, Token Auth

## Konteks

Resource di lantai produksi mencatat log workflow lewat halaman stasiun (tablet/HP) TANPA login user. Autentikasi pakai token per perangkat (station token). Prompt ini membuat fondasinya: tabel, halaman admin kelola stasiun, dan mekanisme autentikasi token di API. Halaman stasiun untuk operator dibuat di Prompt 9b — jangan dibuat sekarang.

## 1. Skema SQL

a. Tambahkan ke `sql/create_tables_tmos_final.sql` (section baru "8. STASIUN"):

```sql
CREATE TABLE stations(
 station_id int primary key identity(1,1),
 station_code varchar(30) not null,
 station_name varchar(150) not null,
 division_id int not null
   constraint FK_stations_divisions foreign key references divisions(division_id),
 station_token varchar(64) not null,        -- GUID tanpa strip, digenerate server
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

Filtered unique index untuk `station_code` dan `station_token` (`WHERE deleted_at IS NULL`), pola sama seperti kode unik lain.

b. Buat `sql/alter_09a_stations.sql` untuk DB yang sudah ada (CREATE TABLE + index di atas, idempotent dengan IF NOT EXISTS).

## 2. Stored Procedures

- `sp_Station_Manage` (@Action: CREATE, UPDATE, DELETE, REGENERATE_TOKEN). CREATE dan REGENERATE_TOKEN menghasilkan token baru (NEWID tanpa strip, lowercase) dan mengembalikannya di result. UPDATE tidak menyentuh token. DELETE = soft delete.
- `sp_Station_List` (paged + search: code, name, division_name; JOIN divisions), `sp_Station_GetById`.
- `sp_Station_GetByToken` — untuk autentikasi: cari stasiun hidup + is_active = 1 berdasarkan token, kembalikan station_id, station_name, division_id, division_name.

## 3. API

### Admin (JWT, module baru STATION_MANAGE)
CRUD stations pola biasa + endpoint POST regenerate-token. Token hanya ditampilkan penuh di response CREATE/REGENERATE; di list cukup 8 karakter awal + "…".

### Autentikasi stasiun (tanpa JWT)
- Buat filter/middleware `[RequireStationToken]`: baca header `X-Station-Token`, validasi via sp_Station_GetByToken, simpan info stasiun di HttpContext.Items. Token tidak valid/nonaktif → 401.
- Endpoint pertama: GET `api/station/me` → info stasiun + divisi (untuk setup perangkat di 9b).
- Endpoint station TIDAK memakai [Authorize] JWT — pastikan tidak konflik dengan konfigurasi auth global.

## 4. Blazor Client (admin saja)

Halaman kelola stasiun, pola CRUD biasa: list (code, name, divisi, badge Aktif, token terpotong) + form create/edit (code, name, dropdown divisi, checkbox aktif). Setelah CREATE atau tombol "Generate Ulang Token": tampilkan token penuh sekali dalam modal dengan tombol salin + peringatan "token lama langsung tidak berlaku".

## 5. Module

- Code: STATION_MANAGE, grup "App Setting", assign ke admin.

## Aturan tetap berlaku

Soft delete, filter deleted_at IS NULL, UserId dari JWT (untuk endpoint admin), konfirmasi delete, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan buat halaman `/station` untuk operator — itu Prompt 9b.
- Jangan sentuh article_workflow_logs atau SP workflow.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

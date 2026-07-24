# Prompt 25 — Modul Packing (Karung): Stok Siap Pack, Buat Karung, Label QR, Scan Publik

## Prasyarat

Dijalankan setelah Prompt 24. Surat jalan dikerjakan di Prompt 26 — JANGAN dibuat di sini (kolom/join shipment belum ada).

## Konteks & keputusan desain (sudah disepakati)

Hasil produksi yang selesai di **step terakhir** workflow artikel menjadi stok siap pack. Operator di **stasiun khusus packing** (tanpa login user, station token biasa) membuat **karung (pack)** berisi campuran artikel/size dalam SATU project, mencetak label QR 6×4 cm, lalu mengonfirmasi qty aktual saat packing fisik selesai.

- Satu karung boleh campur artikel, TIDAK boleh campur project.
- `pack_no` urut per project (1, 2, 3, ...), dihitung termasuk soft-deleted (tidak dipakai ulang) — pola sama dengan `bundle_no`.
- Serial `PK{yy}-{nomor urut global 6 digit}` (mis. `PK26-000012`), pola & applock sama seperti bundle (`pack_serial_seq`).
- QR = `{PublicBaseUrl}/pack/{serial}`, halaman publik tanpa login.
- Label TIDAK mencetak total karung (incremental); "Karung X dari Y" hanya di halaman scan (Y dinamis).
- Dua lapis qty per item: `qty_plan` (perintah kerja) dan `qty_actual` (NULL = belum konfirmasi). Setelah konfirmasi, qty_actual tetap boleh diedit — label bisa dicetak ulang dengan qty terkini.
- Stok tersedia = qty_ok log hidup step terakhir − Σ COALESCE(qty_actual, qty_plan) pack hidup, per artikel per size. Dihitung di SP, TIDAK ada tabel stok baru.
- Cetak lewat `print_jobs` (job_type baru `PACK_LABEL`), printer & worker yang sudah ada.

## 1. Skema SQL

Tambahkan ke `sql/create_tables_tmos_final.sql` (section baru "PACKING") + buat `sql/alter_25_packing.sql` (idempotent):

```sql
CREATE TABLE packs(
 pack_id int primary key identity(1,1),
 project_id int not null
   constraint FK_packs_projects foreign key references projects(project_id),
 pack_no int not null,                      -- urut per project, termasuk soft-deleted
 serial varchar(20) not null,               -- PK{yy}-{6 digit global}
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 delete_reason varchar(255) null
);

CREATE TABLE pack_items(
 pack_item_id int primary key identity(1,1),
 pack_id int not null
   constraint FK_pack_items_packs foreign key references packs(pack_id),
 article_id int not null
   constraint FK_pack_items_articles foreign key references articles(article_id),
 article_size_id int not null
   constraint FK_pack_items_sizes foreign key references article_sizes(article_size_id),
 qty_plan int not null,
 qty_actual int null,                       -- NULL = belum dikonfirmasi
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

Index: filtered unique `UX_packs_serial ON packs(serial) WHERE deleted_at IS NULL`; index `IX_packs_project`, `IX_pack_items_pack` (filtered hidup).

Tambah kolom di `stations`:
```sql
 enable_packing bit not null default 0     -- stasiun ini boleh membuka modul packing
```

## 2. Stored Procedures

### `sql/sp_Pack_Manage.sql` — SIS_Pack_Manage (@Action)

Items dikirim sebagai JSON (`@ItemsJson`: array `{articleId, articleSizeId, qtyPlan}` untuk CREATE/UPDATE_PLAN; `{packItemId, qtyActual}` untuk CONFIRM) — parse dengan OPENJSON.

- **CREATE** (@ProjectId, @ItemsJson, @PublicBaseUrl, @UserId):
  - Validasi: minimal 1 item; qty_plan > 0; semua artikel milik @ProjectId dan hidup; article_size milik artikelnya; tidak ada duplikat (article_id, article_size_id) dalam satu karung.
  - **Validasi stok**: untuk tiap item, qty_plan ≤ stok tersedia (rumus di atas, hitung dalam transaksi). Kurang → RAISERROR menyebut artikel+size+sisa stok.
  - Serial + pack_no digenerate dalam `sp_getapplock` `pack_serial_seq` (pola persis SIS_Bundle_Manage): serial global, pack_no = MAX per project termasuk soft-deleted + 1.
  - INSERT print_jobs (job_type `PACK_LABEL`, ref_id = pack baru, payload lihat §4) — qr_content dirakit di SP dari @PublicBaseUrl (alasan sama dengan bundle: serial baru diketahui di dalam applock).
  - Kembalikan pack_id, pack_no, serial, print_job_id.
- **UPDATE_PLAN** (@Id, @ItemsJson, @UserId): ganti seluruh komposisi planning (soft delete baris lama yang hilang, insert baru, update qty_plan yang berubah). Hanya boleh selama SEMUA baris qty_actual masih NULL. Validasi stok sama seperti CREATE (kecualikan pack ini sendiri dari perhitungan "sudah dipack").
- **CONFIRM** (@Id, @ItemsJson, @UserId): isi/ubah qty_actual per pack_item_id (≥ 0; 0 = batal masuk karung tapi baris tetap tercatat). Boleh dipanggil berulang (edit kondisi terkini). Validasi stok memakai qty_actual baru.
- **DELETE** (@Id, @DeleteReason wajib, @UserId): soft delete pack + semua items.

### `sql/sp_Pack_Select.sql`

- **SIS_Pack_StockAvailable** (@ProjectId): per artikel per size hidup milik project: article_name, style, color, size_name, sort, `qty_done` (Σ qty_ok log hidup pada step hidup dengan sort_order terbesar milik tiap artikel — hati-hati: step terakhir ditentukan PER ARTIKEL, bukan global), `qty_packed` (Σ COALESCE(qty_actual, qty_plan) pack_items hidup), `qty_available` = done − packed. Sertakan juga baris qty_available = 0 agar operator lihat semuanya.
- **SIS_Pack_ListByProject** (@ProjectId): pack hidup + agregat: pack_no, serial, jumlah artikel, total plan, total aktual, `is_confirmed` (1 bila semua baris qty_actual NOT NULL), status label terakhir dari print_jobs (pola SIS_Bundle_ListByArticle), created_at. Result set kedua: seluruh items (pack_id, article_name, style, color, size_name, qty_plan, qty_actual).
- **SIS_Pack_ScanInfo** (@Serial): dua result set —
  1. Info pack: pack_id, pack_no, serial, project_name, `total_packs` (COUNT pack hidup project ini → "Karung {pack_no} dari {total_packs}"), total qty (COALESCE aktual, plan), is_confirmed, created_at.
  2. Items: article_name, style, color, size_name, qty_plan, qty_actual.
  Serial tidak ditemukan → RAISERROR 'Karung tidak ditemukan.'

## 3. API

### Stasiun ([RequireStationToken] + cek packing)
Filter tambahan: endpoint packing menolak 403 bila stasiun tidak `enable_packing` (info sudah ada di HttpContext dari SIS_Station_GetByToken — tambahkan kolom enable_packing ke SP itu dan ke `api/station/me`).

- GET `api/station/packing/projects` → project aktif untuk dropdown (pakai SP/endpoint project aktif yang sudah ada bila cocok, jangan bikin baru tanpa perlu).
- GET `api/station/packing/stock/{projectId}` → SIS_Pack_StockAvailable.
- GET `api/station/packing/packs/{projectId}` → SIS_Pack_ListByProject.
- POST `api/station/packing/packs` — body: projectId, items[], autoPrint (bool).
- PUT `api/station/packing/packs/{id}/plan` — body: items[].
- PUT `api/station/packing/packs/{id}/confirm` — body: items[] (packItemId, qtyActual).
- POST `api/station/packing/packs/{id}/reprint` → insert print_jobs baru, payload dirakit ulang dari data TERKINI.
- DELETE `api/station/packing/packs/{id}` — body/query: reason (wajib).

`created_by`/`updated_by` pakai user sistem 'station' (pola pencatatan log stasiun yang sudah ada).

### Publik (tanpa autentikasi, read-only)
- GET `api/public/packs/{serial}` → SIS_Pack_ScanInfo. Hanya GET.

## 4. Print Service — PACK_LABEL 6×4 cm

Payload JSON: serial, qr_content, project_name, pack_no, total_qty, item_count, is_confirmed.

TsplBuilder: method baru `BuildPackLabel` (jangan sentuh BUNDLE_LABEL). Setup sama label 6×4 (SIZE 60 mm, 40 mm; GAP 3 mm; 480×320 dot):
- Kiri: QR ± 23 mm dari qr_content + serial kecil di bawahnya.
- Kanan: project_name kecil rata kanan (potong 22 kar); `"Karung No. " + pack_no` elemen TERBESAR; garis; `total_qty + " pcs"` besar + `item_count + " artikel"` sedang; garis; baris bawah: tanggal cetak (dd/MM) + badge teks `"PLAN"` bila is_confirmed = 0, `"AKTUAL"` bila 1.
- Worker: job_type `PACK_LABEL` → BuildPackLabel; job_type lain tidak berubah.

## 5. Blazor Client

### `/station` — tab/panel baru "Packing"
Muncul hanya bila `me.enablePacking`. Isi:
1. Dropdown project → dua sub-tab:
2. **Stok Siap Pack**: tabel artikel/size: selesai, sudah dipack, tersedia (tebalkan yang > 0).
3. **Karung**: kartu per pack (pola kartu bundle): "Karung No. X" besar, serial, badge PLAN (kuning) / AKTUAL (hijau), ringkasan isi, status label. Tombol per kartu: **Konfirmasi** (grid item: qty aktual, default = plan) / **Edit Aktual** (setelah konfirmasi), **Edit Planning** (hanya selama belum ada aktual), **Cetak Ulang**, **Hapus** (modal alasan wajib).
4. Tombol **"Buat Karung"**: form baris dinamis (dropdown artikel → dropdown size → qty; tampilkan sisa stok di samping), tambah/hapus baris, checkbox "Cetak label otomatis" default aktif. Sukses → toast berisi nomor karung.

### Halaman publik `/pack/{serial}`
Pola `/b/{serial}`: tanpa login, mobile-friendly. Header "Karung {pack_no} dari {total_packs}" besar, project, badge PLAN/AKTUAL, tabel isi (artikel, size, plan, aktual), total. Placeholder section pengiriman JANGAN dibuat (Prompt 26).

### Admin — Kelola Stasiun
Checkbox "Modul Packing" di form create/edit stasiun (kolom enable_packing), tampilkan badge di list. SIS_Station_Manage tambah parameter @EnablePacking.

## 6. Verifikasi

- Buat 2 artikel 1 project, selesaikan step terakhir sebagian → stok tersedia benar.
- Buat karung campur 2 artikel → pack_no = 1, serial PK26-xxxxxx, print job PENDING, label DryRun: semua elemen dalam 480×320 dot, badge PLAN.
- Konfirmasi qty berbeda dari plan → stok tersedia bergeser mengikuti aktual; cetak ulang → payload qty terbaru + badge AKTUAL.
- Coba qty melebihi stok → tertolak dengan pesan jelas.
- Hapus karung → pack_no tidak dipakai ulang; stok kembali.
- `/pack/{serial}` tampil tanpa login; serial salah → pesan tidak ditemukan.
- Stasiun tanpa enable_packing tidak melihat tab dan tertolak 403 di endpoint.

## Yang TIDAK boleh dilakukan

- Jangan sentuh alur bundle, SIS_WorkflowLog_Manage, atau layout BUNDLE_LABEL.
- Jangan buat tabel stok/saldo — stok selalu dihitung dari log + pack_items.
- Jangan bikin apa pun terkait surat jalan (Prompt 26).

Setelah selesai: daftar file yang diubah/dibuat.

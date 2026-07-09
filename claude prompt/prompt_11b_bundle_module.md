# Prompt 11b — Module Bundle Mandiri (BUNDLE_MANAGE)

## Konteks

Pembuatan bundle saat ini menumpang privilege PROJECT dan hanya bisa diakses lewat Project → Edit Article → Kelola Bundle — terlalu panjang untuk pekerjaan harian supervisor produksi. Prompt ini memberi bundle module dan pintu masuknya sendiri. Halaman kelola bundle yang sudah ada DIPAKAI ULANG, jangan dibuat ulang.

## 1. Module & SQL

Buat `sql/seed_bundle_manage_module.sql` (idempotent, pola sama dengan seed module lain):
- Module Code `BUNDLE_MANAGE`, Name "Bundle", Category "App Setting"... sesuaikan dengan pola grup yang dipakai module operasional (ikuti penempatan module PROJECT), Route `bundles`, icon yang cocok (mis. fe fe-package), SortOrder setelah PROJECT.
- Assign otomatis ke semua user Role = Admin.

## 2. API

Pindahkan otorisasi semua endpoint bundle (list by article, create, update, delete, reprint) dari `RequireModule("PROJECT")` ke `RequireModule("BUNDLE_MANAGE")`. Endpoint lain tidak berubah.

## 3. Blazor Client

a. **Halaman baru `/bundles`** (menu sidebar dari module):
   - Bagian atas: pemilih artikel — dropdown Project (hidup, terbaru dulu) → tabel artikel project itu (nama, style, color, thumbnail foto utama, total qty order, jumlah bundle yang sudah ada).
   - Klik artikel → panel kelola bundle tampil di halaman yang sama (komponen dari halaman `/articles/{articleId}/bundles` diekstrak jadi komponen reusable, mis. `BundleManager.razor`, lalu dipakai di kedua tempat).
   - Sediakan juga kotak pencarian artikel lintas project (cari nama artikel/style, min. 3 karakter) sebagai jalan pintas — perlu endpoint + SP kecil `sp_Article_Search` (@Keyword, hasil max 20: article_id, article_name, style, color, project_name).
b. **Halaman `/articles/{articleId}/bundles`** tetap berfungsi, kini memakai komponen yang sama. Tombol "Kelola Bundle" di Edit Article hanya tampil jika user punya module BUNDLE_MANAGE (pakai mekanisme cek module yang sudah ada di client).

## Aturan tetap berlaku

Soft delete, filter deleted_at IS NULL, UserId dari JWT, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan ubah sp_Bundle_Manage atau logika bundle apa pun — hanya otorisasi, module, dan pintu masuk UI.
- Jangan sentuh print service / print_jobs.
- Jangan duplikasi markup kelola bundle — wajib ekstraksi komponen.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

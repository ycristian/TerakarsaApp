# Prompt Claude Code — Poin 2: Master Divisions, Positions, Resource Types

Buat fitur CRUD lengkap untuk 3 tabel master: `divisions`, `positions`, `resource_types`.

## Acuan pola
Tiru persis pola yang sudah ada di fitur **Product** (SP dengan @Action, controller, service, halaman Blazor dengan pagination + search + sorting). Struktur tabelnya ada di file sql/create_tables_tmos_final.sql (sudah dijalankan di database).

## Yang dibuat per tabel

### 1. Stored Procedure (1 SP per tabel, pola @Action seperti sp_Product_Manage)
- Action: GETALL (dengan @PageNumber, @PageSize, @SearchTerm, @SortColumn, @SortDirection), GETBYID, CREATE, UPDATE, DELETE
- DELETE = soft delete (isi deleted_at, deleted_by), bukan DELETE fisik
- Semua query filter `deleted_at IS NULL`
- CREATE/UPDATE isi created_by/updated_by dari parameter @UserId
- Kolom unik (division_code, resource_type_code): kalau duplikat dengan baris hidup, kembalikan pesan error yang jelas — jangan biarkan error index mentah sampai ke user

### 2. API (per tabel)
- Model di TerakarsaApp.Shared (snake_case kolom → PascalCase property)
- Controller + Service mengikuti pola ProductController/ProductService
- Endpoint: GET list (paged), GET by id, POST, PUT, DELETE
- Semua endpoint pakai [Authorize] + [RequireModule] dengan module code baru: MASTER_DIVISION, MASTER_POSITION, MASTER_RESOURCE_TYPE
- @UserId diambil dari claim JWT, bukan dari request body

### 3. Blazor Client (per tabel)
- Halaman list: tabel + pagination + search + sorting (pakai komponen TablePagination, SortableHeader, PageSizeSelector yang sudah ada)
- Form create/edit dalam modal atau halaman terpisah — ikuti pola Product
- Validasi Data Annotations: code & name wajib diisi, panjang maksimal sesuai kolom (code 30, name 150)
- Konfirmasi sebelum delete
- Tambahkan menu di sidebar, grup "Master Data"

### 4. Registrasi module
- Insert 3 module baru ke tabel Modules (untuk RequireModule dan menu dinamis)
- Assign ke user admin yang ada

## Aturan umum
- Jangan sentuh fitur Product (masih dipakai sebagai referensi, dihapus nanti)
- Jangan ubah struktur tabel yang sudah ada
- Bahasa UI: Indonesia
- Setelah selesai, tuliskan daftar file yang dibuat/diubah dan script SQL yang harus saya jalankan manual

## Urutan kerja
Kerjakan divisions dulu sampai jalan, baru replikasi ke positions dan resource_types.

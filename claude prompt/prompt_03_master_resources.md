# Prompt Claude Code — Poin 3: Master Resources

Buat CRUD untuk tabel `resources`, meniru pola yang sudah jadi di divisions (SP @Action, controller, service, halaman Blazor).

## Beda dari divisions

1. **Dua FK wajib**: `division_id` dan `resource_type_id`
   - Form: dropdown Division dan Resource Type, ambil dari API masing-masing (hanya data hidup)
   - SP GETALL: JOIN ke divisions dan resource_types, tampilkan division_name dan resource_type_name di list
   - Search juga mencari di division_name dan resource_type_name
2. **Kolom `is_active` (bit)**: checkbox di form, tampil sebagai badge Aktif/Nonaktif di list, default aktif saat create
3. Tidak ada kolom code — hanya `resource_name` (wajib, max 150)

## Module
- Code: MASTER_RESOURCE, assign ke admin
- Menu di sidebar grup "Master Data"

## Aturan tetap berlaku
Soft delete, filter deleted_at IS NULL, UserId dari JWT, konfirmasi delete, UI bahasa Indonesia.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

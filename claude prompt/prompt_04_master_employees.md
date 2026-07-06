# Prompt Claude Code — Poin 4: Master Employees

Buat CRUD untuk tabel `employees`, meniru pola resources (yang punya dropdown FK).

## Kolom & aturan form

| Kolom | Aturan |
|---|---|
| employee_code | wajib, max 30, unik (filtered index — tangani error duplikat dengan pesan jelas) |
| employee_name | wajib, max 150 |
| division_id | wajib, dropdown Division |
| position_id | wajib, dropdown Position |
| resource_id | **opsional**, dropdown Resource + pilihan kosong "- Tidak ada -" |
| join_date | opsional, date picker |

## Perilaku khusus

1. Dropdown Resource **terfilter berdasarkan Division yang dipilih** — kalau division berubah, pilihan resource ikut berubah dan pilihan lama di-reset
2. SP GETALL: JOIN division, position, resource (LEFT JOIN karena nullable); tampilkan nama-namanya di list; search mencakup code, name, division_name, position_name

## Module
- Code: MASTER_EMPLOYEE, assign ke admin, menu grup "Master Data"

## Aturan tetap berlaku
Soft delete, filter deleted_at IS NULL, UserId dari JWT, konfirmasi delete, UI bahasa Indonesia.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

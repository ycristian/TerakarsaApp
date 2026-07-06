# Prompt Claude Code — Poin 5: Master Buyers

Buat CRUD untuk tabel `buyers`, meniru pola divisions (paling sederhana, tanpa FK).

## Kolom & aturan form

| Kolom | Aturan |
|---|---|
| buyer_code | wajib, max 30, unik (tangani duplikat dengan pesan jelas) |
| buyer_name | wajib, max 150 |
| address | opsional, max 255, textarea |
| phone | opsional, max 30 |

## Module
- Code: MASTER_BUYER, assign ke admin, menu grup "Master Data"

## Aturan tetap berlaku
Soft delete, filter deleted_at IS NULL, UserId dari JWT, konfirmasi delete, UI bahasa Indonesia.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

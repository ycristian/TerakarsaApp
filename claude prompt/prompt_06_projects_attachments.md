# Prompt Claude Code — Poin 6: Projects + Attachments

Buat fitur Project (order intake) untuk tabel `projects` dan `project_attachments`. Pola dasar CRUD meniru resources/employees (dropdown FK, SP @Action).

## Bagian 1 — Projects (CRUD)

### Kolom & aturan form

| Kolom | Aturan |
|---|---|
| project_name | wajib, max 150 |
| customer_id | wajib, dropdown Buyer |
| project_md | opsional, dropdown Employee + pilihan "- Tidak ada -" |
| project_pic | opsional, dropdown Employee + pilihan "- Tidak ada -" |
| no_po | opsional, max 50 |
| order_date, start_date, deadline, delivery_date | opsional, date picker |

### SP `sp_Project_Manage`
- Action standar: GETALL, GETBYID, CREATE, UPDATE, DELETE (soft delete)
- GETALL: JOIN buyers (buyer_name), LEFT JOIN employees 2x (nama MD, nama PIC — alias berbeda)
- Search: project_name, no_po, buyer_name
- Kolom tanggal ikut ditampilkan di list (order_date, deadline)

### Halaman list
- Kolom: project_name, buyer_name, no_po, order_date, deadline, MD, PIC
- Setelah CREATE berhasil → langsung navigasi ke halaman **edit** project tsb (supaya bisa lanjut upload lampiran)

## Bagian 2 — Attachments (di halaman edit project)

Section "Lampiran" di halaman edit, hanya muncul kalau project sudah tersimpan.

### Upload
- Input file (multipart/form-data) + input description (opsional, max 255)
- Validasi server: tipe hanya jpg/png/pdf/xlsx, max 10 MB — tolak dengan pesan jelas
- File disimpan lewat interface **`IFileStorageService`** (implementasi sekarang: `LocalFileStorageService`, folder dari appsettings key `FileStorage:BasePath`, subfolder `projects/{project_id}/`)
  - Interface ini yang nanti diganti implementasi Azure Blob — controller tidak boleh tahu detail storage
- Nama file di disk = GUID + ekstensi asli. DB simpan: file_name (nama asli), file_path (path relatif dari BasePath), file_size_kb (dihitung server), file_type (ekstensi lowercase)

### List & aksi lampiran
- Tabel: file_name, file_type, ukuran (KB), description, tombol Download & Hapus
- Download: endpoint yang stream file berdasarkan project_attachment_id (validasi project_id cocok)
- Hapus: soft delete metadata saja, file fisik dibiarkan
- Endpoint attachment tidak perlu SP @Action lengkap — cukup SP sederhana: GETBYPROJECT, CREATE, DELETE

### Keamanan
- Semua endpoint (termasuk upload/download) pakai [Authorize] + [RequireModule]
- Jangan pernah pakai file_path dari input client — selalu dari DB

## Module
- Code: ORDER_PROJECT, route `projects`, grup menu baru **"Order"** di sidebar (bukan Master Data), assign ke admin

## Aturan tetap berlaku
Soft delete, filter deleted_at IS NULL, UserId dari JWT, konfirmasi delete, UI bahasa Indonesia. Jangan ubah struktur tabel.

## Urutan kerja
1. CRUD projects sampai jalan (tanpa attachment)
2. IFileStorageService + upload + list + download + delete lampiran

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual (SP + registrasi module + appsettings key yang perlu diisi).

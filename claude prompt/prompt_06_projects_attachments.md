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


# Prompt Claude Code — Poin 7: Kompres Gambar + Multi-File Upload Lampiran

Sempurnakan fitur lampiran project (Lampiran di halaman edit project) yang sudah jadi:
1. Kompres otomatis gambar di server sebelum disimpan
2. Upload bisa banyak file sekaligus

## 1. Image Compression Service

Install package SixLabors.ImageSharp (versi stable terbaru) di TerakarsaApp.API.

Buat `ImageCompressionService` di TerakarsaApp.API/Services:

`Task<CompressResult> CompressAsync(Stream input, string fileExtension)`

Aturan:
- Hanya proses .jpg, .jpeg, .png. Ekstensi lain (pdf, xlsx) kembalikan apa adanya tanpa diubah.
- Kalau lebar gambar > 1920px, resize ke lebar 1920 (aspect ratio dijaga).
- Simpan ulang sebagai JPEG quality 80 — termasuk input PNG, jadi output gambar selalu .jpg.
- CompressResult: Stream hasil, ekstensi akhir, ukuran akhir dalam KB.
- File yang gagal dibaca sebagai gambar (corrupt) → lempar exception dengan pesan jelas, endpoint tangani jadi BadRequest per file (file lain di batch tetap lanjut).

Registrasi DI di Program.cs (scoped).

Nilai max width (1920) dan quality (80) di appsettings.json section "ImageCompression".

## 2. Integrasi ke endpoint upload lampiran

- Panggil ImageCompressionService sebelum file disimpan ke folder.
- Yang disimpan hanya versi kompres — original dibuang.
- `file_size_kb` di project_attachments = ukuran setelah kompres.
- Kalau ekstensi berubah (png → jpg): `file_type` = jpg, dan file_name yang disimpan sesuaikan ekstensinya jadi .jpg (nama dasar tetap).
- Validasi tipe file (jpg/png/pdf/xlsx) dan max 10 MB tetap berlaku, dicek terhadap file asli sebelum kompres.

## 3. Multi-file upload

- API: ubah/tambah endpoint upload agar menerima banyak file dalam satu request.
- Deskripsi (opsional) berlaku untuk semua file dalam batch tersebut.
- Response berisi hasil per file: sukses atau gagal + alasan (misal tipe tidak didukung, terlalu besar, corrupt). Satu file gagal tidak membatalkan file lain.
- Blazor: InputFile dengan atribut multiple, tampilkan daftar file terpilih sebelum tombol Unggah ditekan, dan tampilkan hasil per file setelah upload (yang gagal ditandai dengan alasannya).
- Setelah upload selesai, refresh tabel lampiran.

## Batasan
- Jangan ubah struktur tabel.
- Jangan sentuh fitur lain.
- UI bahasa Indonesia.

## Verifikasi
1. Upload jpg 4000px → tersimpan lebar 1920px, ukuran jauh lebih kecil, file_size_kb sesuai hasil kompres.
2. Upload png → tersimpan sebagai .jpg, file_type = jpg.
3. Upload pdf → tersimpan apa adanya.
4. Upload 3 file sekaligus (1 di antaranya file .txt yang di-rename jadi .jpg) → 2 sukses, 1 gagal dengan pesan jelas.

Setelah selesai: daftar file yang dibuat/diubah + script SQL kalau ada.
# Prompt Claude Code — Poin 7: Size Pack & Artikel

Dua bagian. Kerjakan Bagian A dulu sampai jalan, baru Bagian B.

## Bagian A — Master Size Pack (module baru)

Master-detail dalam satu layar: header `size_packs` + grid `size_pack_details`.

### Form
| Field | Aturan |
|---|---|
| buyer_id | wajib, dropdown buyer (hanya data hidup) |
| size_pack_name | wajib, max 150 |
| Grid detail | minimal 1 baris. Per baris: size_name (wajib, max 50), sort_order (angka, urutan tampil), description (opsional, max 255). Bisa tambah/hapus baris. |

### Stored Procedure
- `sp_SizePack_Manage` (@Action CREATE/UPDATE/DELETE):
  - CREATE/UPDATE terima detail sebagai JSON (`@Details nvarchar(max)`, parse dengan OPENJSON), header + detail dalam **satu transaksi**
  - UPDATE: baris detail yang dihapus user → soft delete; baris baru → insert; baris lama → update
  - DELETE = soft delete header + semua detailnya
- SP read terpisah:
  - `sp_SizePack_List` — paged, search, sorting, JOIN buyer_name
  - `sp_SizePack_GetById` — 2 result set: header + detail hidup urut sort_order

### Module
Code: `MASTER_SIZE_PACK`, grup "Master Data", assign ke admin.

## Bagian B — Artikel (di dalam module Project, TANPA module baru)

Privilege pakai module PROJECT yang sudah ada. Tidak ada menu baru di sidebar.

### Halaman list Project — layout 2 panel sejajar (2:1)
- Panel kiri (2/3): tabel project yang sudah ada (pagination, search, sorting tetap)
- Panel kanan (1/3): panel artikel, awalnya kosong dengan teks "Pilih project untuk melihat artikel"
- Klik baris project → baris berubah warna very light gray (selected), panel kanan memuat artikel project itu via `sp_Article_ListByProject`
- Isi panel kanan per artikel: thumbnail foto utama, nama artikel, style, color, total qty, tombol **Edit** (navigasi ke halaman edit artikel) dan tombol **Hapus** (konfirmasi dulu)
- Tombol **Tambah Artikel** di atas panel kanan, hanya aktif setelah project dipilih
- Layar kecil: panel jadi bertumpuk (project di atas, artikel di bawah)

### Halaman edit Project — tambahan tabel artikel
Di bawah form project dan attachment yang sudah ada, tambahkan tabel artikel:
kolom = thumbnail foto utama, nama artikel, style, color, nama size pack, total qty, tombol Edit (ke halaman edit artikel) dan Hapus.

### Halaman edit Artikel (page terpisah)
Create dan edit pakai **satu halaman yang sama**. Route: `/projects/{projectId}/articles/{articleId}/edit` (create: `/projects/{projectId}/articles/create`).
Berisi form artikel + grid ukuran + bagian foto. Ada tombol kembali ke edit project.
Setelah simpan artikel baru → tetap di halaman ini (berubah jadi mode edit) supaya bisa langsung upload foto.

### Form artikel
| Field | Aturan |
|---|---|
| article_name | wajib, max 150 |
| style, color | opsional, max 100 |
| size_pack_id | wajib, dropdown. **Filter: hanya size pack milik buyer project ini** (size_packs.buyer_id = projects.customer_id) dan hidup |
| Grid ukuran | otomatis di-generate dari size_pack_details saat size pack dipilih. Per baris: nama ukuran (readonly), qty (int ≥ 0), bundle_qty (int ≥ 0). Default 0. |

Saat **edit** dan size pack diganti: tampilkan konfirmasi bahwa baris ukuran lama akan dihapus dan digenerate ulang. Setelah konfirmasi, baris lama di-soft-delete, baris baru dibuat.

### Foto artikel (article_photos) — dikelola di halaman edit artikel
- Upload multi-file jpg/png — ikuti pola upload yang sudah dibuat untuk project_attachments (penyimpanan file, validasi ukuran, endpoint)
- Tampilkan sebagai thumbnail grid, satu foto bisa ditandai sebagai utama (is_primary) — hanya boleh 1 yang primary per artikel; foto pertama yang diupload otomatis jadi primary
- Foto utama inilah yang tampil sebagai thumbnail di panel artikel dan tabel artikel
- Hapus foto = soft delete metadata (file fisik dibiarkan)

### Stored Procedure
- `sp_Article_Manage` (@Action CREATE/UPDATE/DELETE):
  - CREATE/UPDATE: header artikel + sizes (JSON, OPENJSON) dalam satu transaksi
  - DELETE = soft delete artikel + article_sizes + article_photos-nya
- SP read terpisah:
  - `sp_Article_ListByProject` (@ProjectId) — list + total qty + jumlah foto
  - `sp_Article_GetById` — 3 result set: artikel, sizes hidup (urut sort_order size pack), photos hidup

## Aturan tetap berlaku
Soft delete, filter deleted_at IS NULL, UserId dari JWT, konfirmasi delete, UI bahasa Indonesia. Jangan ubah struktur tabel.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

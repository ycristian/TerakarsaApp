# Prompt 19 — Grid Input Hasil Cutting, Modal Tambah Bundle, & Article Size Hanya untuk Qty > 0

> Independen dari Prompt 18 (status project); tidak menyentuh SP yang sama. Boleh dieksekusi sebelum atau sesudahnya.

Tiga perubahan terkait kemudahan input:

## Bagian A — Input Hasil Cutting berbentuk grid (semua size sekaligus)

> Cakupan: HANYA input step non-bundle di `WorkflowInputManager.razor`. Form pembuatan bundle TIDAK memakai grid — tetap satu per satu (lihat Bagian C).

### Kondisi sekarang
`WorkflowInputManager.razor`: form input satu size per simpan (SearchableSelect size + Qty OK + 3 reject + Pelaksana + Catatan). Merepotkan saat cutting menyerahkan banyak size sekaligus.

### Target
Ganti form menjadi grid meniru pola "Grid Ukuran" di `ArticleEdit.razor`:

| Ukuran | Qty OK | Reject Print | Reject Bahan | Reject Jahit |
|---|---|---|---|---|
| (satu baris per size artikel) | input number | input number | input number | input number |

- Baris = seluruh `article_sizes` hidup artikel (setelah Bagian B otomatis hanya size ber-qty order > 0).
- Di bawah grid: **Pelaksana (opsional)** dan **Catatan (opsional)** — SATU untuk seluruh batch, berlaku ke semua baris log yang tersimpan. Divisi Tujuan tetap tampil read-only seperti sekarang.
- Satu tombol Simpan. Baris yang seluruh angkanya 0 dilewati. Minimal satu baris berisi angka > 0, kalau tidak tampilkan validasi.
- Setelah sukses: grid dikosongkan, ringkasan qty per size (tabel selisih yang sudah ada) dan riwayat log di bawahnya refresh.
- Model data TIDAK berubah: tetap satu baris `article_workflow_logs` per size. Riwayat, revisi (12d), dan laporan tidak terpengaruh.

### Backend — endpoint batch, satu transaksi
- Endpoint baru di `WorkflowInputController.cs` (mis. `POST .../logs/batch`), body: list entri `{ArticleSizeId, QtyOk, RejectPrint, RejectBahan, RejectJahit}` + `ResourceId?`, `Remark?`, step tujuan.
- `WorkflowLogService.cs`: loop `EXEC SIS_WorkflowLog_Manage @Action='CREATE'` per entri **di dalam SATU transaksi DB** — gagal satu, rollback semua, kembalikan pesan error SP + size yang gagal. Validasi tetap satu sumber di SP; TIDAK membuat SP baru dan TIDAK mengubah `sp_WorkflowLog_Manage.sql`.
- `WorkflowLogModels.cs` (atau model terkait WORKFLOW_INPUT): tambah request batch.
- Privilege endpoint sama dengan endpoint create tunggal yang ada. Endpoint tunggal tetap dipertahankan (dipakai revisi/UPDATE).

## Bagian B — `article_sizes` hanya dibuat untuk qty order > 0

### Kondisi sekarang
`SIS_Article_Manage` insert `article_sizes` untuk SEMUA size di JSON `@Sizes`, termasuk qty 0 → dropdown size di pembuatan bundle dan input cutting penuh size yang tidak dipesan.

### Target — ubah `sql/sp_Article_Manage.sql`
- **CREATE**: insert hanya entri JSON dengan `Qty > 0`.
- **UPDATE**:
  1. Entri `Qty > 0`, sudah ada baris hidup → update (seperti sekarang).
  2. Entri `Qty > 0`, belum ada baris hidup → insert (cabang ini sudah ada; pastikan juga meng-"hidupkan kembali"/insert baru bila baris lama sudah soft-delete — pilih insert baru agar sederhana, kecuali ada unique constraint filtered yang menghalangi; kalau ada, restore baris lama: `deleted_at = NULL` + update qty).
  3. Entri `Qty = 0` (atau size template tidak dikirim), tapi ada baris hidup:
     - Belum direferensikan `bundles` atau `article_workflow_logs` hidup → soft delete baris `article_sizes`.
     - Sudah direferensikan → RAISERROR: `'Size <nama> sudah memiliki bundle/log produksi, qty tidak boleh dikosongkan.'` dan batalkan seluruh simpan.
- **Grid Ukuran di `ArticleEdit.razor` TIDAK berubah**: tetap menampilkan seluruh size dari size pack (nilai 0 untuk yang belum ada barisnya), supaya size bisa diisi belakangan. Hanya perilaku simpannya yang berubah lewat SP.
- Perbarui komentar header SP dan komentar tabel `article_sizes` di `create_tables_tmos_final.sql` sesuai aturan baru.

### Data uji lama (opsional, script manual)
Buat `sql/cleanup_19_article_sizes_qty0.sql`: soft delete `article_sizes` hidup ber-`qty = 0` yang tidak direferensikan bundle/log hidup (`deleted_by = 1`). Dijalankan manual sekali.

## Bagian C — Form tambah bundle jadi modal pop-up

### Kondisi sekarang
`BundleManager.razor`: form tambah bundle tampil inline sebagai card, berdampingan dengan ringkasan per ukuran dan daftar bundle. Edit bundle SUDAH memakai modal Bootstrap.

### Target
- Ganti card form tambah dengan tombol **"+ Tambah Bundle"** (posisi di header/atas daftar bundle).
- Klik tombol → buka modal "Tambah Bundle" berisi field yang sama seperti sekarang (Ukuran, Qty, Penjahit resource, Nama Penjahit bebas, dan Pelaksana Bundling dari Prompt 17). Pembuatan tetap SATU bundle per simpan — tidak ada grid/batch.
- Pola modal, tutup (klik backdrop/tombol), validasi, dan state saving meniru modal Edit Bundle yang sudah ada di file yang sama.
- Setelah simpan sukses: modal tertutup, daftar bundle & ringkasan refresh, notifikasi/alert sukses seperti perilaku sekarang (termasuk info print job label).
- Tidak ada perubahan API/SP di bagian ini.

## Aturan tetap berlaku
Soft delete, filter `deleted_at IS NULL`, prefix `SIS_`, pola `@Action`, UI bahasa Indonesia, pola komponen/validasi mengikuti yang sudah ada di file terkait.

## Yang TIDAK boleh dilakukan
- Jangan ubah skema tabel apa pun (tidak ada ALTER).
- Jangan ubah `sp_WorkflowLog_Manage.sql` — batch cukup loop di service dalam satu transaksi.
- Jangan hapus endpoint/form create tunggal yang dipakai alur revisi.
- Jangan ubah tampilan Grid Ukuran di ArticleEdit (tetap semua size template).
- Jangan buat grid/batch untuk pembuatan bundle — tetap satu bundle per simpan.
- Jangan sentuh logika bundle (Prompt 17) dan status project (Prompt 18) di SP/API.

## Verifikasi
1. `dotnet build` sukses.
2. Skenario manual:
   - Artikel baru, isi qty hanya untuk S & M → dropdown size di buat bundle dan grid input cutting hanya S & M.
   - Edit artikel, isi qty L → L muncul; kosongkan qty M yang belum dipakai → M hilang; kosongkan qty S yang sudah punya bundle → ditolak dengan pesan jelas.
   - Input Hasil Cutting via grid: isi 2 size sekaligus + pelaksana → tersimpan 2 baris log, pelaksana sama; riwayat & ringkasan selisih ter-refresh.
   - Simpan grid dengan semua 0 → validasi muncul, tidak ada request.
   - Satu baris gagal validasi SP (mis. qty exceed) → tidak ada satu pun log tersimpan, pesan error menyebut size-nya.
   - Tambah bundle: tombol "+ Tambah Bundle" membuka modal, simpan sukses → modal tutup, daftar & ringkasan refresh; batal/klik backdrop menutup tanpa menyimpan.
3. Di akhir: daftar file diubah/dibuat + script SQL manual (`sp_Article_Manage.sql`, cleanup opsional).

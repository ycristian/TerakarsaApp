# Prompt 83 — Manual Output & Harga Saat Lock

## Konteks
Terakarsa (TMOS), Blazor + SQL Server. Lanjutan Prompt 55–57 (lock workflow log).

Sebelum mengubah apa pun, baca DDL tabel berikut dan SP lock yang sudah ada:
- `workflow_locks`
- `workflow_lock_items`
- `article_workflow_logs`
- `article_workflow_steps`
- `payroll_periods`

Jangan menebak nama kolom. Kalau DDL atau SP yang ditemukan berbeda dari asumsi di bawah, tanyakan dulu sebelum lanjut.

## Tujuan
1. Line bisa mencatat output yang tidak lewat bundle (output manual), tanpa bergantung pada artikel, PO, atau divisi lain.
2. Harga borongan dibekukan saat lock, dan bisa dikoreksi admin produksi di rekap gajian selama periode belum final.

## Prinsip
- Output manual **tidak menyentuh saldo bundle**. Murni untuk gajian dan laporan per resource.
- Tiap divisi mencatat outputnya sendiri. Cutting, bundling, dan QC tidak saling bergantung.
- Artikel boleh ditempelkan belakangan oleh admin, termasuk ke baris yang sudah lock. Menempelkan artikel tidak mengubah fakta qty.
- Harga melekat ke lock item, bukan ke log dan bukan ke manual output.
- PIC tidak pernah melihat atau mengisi harga.

## Bagian 1 — Tabel `manual_outputs`
Kolom:
- `id`
- `resource_id` (operator yang mengerjakan)
- `division_id`
- `article_id` nullable
- `work_description` teks bebas, wajib (contoh: "kaos polos hitam pak Budi")
- `size` nullable
- `qty` int, boleh 0 atau minus
- `reject_qty` int, default 0
- `note` nullable
- `created_by`, `created_at`
- soft delete sesuai konvensi proyek
- `lock_id` nullable, FK ke `workflow_locks`

Tidak ada relasi ke bundle atau PO.

Baris dengan `qty` minus dipakai sebagai **catatan potongan**: PIC menulis kronologi dan usulan potongan di `note`, admin produksi yang menentukan nominalnya di rekap gajian.

## Bagian 2 — Perubahan `workflow_lock_items`
Tambah kolom:
- `source` varchar: `'LOG'` atau `'MANUAL'`
- `manual_output_id` nullable, FK ke `manual_outputs`
- `unit_price` decimal nullable

Constraint: tepat satu dari `log_id` atau `manual_output_id` terisi, sesuai `source`.

Aturan pengisian `unit_price` saat lock:
- Baris `LOG`: ambil tarif dari `article_workflow_steps` untuk artikel dan step terkait, bila ada.
- Baris `MANUAL`: ambil tarif yang sama hanya bila `article_id` sudah terisi dan step bisa ditentukan dari `division_id`; selain itu `NULL`.
- Jika tarif tidak ditemukan, `NULL`. Jangan isi 0.

Jika `article_workflow_steps` belum punya kolom tarif, tambahkan kolom `unit_price` decimal nullable di sana sebagai master tarif per artikel per proses.

## Bagian 3 — Stored Procedure
1. **SP lock yang sudah ada**: perluas agar menerima baris dari `manual_outputs` selain `article_workflow_logs`, menulis `source`, `manual_output_id`, dan `unit_price` sesuai aturan di atas, serta mengisi `manual_outputs.lock_id`.
2. **Guard lock** berlaku di SP untuk semua jalur, termasuk Super Admin: baris yang sudah lock tidak boleh diedit atau dihapus qty-nya.
3. **`SIS_ManualOutput_LinkArticle`**: menempelkan `article_id` ke satu atau banyak baris `manual_outputs`. Boleh untuk baris yang sudah lock. Jika baris sudah lock dan `unit_price` di lock item masih `NULL`, isi dari tarif artikel bila ada; jika sudah terisi, jangan ditimpa.
4. **`SIS_LockItem_UpdatePrice`**: ubah `unit_price` satu lock item. Nilai minus diperbolehkan. Ditolak bila `payroll_periods.finalized_at` periode terkait sudah terisi. Catat `updated_by`, `updated_at`.
5. **Finalisasi periode**: ditolak bila masih ada lock item dalam periode itu dengan `unit_price IS NULL`. Kembalikan daftar baris yang bermasalah (id, source, resource, deskripsi/artikel, qty).

## Bagian 4 — Station tab OUT
- Tambah tombol **"Tambah Output Manual"**.
- Form: artikel (opsional, searchable), deskripsi kerjaan (wajib), size, qty, reject, catatan. Operator diambil dari sesi login, divisi dari stasiun.
- Baris manual tampil di checklist lock yang sama dengan baris log, dibedakan dengan badge "Manual".
- Baris dengan qty minus diberi badge "Potongan".
- Tidak ada kolom harga di sisi station.

## Bagian 5 — Admin
### Halaman "Output Manual"
- Daftar semua `manual_outputs`, filter: belum terhubung artikel, divisi, periode, resource.
- Aksi **Hubungkan ke Artikel** secara massal: pilih beberapa baris, pilih satu artikel, panggil `SIS_ManualOutput_LinkArticle`.

### Rekap Gajian
- Tampilkan baris `LOG` dan `MANUAL` dalam satu daftar per resource, dengan badge sumber.
- Kolom `unit_price` bisa diedit inline, memanggil `SIS_LockItem_UpdatePrice`. Nilai minus diperbolehkan.
- Baris dengan harga kosong disorot.
- Tombol **Finalisasi Periode** terkunci selama masih ada harga kosong, dengan hitungan jumlah baris bermasalah.
- Setelah `finalized_at` terisi, kolom harga menjadi read-only.

## Di luar cakupan prompt ini
- Laporan yang masih memakai `created_at` (belum periode lock).
- Kartu NFC.
- Alur approval potongan.
- Migrasi harga untuk lock item lama yang sudah ada sebelum prompt ini (biarkan `NULL`).

## Output yang diharapkan
- Script migrasi SQL (tabel, kolom, constraint, SP).
- Perubahan Blazor untuk station tab OUT dan dua halaman admin.
- Ringkasan singkat asumsi yang diambil dan hal yang perlu dikonfirmasi.

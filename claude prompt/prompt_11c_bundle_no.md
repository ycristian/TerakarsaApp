# Prompt 11c — No Bundle per Project (bundle_no)

## Konteks

Selain `serial` (identitas mesin/QR), lapangan butuh nomor pendek per PO: bundle pertama project = 1, naik terus lintas artikel sampai project selesai. Nomor TIDAK pernah dipakai ulang meski bundle dihapus. Jalankan SETELAH Prompt 11 (karena menyentuh TSPL di PrintService) dan boleh sebelum/sesudah 11b.

## 1. Skema SQL

a. Di `sql/create_tables_tmos_final.sql`, tabel `bundles`: tambah `bundle_no int not null` setelah `serial`, dengan komentar "nomor urut per project, generate di sp_Bundle_Manage, tidak dipakai ulang".

b. Buat `sql/alter_11c_bundle_no.sql`:
   1. `ALTER TABLE bundles ADD bundle_no int NULL;`
   2. Backfill: nomori SEMUA bundle (termasuk yang soft-deleted) per project, urut created_at lalu bundle_id — project didapat via JOIN articles. Pakai ROW_NUMBER() OVER (PARTITION BY a.project_id ORDER BY b.created_at, b.bundle_id).
   3. `ALTER TABLE bundles ALTER COLUMN bundle_no int NOT NULL;`
   Idempotent (cek kolom sudah ada).

Tidak perlu unique index (project_id tidak ada di bundles); keunikan dijamin di SP karena generate berada dalam applock yang sama dengan serial.

## 2. Stored Procedures

- `sp_Bundle_Manage` CREATE: di dalam applock/transaksi yang sudah ada, hitung `bundle_no = ISNULL(MAX(bundle_no), 0) + 1` atas SEMUA bundle (termasuk deleted) milik project yang sama (JOIN articles). Kembalikan bundle_no di result.
- Payload print_jobs (CREATE dan `sp_Bundle_ReprintLabel`): tambahkan field `bundle_no`.
- `sp_Bundle_ListByArticle` dan `sp_Article_BundleSummary` (jika relevan): sertakan bundle_no.

## 3. API & Client

- Model Shared: tambah BundleNo di response/list bundle.
- UI kelola bundle: kolom **No** (bundle_no) jadi kolom pertama daftar; tampil juga di pesan sukses setelah simpan ("Bundle #27 dibuat").

## 4. PrintService (TSPL)

Ubah layout label 10×5cm: **bundle_no elemen paling besar** di kanan atas (mis. "No. 27", font terbesar), serial turun jadi baris kecil di bawah (tetap tercetak sebagai teks cadangan QR). Sisanya tetap: artikel, style/color, size + qty, project.

## Yang TIDAK boleh dilakukan

- Jangan ubah format serial atau isi QR (`qr_content` tetap URL berisi serial).
- Jangan buat mekanisme pakai-ulang nomor.
- Jangan sentuh alur stasiun/log.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

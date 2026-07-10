# Prompt 12b — Simplifikasi Model Workflow Log (1 Baris per Serah Terima)

## Konteks

Model 2-baris (RECEIVED + COMPLETED) diganti model 1-baris: INSERT = pekerjaan step selesai; penerimaan = mengisi `received_at` + `received_by_resource_id` di baris yang sama (satu-satunya UPDATE yang diizinkan pada log). Kolom `[status]` dihapus. Step non-bundle jadi catatan bebas berulang dan tidak pernah menjadi prasyarat step ber-bundle. Data log yang ada saat ini adalah data uji — boleh dikosongkan.

## 1. Skema SQL

Perbarui `sql/create_tables_tmos_final.sql` dan buat `sql/alter_12b_simplify_logs.sql` (idempotent):

1. `DELETE FROM article_workflow_logs;` (data uji).
2. DROP kolom `[status]`.
3. ADD `article_size_id int null` + `FK_awl_article_sizes` → article_sizes (untuk input size di step non-bundle).
4. ADD `received_remark varchar(500) null` (catatan saat terima, mis. selisih qty).
5. Kolom `received_at`, `received_by_resource_id` kini resmi terpakai — perbarui komentar tabel menjelaskan model baru.

## 2. SIS_WorkflowLog_Manage — tulis ulang

### @Action = 'CREATE' (= pekerjaan step selesai)
Parameter seperti sekarang minus @Status, plus @ArticleSizeId INT = NULL.

Aturan **step non-bundle** (requires_bundle = 0, @BundleId harus NULL):
- Boleh berkali-kali, tanpa prasyarat apa pun.
- @ArticleSizeId WAJIB diisi dan harus milik artikel step itu ('Size wajib dipilih untuk step ini.').
- @TargetDivisionId opsional (hanya info tujuan serah).

Aturan **step ber-bundle** (requires_bundle = 1, @BundleId wajib, milik artikel yang sama):
- Maksimal satu baris hidup per (step, bundle) — tolak ganda.
- Step ber-bundle PERTAMA (MIN sort_order di antara step requires_bundle = 1 hidup): tanpa prasyarat baris sebelumnya; jika `bundles.resource_id` IS NOT NULL maka @ResourceId wajib sama ('Bundle ini ditugaskan ke line lain.').
- Step ber-bundle SELANJUTNYA: baris step ber-bundle tepat sebelumnya (bundle sama) harus ada DAN `received_at` sudah terisi DAN `target_division_id`-nya = divisi step ini ('Bundle belum diterima divisi ini.').
- @TargetDivisionId wajib kecuali step terakhir artikel.
- @ArticleSizeId harus NULL (size sudah melekat di bundle).

Umum: qty non-negatif; @ActingDivisionId (jika diisi) harus = divisi step.

### @Action = 'RECEIVE' (baru — pengganti log RECEIVED)
Parameter: @Id (workflow_log_id), @ReceivedByResourceId, @ReceivedRemark = NULL, @ActingDivisionId = NULL.
- Baris harus hidup, `received_at` masih NULL, `target_division_id` tidak NULL.
- @ActingDivisionId (jika diisi) harus = target_division_id ('Serah terima ini bukan untuk divisi Anda.').
- UPDATE received_at = SYSDATETIME(), received_by_resource_id, received_remark. Tidak mengubah kolom lain.

### @Action = 'DELETE'
Tetap: soft delete + alasan wajib. Tambahan: tolak jika baris ber-bundle ini sudah dipakai sebagai dasar step berikutnya (ada baris hidup step sesudahnya untuk bundle yang sama).

## 3. Validasi urutan workflow (bundle tidak boleh disusul non-bundle)

Di SP pengelola step template DAN step artikel (manage/copy): tolak susunan yang menghasilkan step requires_bundle = 0 dengan sort_order LEBIH BESAR dari step requires_bundle = 1 mana pun ('Step tanpa bundle harus berada sebelum semua step ber-bundle.'). Terapkan juga saat reorder di UI (pesan error yang sama).

## 4. SP turunan — sesuaikan ke model baru

- `SIS_Station_PendingReceives`: baris hidup dengan target_division_id = @DivisionId dan received_at IS NULL (level artikel maupun bundle; sertakan bundle_no/serial bila ada, size_name bila article_size_id terisi).
- `SIS_Station_ActiveWork`: step requires_bundle = 0 milik divisi ini pada artikel yang project-nya aktif — selalu tampil (bisa dicatat kapan pun, tidak sekali pakai).
- `SIS_Bundle_ScanInfo`: aksi dihitung model baru — 'COMPLETE' jika (step ber-bundle pertama & belum ada barisnya & [resource cocok bila ditunjuk]) ATAU (baris step sebelumnya sudah diterima divisiku & step ini belum ada barisnya); 'RECEIVE' jika ada baris bundle ini bertarget divisiku yang received_at IS NULL; selain itu 'NONE' + pesan posisi. Timeline: tiap baris tampil dua stempel — selesai (created_at, resource) dan diterima (received_at, penerima) bila ada.
- `SIS_Article_Wip`: per step — non-bundle: jumlah input + total qty_ok + rincian per size (article_size_id kini selalu terisi); ber-bundle: bundle selesai / diterima / total bundle + qty_ok.
- `SIS_WorkflowLog_ListByArticle`: sertakan article_size_id + size_name, received_at, received_by (nama), received_remark; tanpa kolom status.

## 5. API & Client

- Hapus konsep status dari model Shared; tambah ArticleSizeId, ReceivedAt, ReceivedByResourceName, ReceivedRemark.
- POST `api/station/receive` → kini mengirim workflowLogId (+ resourceId penerima, remark opsional) → action RECEIVE.
- Form Selesai step non-bundle di stasiun: tambah dropdown **Size** (WAJIB, daftar size artikel, validasi client + server); form bisa dipakai berulang — setelah simpan, size terakhir dipertahankan untuk input beruntun.
- Tab Menunggu Diterima, kartu scan, riwayat di Edit Article: sesuaikan tampilan (badge "Menunggu diterima" / "Diterima {waktu} oleh {nama}").
- **Perbaiki bug**: banner error di kartu scan menampilkan teks mentah "actionError" — pastikan pesan error dari server yang tampil.

## Yang TIDAK boleh dilakukan

- Jangan ubah alur pembuatan bundle, print, serial/bundle_no.
- Jangan tambah kolom status baru dalam bentuk apa pun — status selalu diturunkan dari received_at.
- Jangan izinkan UPDATE kolom lain pada log selain trio received_* lewat action RECEIVE.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

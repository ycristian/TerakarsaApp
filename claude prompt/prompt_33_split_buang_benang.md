# Prompt Claude Code — Poin 33: Pemisahan Step "Sew+QC+Buang Benang" → "Sew+QC" + "Buang Benang"

## Konteks & keputusan

Di lapangan, step gabungan Sew + QC + Buang Benang dipecah menjadi dua step berurutan:
1. **Sew+QC** (step lama, di-rename, divisi tetap)
2. **Buang Benang** (step baru, `requires_bundle = 1`, **divisi baru** `BUANG_BENANG` dengan station sendiri)

Keputusan transisi: **backfill** — semua artikel berjalan ikut alur baru, bundle yang sudah lewat titik itu diberi log migrasi supaya rantai serah-terima, kuota qty, WIP report, dan kelayakan packing tetap konsisten.

Ini **murni migrasi data**. Tidak ada perubahan kode C# maupun stored procedure — steps dan divisi sepenuhnya data-driven. Hasil kerja prompt ini: **satu file `sql/migration_33_split_buang_benang.sql`** berisi seluruh script di bawah, siap dijalankan manual.

Station untuk divisi baru TIDAK dibuat di script — Ivander membuatnya via UI Station Manage setelah divisi ter-seed.

## Prasyarat

- Dijalankan setelah semua prompt yang menyentuh workflow/log (12b–17, 25, 26) selesai.
- **Backup database sebelum menjalankan script migrasi.**
- Script harus bisa dijalankan ulang dengan aman bila gagal di tengah (idempotent seperlunya / seluruh mutasi dalam satu transaksi).

## Struktur script (satu file, section berurutan)

### Section 0 — Variabel & verifikasi awal (dijalankan/direview dulu, read-only)

```sql
DECLARE @OldStepName   VARCHAR(150) = 'Sew+QC+Buang Benang'; -- SESUAIKAN dengan nama step aktual di DB
DECLARE @NewOldName    VARCHAR(150) = 'Sew+QC';
DECLARE @NewStepName   VARCHAR(150) = 'Buang Benang';
DECLARE @NewDivCode    VARCHAR(30)  = 'BUANG_BENANG';
DECLARE @NewDivName    VARCHAR(150) = 'Buang Benang';
DECLARE @MigrationUser INT          = <admin user id>; -- untuk created_by/updated_by
```

Sertakan query verifikasi awal yang WAJIB direview sebelum lanjut:
1. Daftar `DISTINCT step_name` di `article_workflows` hidup + jumlah artikel — untuk memastikan `@OldStepName` cocok persis (kalau nama step bervariasi antar artikel, migrasi pakai daftar nama atau match per division, konfirmasi dulu ke Ivander sebelum eksekusi).
2. Daftar artikel yang step lamanya adalah **step terakhir** (`sort_order` = MAX artikel) — kelompok ini punya perlakuan khusus (Section 5).
3. Snapshot stock/WIP sebelum migrasi (pakai SP stock Prompt 25 & `SIS_Report_BundleWip`) untuk dibandingkan sesudah.

### Section 1 — Seed divisi baru

Insert ke `divisions` (code `@NewDivCode`, nama `@NewDivName`) hanya bila belum ada yang hidup. Ambil `@NewDivisionId`.

### Section 2 — Update workflow template

Untuk setiap `workflow_template_steps` hidup dengan `step_name = @OldStepName`:
1. Rename ke `@NewOldName`.
2. Geser `sort_order` semua step hidup template itu yang `sort_order` > step tsb sebanyak +1.
3. Insert step baru: `@NewStepName`, `division_id = @NewDivisionId`, `sort_order` = step lama + 1, `requires_bundle = 1`.

### Section 3 — Update workflow artikel

Sama seperti Section 2, tapi pada `article_workflows` per artikel hidup:
1. Rename step lama → `@NewOldName`.
2. Resequence: `sort_order` step hidup di atasnya +1 (per artikel).
3. Insert step Buang Benang (`workflow_template_id = NULL`, `requires_bundle = 1`, `is_bundling = 0`, `created_by = @MigrationUser`).

Jangan sentuh step `is_bundling = 1` selain terkena geser sort_order bila posisinya di atas (tidak mungkin — step Bundling selalu sebelum step ber-bundle pertama, tapi tetap pastikan resequence tidak merusak posisinya).

### Section 4 — Backfill log (bundle non-step-terakhir)

Prinsip: hasil step gabungan **sudah termasuk** pekerjaan buang benang. Maka SEMUA baris log hidup step lama diperlakukan seragam — pekerjaan Buang Benang dianggap sudah selesai, dan **tidak ada bundle lama yang dialihkan masuk ke station Buang Benang**. Station baru hanya dipakai bundle yang menyelesaikan Sew+QC setelah migrasi.

Untuk setiap **baris** log hidup di step lama (per baris, bukan per bundle — sadar multi-baris susulan Prompt 14b), pada artikel yang step lamanya BUKAN step terakhir:

1. **Insert baris baru di step Buang Benang** (menyalin "sisi keluar" baris lama): `bundle_id` sama, `division_id = @NewDivisionId`, `qty_ok` = `qty_ok` baris lama, semua reject 0 (reject tetap tercatat di baris Sew+QC), `target_division_id` = `target_division_id` LAMA, `received_at` / `received_by_resource_id` disalin apa adanya — **NULL tetap NULL** (masih menunggu diterima divisi tujuan lama, yang menerima nanti divisi tsb, asal serah tampil dari Buang Benang), `remark = 'Migrasi: pemisahan step Buang Benang'`, `created_by = @MigrationUser`.
2. **Update baris lama** (jadi "sisi masuk" ke Buang Benang): `target_division_id = @NewDivisionId`; bila `received_at` NULL → isi otomatis `received_at = created_at` baris itu (serah & terima dianggap sesaat, karena pekerjaannya dulu satu step), `received_remark = 'Otomatis: migrasi pemisahan step'`; bila sudah terisi, biarkan.

Catatan: log memang immutable by design — pengecualian sadar satu kali untuk migrasi ini, `updated_by = @MigrationUser`.

### Section 5 — Backfill log (artikel yang step lamanya = step terakhir)

**Periksa dulu konvensi aktual step terakhir** di `SIS_WorkflowLog_Manage` / data (bagaimana `target_division_id` dan `received_at` diisi saat COMPLETE step terakhir — kemungkinan target NULL). Lalu prinsip Section 4 tetap berlaku:
- (a) Insert baris Buang Benang meniru konvensi step terakhir (target NULL dst.), qty mirror, remark migrasi — Buang Benang jadi step terakhir baru yang tercatat selesai.
- (b) UPDATE baris lama → `target_division_id = @NewDivisionId`; `received_at = created_at` baris itu + `received_remark = 'Otomatis: migrasi pemisahan step'` bila konvensi lama membiarkannya kosong — agar tidak muncul sebagai "menunggu diterima".
- Ini menjaga bundle yang **sudah dipacking** (Prompt 25 — last step per artikel) tetap terhitung selesai di step terakhir baru.

### Section 6 — Verifikasi akhir (read-only)

1. Tidak ada artikel hidup dengan step bernama `@OldStepName` tersisa.
2. `sort_order` per artikel unik & berurutan tanpa lubang.
3. Jumlah baris backfill Buang Benang = jumlah SEMUA baris hidup step lama (1:1, cetak angka keduanya).
4. Tidak ada baris hidup step Sew+QC dengan `received_at IS NULL` (semua sudah auto-received oleh Buang Benang).
5. Tidak ada baris log hidup dengan `target_division_id` menunjuk divisi yang bukan step berikutnya bundle-nya (query sanity rantai).
6. Snapshot stock/WIP sesudah — bandingkan dengan Section 0: stock packing dan posisi semua bundle TIDAK boleh berubah; baris yang tadinya pending dari step gabungan kini tampil pending dari Buang Benang menuju divisi tujuan yang sama.

## Aturan tetap berlaku

Filter `deleted_at IS NULL` di semua query, seluruh mutasi Section 2–5 dalam SATU transaksi (BEGIN TRAN / COMMIT, ROLLBACK on error), tidak ada perubahan struktur tabel, tidak ada perubahan kode aplikasi.

Setelah selesai: daftar file yang dibuat + ringkasan angka yang harus dicek Ivander di Section 0 dan 6, plus pengingat: (1) backup DB dulu, (2) buat station "Buang Benang" via UI setelah migrasi, (3) jalankan saat tidak ada input station berlangsung.

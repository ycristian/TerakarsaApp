# Prompt 17 — Step Bundling: Entitas Penerima Hasil Cutting & Pembuat Bundle

## Konteks

Saat ini ada "lompatan entitas" antara step non-bundle (Cutting) dan step ber-bundle pertama (Sewing): log cutting menggantung (`received_at` tidak pernah terisi), dan pembuatan bundle tidak tercatat sebagai kegiatan workflow. Solusi yang disepakati: **Bundling menjadi step workflow implisit** — disisipkan otomatis oleh sistem, tidak dikelola user di template maupun editor step.

Konsep:
1. Divisi baru **Bundling** (master `divisions`, seed).
2. Kolom baru `is_bundling bit not null default 0` di `article_workflows` (TIDAK di `workflow_template_steps` — template tidak menyimpan step ini).
3. Saat APPLY template ke artikel, sistem otomatis menyisipkan satu step `Bundling` (`is_bundling = 1`, `requires_bundle = 1`, divisi Bundling) tepat di antara step non-bundle terakhir dan step ber-bundle pertama.
4. Saat bundle dibuat (`SIS_Bundle_Manage` CREATE), dalam transaksi yang sama:
   - Insert baris `article_workflow_logs` untuk step Bundling: pembuat bundle = pihak yang menerima hasil cutting dan mengemas. `qty_ok` = qty bundle, `received_at` = NULL (menunggu diterima divisi berikutnya, mis. Sewing).
   - **Auto-receive** semua baris log non-bundle artikel itu yang masih `received_at IS NULL` (tanggung jawab akurasi qty tetap di admin non-bundle; sistem tidak memblokir).
5. Rantai per-bundle yang sudah ada bekerja otomatis: Sewing scan QR → RECEIVE baris Bundling → baru bisa CREATE baris Sewing. Step ber-bundle pertama TIDAK lagi bebas prasyarat.
6. Step Bundling tersembunyi dari station dan dari pemilihan step mana pun; baris lognya hanya lahir lewat aksi pembuatan bundle.

Data DB masih data uji — TIDAK ada backfill/migrasi data lama. Setelah eksekusi, data uji akan di-reset manual.

## 1. Skema & Seed

### a. Edit `sql/create_tables_tmos_final.sql`
- Tabel `article_workflows`: tambah kolom setelah `requires_bundle`:
  ```sql
   is_bundling bit not null default 0,        -- step Bundling implisit (disisipkan sistem saat APPLY, bukan dari template)
  ```
- Tambah komentar di atas tabel `article_workflows` dan `article_workflow_logs` yang menjelaskan konsep step Bundling (entitas penerima cutting + pencatat pembuatan bundle; log hanya dibuat via SIS_Bundle_Manage).

### b. Buat `sql/alter_17_bundling_step.sql` (dijalankan manual)
```sql
-- Prompt 17: step Bundling implisit
ALTER TABLE article_workflows
  ADD is_bundling bit NOT NULL CONSTRAINT DF_aw_is_bundling DEFAULT 0;
GO
```

### c. Buat `sql/seed_division_bundling.sql` (dijalankan manual, idempotent)
Insert divisi `division_code = 'BUNDLING'`, `division_name = 'Bundling'` bila belum ada (`IF NOT EXISTS` berdasarkan code, `deleted_at IS NULL`), `created_by = 1`.

## 2. SIS_ArticleWorkflow_Manage (`sql/sp_ArticleWorkflow_Manage.sql`)

### APPLY
Setelah menyalin steps dari template, bila template punya minimal satu step `requires_bundle = 1`:
1. Cari `@BundlingDivisionId` dari `divisions` (code 'BUNDLING', hidup). Kalau tidak ada → RAISERROR jelas ("Divisi Bundling belum di-seed.").
2. Geser `sort_order` semua step ber-bundle hasil salinan +1.
3. Insert step Bundling: `step_name = 'Bundling'`, `division_id = @BundlingDivisionId`, `sort_order` = sort_order step ber-bundle pertama sebelum digeser, `requires_bundle = 1`, `is_bundling = 1`, `workflow_template_id = @WorkflowTemplateId`.

Kalau template tidak punya step ber-bundle sama sekali → tidak menyisipkan apa pun.

### SAVE
- `@Steps` dari UI TIDAK memuat baris `is_bundling = 1` (UI menampilkannya read-only, lihat bagian 5). SP tidak boleh menganggap step Bundling "dihapus user" — kecualikan baris `is_bundling = 1` dari pengecekan penghapusan dan dari operasi update/insert/delete.
- Setelah update/insert/delete step user selesai (masih dalam transaksi), **resequence otomatis** step Bundling: posisinya harus tepat sebelum step hidup `requires_bundle = 1 AND is_bundling = 0` dengan sort_order terkecil. Cara paling aman: renumber ulang seluruh step hidup artikel secara berurutan dengan Bundling disisipkan di posisi itu.
- Kalau hasil SAVE tidak menyisakan step ber-bundle (user mengubah semuanya jadi non-bundle) padahal step Bundling punya log hidup → tolak dengan pesan jelas. Kalau tidak punya log → soft delete step Bundling ikut.
- Kalau hasil SAVE punya step ber-bundle tapi artikel belum punya step Bundling hidup (kasus artikel lama / step ber-bundle baru ditambahkan) → sisipkan step Bundling seperti logika APPLY.
- Validasi lama "step tanpa bundle harus sebelum semua step ber-bundle" tetap berlaku.

## 3. SIS_Bundle_Manage (`sql/sp_Bundle_Manage.sql`)

Parameter baru: `@BundlingResourceId INT = NULL` — pelaksana bundling (opsional). Bila diisi: harus resource hidup + `is_active` milik divisi Bundling, kalau tidak → RAISERROR.

### CREATE (dalam transaksi & applock yang sudah ada)
Setelah insert `bundles` dan `print_jobs`:
1. Cari step Bundling artikel: `article_workflows` hidup, `article_id = @ArticleId`, `is_bundling = 1`. Kalau tidak ada → RAISERROR ("Workflow artikel belum memiliki step Bundling. Terapkan ulang/simpan workflow artikel terlebih dahulu.") dan ROLLBACK.
2. Hitung `target_division_id` = divisi step hidup berikutnya (sort_order tepat di atas step Bundling) — pola sama dengan `SIS_WorkflowLog_Manage`.
3. Insert `article_workflow_logs`: step Bundling, `bundle_id` = bundle baru, `article_size_id = NULL`, `division_id` = divisi Bundling, `resource_id = @BundlingResourceId`, `qty_ok = @Qty`, qty reject semua 0, `received_at = NULL`, `created_by = @UserId`.
4. Auto-receive log non-bundle pending:
   ```sql
   UPDATE awl SET received_at = SYSDATETIME(),
                  received_by_resource_id = @BundlingResourceId,
                  received_remark = 'Otomatis: pembuatan bundle'
   FROM article_workflow_logs awl
   INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
   WHERE aw.article_id = @ArticleId AND aw.requires_bundle = 0
     AND aw.deleted_at IS NULL AND awl.deleted_at IS NULL
     AND awl.received_at IS NULL AND awl.target_division_id IS NOT NULL;
   ```

### UPDATE — sekaligus PERBAIKAN BUG
Pengecekan lama `[status] = 'COMPLETED'` sudah invalid (kolom `status` dihapus di Prompt 12b) — aksi ini sekarang error saat runtime. Ganti aturannya:
- Tolak bila bundle punya log hidup di step `is_bundling = 0` (sudah dikerjakan station), ATAU log Bundling-nya sudah `received_at IS NOT NULL` (sudah diserah-terimakan). Pesan: "Bundle sudah diproses, tidak bisa diubah."
- Bila lolos: update `bundles` seperti sekarang, DAN sinkronkan `qty_ok` log Bundling = `@Qty`. Bila `@BundlingResourceId` dikirim, update juga `resource_id` log Bundling.

### DELETE — perbaikan bug yang sama
- Tolak dengan kondisi identik UPDATE di atas.
- Bila lolos: soft delete bundle + soft delete log Bundling-nya (`delete_reason = 'Bundle dihapus'`, `deleted_by = @UserId`).

## 4. SIS_WorkflowLog_Manage (`sql/sp_WorkflowLog_Manage.sql`)

### CREATE
- Tolak bila step tujuan `is_bundling = 1`: "Log step Bundling hanya dibuat lewat pembuatan bundle."
- Hapus perlakuan khusus "step ber-bundle pertama tanpa prasyarat". Semua step ber-bundle `is_bundling = 0` memakai aturan generik yang sudah ada: baris step ber-bundle tepat sebelumnya (termasuk step Bundling) harus ada, `received_at` terisi, `target_division_id` = divisi step ini.
- Validasi "bundle ditugaskan ke line lain" (`bundles.resource_id`) dipindah: berlaku pada step ber-bundle pertama yang `is_bundling = 0` (MIN sort_order di antara `requires_bundle = 1 AND is_bundling = 0`).
- Kuota qty (Prompt 14/14b): tidak perlu cabang khusus `bundles.qty` lagi — qty masuk step station pertama otomatis = SUM `qty_ok` baris step Bundling (yang nilainya memang qty bundle). Hapus cabang `@SortOrder = @FirstBundleSort → bundles.qty` bila jadi redundan; pastikan definisi "step sebelumnya" konsisten.

### UPDATE / RECEIVE / UNRECEIVE / DELETE
Berlaku generik ke baris Bundling tanpa perubahan (RECEIVE oleh divisi tujuan via station sudah benar; UPDATE baris Bundling praktis hanya lewat `SIS_Bundle_Manage` UPDATE karena `@ActingDivisionId` station tidak akan sama dengan divisi Bundling — tidak perlu blok tambahan). DELETE baris Bundling langsung dari log tetap boleh untuk Admin, aturan lama.

## 5. Select SP, API, dan Client

### SQL Select
- `sp_ArticleWorkflow_Select.sql`: kembalikan kolom `is_bundling` di daftar step artikel.
- Periksa `sp_Bundle_Select.sql` (`SIS_Article_BundleSummary` dkk.): flag/logika yang mengacu "step ber-bundle pertama" perlu disesuaikan bila maknanya = step station pertama (`is_bundling = 0`). Banner "cutting belum dikonfirmasi diterima" boleh tetap membaca step Bundling (karena Bundling-lah penerima cutting sekarang) — sesuaikan komentarnya.
- `sp_Bundle_ScanInfo.sql`, `sp_WorkflowLog_Select.sql`, `sp_Report_Bundle.sql`: tidak ada perubahan logika — baris/step Bundling MEMANG tampil di riwayat, pending receive, dan laporan (itu tujuannya: kontinuitas status). Cukup verifikasi tampil wajar.

### API & Shared
- `BundleModels.cs`: tambah `BundlingResourceId` (nullable) di request create & update bundle.
- `BundleService.cs` + `BundleController.cs`: teruskan `@BundlingResourceId`.
- `ArticleWorkflowModels.cs` + `ArticleWorkflowService.cs`: teruskan `is_bundling`; payload SAVE dari client tidak memuat baris `is_bundling = 1`.

### Client
- `BundleManager.razor`: dropdown "Pelaksana Bundling (opsional)" — resource hidup divisi Bundling (pakai endpoint resource per divisi yang sudah ada bila tersedia; kalau belum, tambah). Dikirim saat create & edit bundle.
- `ArticleEdit.razor` (editor step workflow): baris step Bundling tampil **read-only** (badge "Bundling — otomatis"), tanpa tombol hapus/edit, tidak ikut drag/reorder, dan TIDAK dikirim di payload SAVE.
- UI bahasa Indonesia, pola halaman/CloseButton mengikuti konvensi yang ada.

## Aturan tetap berlaku
Soft delete, filter `deleted_at IS NULL`, prefix SP `SIS_`, pola `@Action` untuk mutasi, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan
- Jangan tambah kolom `is_bundling` di `workflow_template_steps` — template tidak mengenal step ini.
- Jangan buat backfill/migrasi data bundle atau artikel lama — data uji akan di-reset manual.
- Jangan buat station/token untuk divisi Bundling.
- Jangan ubah format serial, `bundle_no`, atau payload label.
- Jangan ubah logika Prompt 14/14b/15 di luar penyesuaian yang disebut di bagian 4.

## Verifikasi
1. `dotnet build` sukses.
2. Skenario manual (setelah jalankan `alter_17` + `seed_division_bundling` + reset data uji):
   - Apply template → step Bundling muncul otomatis di antara Cutting dan Sewing, read-only di editor.
   - Input "Hasil Cutting" (WORKFLOW_INPUT) → buat bundle → log cutting pending otomatis ter-receive; log Bundling tercatat dengan pelaksana & qty bundle, status "menunggu diterima Sewing".
   - Station Sewing scan QR → RECEIVE baris Bundling → CREATE log Sewing sukses; CREATE Sewing tanpa RECEIVE ditolak.
   - Edit/hapus bundle sebelum diterima Sewing → sukses & qty log Bundling ikut berubah / log ikut terhapus. Setelah diterima → ditolak.
   - Laporan bundle menampilkan tahap Bundling.
3. Di akhir: daftar file yang diubah/dibuat + daftar script SQL yang harus dijalankan manual.

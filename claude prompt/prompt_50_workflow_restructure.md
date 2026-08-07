# Prompt 50 — Restructure Workflow Artikel Setelah Ada Log

Menambah kemampuan **menyisipkan step baru** dan **menonaktifkan step** pada workflow artikel yang sudah berjalan (sudah punya `article_workflow_logs`), tanpa memutus rantai handover dan tanpa menghilangkan riwayat produksi.

Berlaku untuk **kedua jalur**: step ber-bundle (rantai per `bundle_id`) dan step non-bundle (rantai per `article_size_id`).

Guard `SIS_ArticleWorkflow_Manage` SAVE yang menolak penghapusan step ber-log **tetap dipertahankan apa adanya**. Prompt ini menambah jalur terpisah, bukan melonggarkan yang lama.

---

## 0. Konteks masalah

`article_workflow_logs.target_division_id` **ditulis saat baris dibuat**, tidak dihitung ulang saat dibaca. Validasi CREATE di step S memeriksa apakah log di step sebelumnya sudah `received_at` terisi **dan** `target_division_id`-nya = divisi S. Begitu struktur step bergeser, dua nilai itu tidak lagi cocok dan bundle nyangkut.

Untuk setiap perubahan struktur, unit kerja (bundle atau size) terbagi tiga kategori berdasarkan **status log di step tepat sebelum titik perubahan**:

| Kategori | Kondisi log step sebelumnya | Tindakan |
|---|---|---|
| A | Belum ada log sama sekali | Tidak perlu apa-apa — akan lewat struktur baru secara normal |
| B | Ada, `received_at IS NULL` | **Redirect** `target_division_id` |
| C | Ada, `received_at IS NOT NULL` | **Backfill** log di step baru |

Pembedanya **hanya status `received_at`** — bukan "sudah punya log di step berikutnya atau belum". Kalau memakai pembeda yang salah, unit yang sudah diterima divisi tujuan tapi belum submit akan jatuh di celah antara dua aturan dan pasti nyangkut.

---

## 1. Perubahan skema

File: `sql/prompt_50_workflow_restructure.sql` (manual, idempoten, bungkus setiap ALTER dengan `IF NOT EXISTS (SELECT 1 FROM sys.columns ...)`).

**`article_workflows`:**

| Kolom | Tipe | Keterangan |
|---|---|---|
| `inactive_at` | `DATETIME NULL` | Diisi = step berhenti jadi jalur untuk unit baru |
| `inactive_by` | `INT NULL` | User yang menonaktifkan |

**`article_workflow_logs`:**

| Kolom | Tipe | Keterangan |
|---|---|---|
| `target_division_id_original` | `INT NULL` | Nilai `target_division_id` sebelum redirect pertama. Hanya diisi kalau masih NULL — redirect kedua tidak boleh menimpanya |

Baris step nonaktif tetap `deleted_at IS NULL`. Ini disengaja: semua SP baca memfilter `deleted_at IS NULL` dengan INNER JOIN, sehingga soft delete akan membuat log yang menempel di step itu **hilang diam-diam** dari laporan, timeline, dan WIP tanpa error apa pun.

---

## 2. SP baru: `SIS_ArticleWorkflow_Restructure`

File baru: `sql/sp_ArticleWorkflow_Restructure.sql`. Jangan menumpang di `SIS_ArticleWorkflow_Manage` — pola isolasi seperti `SIS_SuperAdmin_Manage`.

### Signature

```
@Action            VARCHAR(20),   -- 'PREVIEW_INSERT' | 'INSERT_STEP' | 'PREVIEW_DEACTIVATE' | 'DEACTIVATE_STEP'
@ArticleId         INT,
@StepName          VARCHAR(150) = NULL,
@DivisionId        INT = NULL,
@RequiresBundle    BIT = NULL,
@AutoReceive       BIT = 0,       -- nilai auto_receive step baru (lihat Prompt 34/40)
@AfterWorkflowId   INT = NULL,    -- sisip TEPAT SETELAH step ini. NULL = jadi step pertama
@ArticleWorkflowId INT = NULL,    -- DEACTIVATE_STEP
@Backfill          BIT = 1,
@UserId            INT
```

Seluruh action menulis di dalam satu transaksi + `sp_getapplock` per artikel. **Gunakan nama resource applock yang sama persis** dengan yang dipakai `SIS_WorkflowLog_Manage` dan `SIS_Bundle_Manage`, supaya station device tidak bisa submit di tengah restructure.

### PREVIEW_INSERT / PREVIEW_DEACTIVATE

Dry-run, tidak menulis apa pun. Result set 1 (ringkasan):

| Kolom | Isi |
|---|---|
| `PendingLogsToRedirect` | Kategori B — log yang `target_division_id`-nya diubah |
| `ReceivedLogsToRedirect` | Hanya DEACTIVATE — log received yang diubah (lihat §2.3) |
| `BackfillLogsToCreate` | Kategori C — jumlah **baris log** yang dibuat, bukan jumlah bundle |
| `ForcedBackfillCount` | Bagian dari backfill yang tetap dijalankan walau `@Backfill = 0` |
| `StepsResequenced` | Jumlah step yang `sort_order`-nya bergeser |
| `WarningMessage` | Peringatan, atau NULL |

Result set 2: daftar unit terdampak (`bundle_id`, `serial`, `bundle_no`, atau `article_size_id` untuk jalur non-bundle) beserta kategori A/B/C dan posisi step terakhirnya.

Preview bisa basi kalau ada submit masuk di sela preview dan eksekusi. Angka final yang dikembalikan action eksekusi adalah yang berlaku.

### 2.1 INSERT_STEP

**Validasi awal**
- Artikel ada dan punya workflow hidup; `@DivisionId` divisi hidup.
- `@AfterWorkflowId` (kalau diisi) milik artikel ini, `deleted_at IS NULL`, `inactive_at IS NULL`.
- Tolak menyisipkan step dengan `is_bundling = 1` — step Bundling dikelola otomatis.
- Tolak kalau hasil sisipan melanggar aturan **semua step non-bundle harus mendahului semua step ber-bundle**. Artinya: step non-bundle hanya boleh disisipkan sebelum step ber-bundle pertama, step ber-bundle hanya boleh disisipkan setelah step non-bundle terakhir.

**Langkah**

1. Geser `sort_order` +1 untuk semua step hidup yang `sort_order`-nya ≥ posisi target, **lalu** insert step baru. Isi `auto_receive` dari `@AutoReceive`.

2. **Resequence** seluruh step hidup artikel secara berurutan dari 1, dan reposisi step `is_bundling = 1` supaya tetap tepat sebelum step hidup-aktif ber-bundle pertama (`requires_bundle = 1 AND is_bundling = 0 AND inactive_at IS NULL`, `sort_order` terkecil).

3. **Redirect kategori B.** Untuk setiap log hidup di step tepat sebelum titik sisip dengan `received_at IS NULL`: set `target_division_id` = divisi step baru; isi `target_division_id_original` kalau masih NULL; update `updated_at` / `updated_by`.

4. **Backfill kategori C.** Untuk **setiap baris log** hidup di step tepat sebelum titik sisip dengan `received_at IS NOT NULL` — bukan satu baris per bundle, karena log susulan membuat satu unit bisa punya beberapa baris di satu step, dan qty tidak akan cocok kalau digabung — buat satu baris `article_workflow_logs`:

   | Kolom | Nilai |
   |---|---|
   | `article_workflow_id` | Step baru |
   | `bundle_id`, `article_size_id` | Salin dari log sumber |
   | `division_id` | Divisi step baru |
   | `resource_id` | Salin dari log sumber |
   | `qty_ok`, `qty_reject_print`, `qty_reject_fabric`, `qty_reject_sewing`, `qty_reject_rework`, `qty_lost` | **Salin apa adanya** |
   | `log_type` | Salin dari log sumber |
   | `target_division_id` | Divisi step aktif berikutnya setelah step baru; NULL kalau step baru jadi step terakhir |
   | `created_at`, `received_at` | `received_at` log sumber (timestamp asli, **bukan** `GETDATE()`) |
   | `received_by` | Salin dari log sumber |
   | `remark` | `'[Backfill Prompt 50]'` |
   | `created_by`, `updated_by` | `@UserId` |

5. **Backfill paksa.** Kalau `@Backfill = 0`, backfill tetap **wajib dijalankan** untuk unit kategori C yang belum punya log di step aktif setelah titik sisip — unit ini fisiknya sudah di tangan divisi tujuan dan akan pasti nyangkut tanpa backfill. Hitung jumlahnya di `ForcedBackfillCount`. `@Backfill = 0` hanya melewati unit yang sudah punya log di step setelahnya.

### 2.2 INSERT_STEP jalur non-bundle

Logika identik, hanya unitnya berbeda: rantai ditelusuri per `article_size_id` dengan `bundle_id IS NULL`, bukan per `bundle_id`. Kategori A/B/C, redirect, dan backfill diberlakukan sama persis pada baris-baris tersebut.

Jangan menulis dua blok kode terpisah kalau bisa dihindari — kelompokkan dengan kunci `COALESCE(bundle_id, -article_size_id)` atau pendekatan setara, supaya perilaku kedua jalur dijamin identik dan tidak menyimpang saat salah satunya diubah kelak.

### 2.3 DEACTIVATE_STEP

**Validasi**
- Step milik artikel, `deleted_at IS NULL`, `inactive_at IS NULL`, `is_bundling = 0`.
- Tolak kalau tidak menyisakan step hidup-aktif sama sekali.
- Tolak kalau step ini punya log **pending** (`received_at IS NULL`) — ada unit sedang menunggu diterima di step ini. Pesan: selesaikan atau koreksi dulu lewat Super Admin.

**Langkah**

1. Set `inactive_at = GETDATE()`, `inactive_by = @UserId`.

2. Resequence seluruh step hidup-aktif, termasuk reposisi step Bundling.

3. **Redirect.** Untuk log hidup yang `target_division_id`-nya = divisi step yang dinonaktifkan, arahkan ke divisi step aktif berikutnya (NULL kalau tidak ada step aktif setelahnya). Ini berlaku untuk log pending **maupun** log yang sudah received.

   **Batasi cakupannya:** hanya unit yang **masih berjalan**, yaitu belum punya log di step aktif mana pun setelah step yang dinonaktifkan. Unit yang workflow-nya sudah tuntas **tidak boleh disentuh** — redirect tidak memberi manfaat apa pun di sana dan hanya merusak riwayat.

   Setiap baris yang di-redirect wajib mengisi `target_division_id_original` kalau kolomnya masih NULL. Hitung terpisah di `PendingLogsToRedirect` dan `ReceivedLogsToRedirect` supaya admin melihat berapa baris riwayat yang berubah sebelum menekan Jalankan.

---

## 3. SP & service lama yang wajib disesuaikan

### Harus mulai memfilter `inactive_at IS NULL`

Semua yang menghitung **step berikutnya / posisi step**. Tanpa ini, unit baru diarahkan ke step mati:

- `sql/sp_WorkflowLog_Manage.sql` — perhitungan `target_division_id` dan validasi rantai step sebelumnya
- `sql/sp_Bundle_Manage.sql` — CREATE: pencarian step Bundling dan divisi tujuan
- `sql/sp_Bundle_ScanInfo.sql` — `@FirstBundleSort`, `@MaxArticleSort`, `@AllowedAction`, `@NextDivisionId`
- `sql/sp_Station_Operations.sql` — `SIS_Station_PendingHandover` dan SP station lain yang menelusuri urutan step
- `TerakarsaApp.API/Services/ArticleWorkflowService.cs` — `GetNonBundleStepsAsync`

### Tidak boleh memfilter `inactive_at`

Riwayat harus tetap tampil:

- Timeline di `SIS_Bundle_ScanInfo`
- `SIS_Report_ProduksiAgg` / `SIS_Report_ProduksiDetail`
- `SIS_Report_DivisionWip` / `SIS_Report_DivisionWipBundles`
- `SIS_Report_ActivityLog` (Prompt 47)

Telusuri **seluruh** referensi `article_workflows` di repo dan klasifikasikan ke salah satu dari dua kelompok. Kalau ada yang ambigu, hentikan dan tanyakan — jangan menebak.

### `SIS_ArticleWorkflow_Manage` SAVE

Kecualikan baris `inactive_at IS NOT NULL` dari pengecekan insert, update, dan delete — perlakuan persis sama seperti baris `is_bundling = 1` sekarang. Tanpa ini, step nonaktif dianggap "dihapus user" begitu admin menekan Simpan, lalu tertolak guard log.

### `SIS_ArticleWorkflow_ListByArticle`

Tambah filter `aw.inactive_at IS NULL` — step nonaktif disembunyikan sepenuhnya dari grid edit workflow.

---

## 4. API

Di controller yang menangani workflow artikel, semua memerlukan privilege module `PROJECT`:

- `POST api/article-workflow/{articleId}/restructure/preview-insert`
- `POST api/article-workflow/{articleId}/restructure/insert-step`
- `POST api/article-workflow/{articleId}/restructure/preview-deactivate`
- `POST api/article-workflow/{articleId}/restructure/deactivate-step`

DTO mengikuti parameter dan result set SP. Tangani `SqlException` dan kembalikan pesan RAISERROR apa adanya, pola sama dengan `ApplyAsync` / `SaveAsync`.

---

## 5. UI — section Workflow di halaman edit Artikel

Tampil hanya kalau artikel sudah punya workflow hidup. Bahasa Indonesia.

**Tombol "Sisipkan Step"** — dialog berisi: nama step, dropdown divisi, checkbox "Butuh bundle", checkbox "Auto-receive", dropdown "Sisipkan setelah" (step aktif + opsi "Jadi step pertama"), checkbox **"Backfill log untuk unit yang sudah lewat" tercentang default**.

**Tombol "Nonaktifkan"** per baris step — konfirmasi dua langkah. Sertakan kalimat bahwa riwayat produksi step ini tetap tersimpan dan tetap muncul di laporan, hanya berhenti jadi jalur untuk unit baru.

Untuk keduanya: tombol "Cek Dampak" memanggil preview, tampilkan ringkasan angka + daftar unit terdampak. Tombol "Jalankan" **baru aktif setelah preview dijalankan** — wajib, bukan opsional.

Kalau `ReceivedLogsToRedirect > 0`, tampilkan peringatan menonjol: riwayat serahan pada log tersebut akan berubah dan bundle lama akan menampilkan divisi tujuan yang berbeda dari kenyataan saat itu.

---

## 6. Batasan — yang TIDAK boleh dikerjakan

- Jangan melonggarkan guard `SIS_ArticleWorkflow_Manage` SAVE yang menolak penghapusan step ber-log.
- Jangan membuat fitur mengaktifkan kembali step nonaktif. Urutan sudah bergeser dan unit sudah lewat; reaktivasi menimbulkan lubang rantai yang lebih sulit ditelusuri daripada membuat step baru.
- Jangan menyentuh `workflow_template_steps` atau template mana pun.
- Jangan soft delete step yang punya log, dalam kondisi apa pun.
- Jangan menimpa `target_division_id_original` yang sudah terisi.
- Jangan menyentuh log unit yang workflow-nya sudah tuntas.
- Jangan menjalankan script SQL otomatis. Semua migration manual.

---

## 7. Urutan deploy

1. `sql/prompt_50_workflow_restructure.sql` — tambah kolom.
2. `sql/sp_ArticleWorkflow_Restructure.sql` — SP baru.
3. Jalankan ulang seluruh SP lama yang diubah di §3.
4. Deploy API + Blazor.

Langkah 3 harus setelah 1, karena SP lama mereferensikan `inactive_at`.

---

## 8. Verifikasi

Siapkan satu artikel uji dengan bundle di empat posisi berbeda: belum sampai titik sisip (A), log pending (B), sudah received tapi belum submit (C1), sudah submit di step berikutnya (C2).

1. Sisip step di tengah, backfill menyala. **Keempatnya harus bisa lanjut** lewat scan station tanpa error. C1 adalah kasus yang paling sering luput — uji khusus.
2. Ulangi dengan backfill dimatikan. C1 harus **tetap** dapat log (backfill paksa) dan tetap bisa lanjut; hanya C2 yang bolong.
3. Bundle dengan log susulan di step sebelum titik sisip: jumlah baris backfill harus sama dengan jumlah baris log sumber, dan total qty harus cocok.
4. Sisip step non-bundle di antara dua step non-bundle ber-log — jalur per size harus berperilaku identik dengan jalur bundle.
5. Nonaktifkan step di tengah. Unit yang masih berjalan harus bisa lanjut; cek `target_division_id_original` terisi pada baris yang di-redirect.
6. Cek bundle yang workflow-nya sudah tuntas sebelum deaktivasi — `target_division_id`-nya **tidak boleh berubah**.
7. Timeline scan QR bundle lama: step nonaktif harus masih muncul beserta qty-nya.
8. Laporan Produksi, WIP Dashboard, Activity Log: angka historis step nonaktif tidak boleh hilang.
9. Buka edit workflow, tekan Simpan tanpa mengubah apa pun. Harus sukses dan step nonaktif tidak ikut terhapus.
10. Jalankan script migration dua kali — tidak boleh error.

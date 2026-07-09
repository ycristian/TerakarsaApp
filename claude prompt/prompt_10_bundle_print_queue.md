# Prompt 10 — Bundle & Antrian Cetak Label

## Konteks

Supervisor (UI login, privilege PROJECT) membuat bundle secara MANUAL per baris untuk sebuah artikel, lalu tiap bundle otomatis masuk antrian cetak label QR (`print_jobs`). Pencetakan fisik oleh Windows service dikerjakan di Prompt 11 — prompt ini berhenti di antrian. Alur scan per-bundle di stasiun dikerjakan di Prompt 12.

## 1. Skema SQL

a. Tambahkan tabel baru di `sql/create_tables_tmos_final.sql` (section PRODUKSI):

```sql
CREATE TABLE print_jobs(
 print_job_id int primary key identity(1,1),
 job_type varchar(30) not null,             -- 'BUNDLE_LABEL' (nanti: 'MATERIAL_LABEL')
 ref_id int not null,                       -- bundle_id untuk BUNDLE_LABEL
 payload nvarchar(max) not null,            -- JSON data label; TSPL dirakit oleh print service
 [status] varchar(20) not null default 'PENDING',  -- PENDING/PRINTING/DONE/ERROR
 error_message varchar(500) null,
 retry_count int not null default 0,
 printed_at datetime2 null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
CREATE INDEX IX_print_jobs_status ON print_jobs([status]) WHERE deleted_at IS NULL;
```

b. Buat `sql/alter_10_print_jobs.sql` (idempotent) untuk DB yang sudah ada.

## 2. Stored Procedures

### sp_Bundle_Manage (@Action: CREATE, UPDATE, DELETE)

- **CREATE**: @ArticleId, @ArticleSizeId, @Qty, @ResourceId (nullable), @ResourcePersonName (nullable), @UserId.
  - Validasi: article_size milik article; qty > 0.
  - **Serial digenerate di SP**, format `B{yy}-{nomor urut global 6 digit}` (contoh `B26-000153`), aman dari race condition: pakai `sp_getapplock` atau MAX dengan UPDLOCK/HOLDLOCK dalam transaksi.
  - sort_order = urutan berikutnya dalam size itu.
  - Dalam transaksi yang sama: INSERT `print_jobs` (job_type BUNDLE_LABEL, ref_id = bundle baru, payload JSON berisi: serial, qr_content, project_name, article_name, style, color, size_name, qty). `qr_content` = `{BaseUrl}/b/{serial}` — BaseUrl dibaca dari appsettings.json (key baru `App:PublicBaseUrl`), dirakit di layer API sebelum memanggil SP (SP menerima @QrContent). Kembalikan bundle lengkap + print_job_id.
- **UPDATE**: hanya @Qty, @ResourceId, @ResourcePersonName. Tolak jika bundle sudah punya log hidup di article_workflow_logs. Serial tidak pernah berubah.
- **DELETE**: soft delete. Tolak jika bundle sudah punya log hidup.

### sp_Bundle_ListByArticle

@ArticleId → semua bundle hidup, JOIN size_name, dan status label terakhir dari print_jobs (job hidup terbaru per bundle: status + printed_at). Urut size sort_order, lalu bundle sort_order.

### sp_Bundle_ReprintLabel

@BundleId, @UserId → insert print_jobs baru (payload dirakit ulang dari data terkini). Kembalikan print_job_id.

### sp_Article_BundleSummary

@ArticleId → per size: size_name, qty order, bundle_qty, jumlah bundle, total qty bundle. Plus flag peringatan: apakah step ber-bundle pertama artikel ini (requires_bundle = 1, sort_order terkecil) sudah punya log RECEIVED hidup.

## 3. API

Pola biasa, [Authorize] + RequireModule("PROJECT"):
- GET `api/articles/{articleId}/bundles` (list + summary dalam satu response)
- POST `api/bundles` (CREATE)
- PUT `api/bundles/{id}` (UPDATE)
- DELETE `api/bundles/{id}` (soft delete, tanpa alasan — bukan tabel log)
- POST `api/bundles/{id}/reprint`

## 4. Blazor Client

Halaman baru `/articles/{articleId}/bundles`, dibuka dari tombol **"Kelola Bundle"** di halaman Edit Article. Tanpa menu sidebar baru.

1. **Header**: project, artikel, style, color.
2. **Banner peringatan** (kuning, tidak memblokir) jika flag dari summary menyatakan hasil cutting belum dikonfirmasi Terima: "Hasil cutting belum dikonfirmasi diterima. Bundle tetap bisa dibuat."
3. **Ringkasan per size**: qty order, saran bundle_qty, jumlah bundle, total qty bundle. Highlight kuning jika total qty bundle ≠ qty order (informasi saja, tidak memblokir).
4. **Form tambah bundle**: dropdown size (dari article_sizes), qty (prefill dari bundle_qty size terpilih), penjahit opsional (dropdown resource + input nama orang), tombol Simpan → baris langsung muncul di daftar. Form tetap terbuka untuk input beruntun (size & qty terakhir dipertahankan).
5. **Daftar bundle** dikelompokkan per size: serial, qty, penjahit, badge status label (Menunggu Cetak / Dicetak / Gagal), aksi: Edit (qty/penjahit), Hapus (konfirmasi; tampilkan pesan jelas kalau ditolak karena sudah ada log), **Cetak Ulang**.

## Aturan tetap berlaku

Soft delete, filter deleted_at IS NULL, UserId dari JWT, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan buat Windows service / komunikasi printer / TSPL — Prompt 11. Payload cukup JSON.
- Jangan buat endpoint polling untuk print service — Prompt 11.
- Jangan ubah alur stasiun / halaman `/station` — alur per-bundle di Prompt 12.
- Jangan buat generate bundle otomatis massal — pembuatan manual per baris.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.
# Prompt 7b — Schema Update: Workflow Log Tanpa Bundle (Cutting)

## Konteks

Proses cutting terjadi SEBELUM bundle dibuat (bundle dibuat supervisor setelah cutting, lalu diserahkan ke sewing). Karena itu log workflow untuk step cutting tidak punya bundle. Solusi yang disepakati:

1. `article_workflow_logs.bundle_id` diubah jadi NULLABLE. Log tanpa bundle terhubung ke artikel lewat `article_workflow_id → article_workflows.article_id` (TIDAK menambah kolom `article_id` di tabel log — redundan).
2. Tambah kolom `requires_bundle bit not null default 1` di `workflow_template_steps` DAN di `article_workflows` (karena `article_workflows` adalah salinan snapshot dari template step, flag harus ikut tersalin). Nilai 0 hanya untuk step pra-bundle seperti Cutting.

Ini perubahan skema SQL saja. TIDAK ADA perubahan kode C# — modul workflow belum dibuat (Phase D).

## Tugas

### 1. Edit `sql/create_tables_tmos_final.sql`

a. Di tabel `article_workflow_logs`, ubah:

```sql
 bundle_id int not null
   constraint FK_awl_bundles foreign key references bundles(bundle_id),
```

menjadi:

```sql
 bundle_id int null                          -- NULL = log level artikel (step pra-bundle, mis. Cutting)
   constraint FK_awl_bundles foreign key references bundles(bundle_id),
```

b. Di tabel `workflow_template_steps`, tambahkan kolom setelah `sort_order`:

```sql
 requires_bundle bit not null default 1,     -- 0 = step boleh log tanpa bundle (mis. Cutting)
```

c. Di tabel `article_workflows`, tambahkan kolom setelah `sort_order` (flag ikut tersalin saat copy step dari template):

```sql
 requires_bundle bit not null default 1,     -- salinan dari template step
```

d. Tambahkan komentar di atas tabel `article_workflow_logs` (gabung dengan komentar LOG MURNI yang sudah ada):

```sql
-- bundle_id NULL hanya untuk step dengan requires_bundle = 0 (mis. Cutting).
-- Validasi di sp_WorkflowLog_Manage (Phase D/E):
--   1. requires_bundle = 1 -> bundle_id wajib diisi
--   2. bundle_id diisi -> bundles.article_id harus = article_workflows.article_id
```

### 2. Buat file baru `sql/alter_07b_workflow_bundle_nullable.sql`

Untuk DB yang sudah ada (dijalankan manual):

```sql
-- Prompt 7b: workflow log tanpa bundle untuk step pra-bundle (Cutting)

ALTER TABLE article_workflow_logs ALTER COLUMN bundle_id int NULL;
GO

ALTER TABLE workflow_template_steps
  ADD requires_bundle bit NOT NULL CONSTRAINT DF_wts_requires_bundle DEFAULT 1;
GO

ALTER TABLE article_workflows
  ADD requires_bundle bit NOT NULL CONSTRAINT DF_aw_requires_bundle DEFAULT 1;
GO
```

Catatan: pastikan `ALTER COLUMN bundle_id` tidak menghapus constraint FK_awl_bundles (ALTER COLUMN ke nullable aman, FK tetap ada). Jangan drop/recreate FK.

### 3. Verifikasi

- Jalankan `dotnet build` — harus tetap sukses (tidak ada perubahan C#).
- Pastikan tidak ada file C# yang diubah.
- Di akhir, sebutkan daftar file yang diubah/dibuat dan daftar script SQL yang perlu dijalankan manual.

## Yang TIDAK boleh dilakukan

- Jangan tambah kolom `article_id` di `article_workflow_logs`.
- Jangan ubah index yang sudah ada (`IX_awl_bundle` dan `IX_awl_article_workflow` tetap seperti semula).
- Jangan buat stored procedure apa pun — validasi requires_bundle dikerjakan nanti di Phase D/E.
- Jangan sentuh kode C#.

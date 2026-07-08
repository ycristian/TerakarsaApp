# Prompt 9b — Halaman Stasiun: Log Pra-Bundle (Terima & Selesai)

## Konteks

Fondasi stasiun (tabel, token auth, admin) sudah jadi di 9a. Prompt ini membuat halaman stasiun untuk operator dan pencatatan log workflow **level artikel** (bundle_id NULL). Alur per-bundle dengan scan QR dibuat di Prompt 12 — jangan dibuat sekarang.

Konsep log (2 baris per step, tabel `article_workflow_logs`, immutable):
- `RECEIVED` = divisi menerima pekerjaan dari step sebelumnya.
- `COMPLETED` = step selesai, qty diisi, `target_division_id` = divisi tujuan.
- Step pertama artikel (sort_order terkecil) langsung bisa COMPLETED tanpa RECEIVED.

## 1. Stored Procedures

### sp_WorkflowLog_Manage (@Action: CREATE, DELETE — tanpa UPDATE)

CREATE — parameter: @ArticleWorkflowId, @BundleId (nullable), @ResourceId, @QtyOk, @QtyRejectPrint, @QtyRejectFabric, @QtyRejectSewing, @QtyRework, @Remark, @TargetDivisionId (nullable), @Status ('RECEIVED'/'COMPLETED'), @CreatedBy.

Validasi (pesan error jelas):
1. article_workflows target hidup.
2. Status COMPLETED: kalau step `requires_bundle = 1` → @BundleId wajib; kalau `= 0` → @BundleId harus NULL. Status RECEIVED: @BundleId boleh NULL apa pun flag-nya.
3. Kalau @BundleId diisi → bundles.article_id harus = article_workflows.article_id.
4. Status COMPLETED: harus sudah ada log RECEIVED hidup di step yang sama — KECUALI step itu adalah sort_order terkecil (hidup) di artikelnya.
5. Tolak COMPLETED ganda dan RECEIVED ganda di step yang sama (level artikel; aturan per-bundle menyusul di Prompt 12).
6. Qty tidak boleh negatif. @TargetDivisionId wajib untuk COMPLETED (boleh NULL hanya jika step itu sort_order terbesar di artikelnya = step terakhir).

DELETE — soft delete + @DeleteReason wajib (max 255).

### SP untuk stasiun (semua berbasis @DivisionId)

- `sp_Station_PendingReceives`: step milik divisi ini yang step sebelumnya (sort_order tepat di bawahnya, hidup) sudah COMPLETED dengan target_division_id = divisi ini, tapi step ini belum punya RECEIVED. Kembalikan: article_workflow_id, project_name, article_name, style, color, step_name, qty_ok kiriman, waktu kirim, divisi pengirim.
- `sp_Station_ActiveWork`: step milik divisi ini yang bisa dikerjakan/diselesaikan — (sudah RECEIVED atau merupakan step pertama artikel) dan belum COMPLETED dan `requires_bundle = 0`. (Step requires_bundle = 1 belum bisa diselesaikan di prompt ini.)
- `sp_Station_Resources`: resource hidup + is_active milik divisi ini (untuk pilihan operator).

### sp_WorkflowLog_ListByArticle

Semua log hidup per artikel (JOIN step, division, resource, target division), urut sort_order lalu created_at. Dipakai di halaman Edit Article (riwayat).

## 2. API

### Endpoint stasiun ([RequireStationToken], divisi diambil dari token — BUKAN dari request)
- GET `api/station/resources`
- GET `api/station/pending-receives`
- GET `api/station/active-work`
- POST `api/station/receive` — body: articleWorkflowId, resourceId, remark opsional. Server set status RECEIVED. Kalau remark diisi → itu "terima dengan catatan".
- POST `api/station/complete` — body: articleWorkflowId, resourceId, qty-qty, targetDivisionId, remark. Server set status COMPLETED.
- `created_by` untuk log dari stasiun: pakai user sistem (buat 1 user 'station' nonaktif-login via script SQL seed, id-nya dikonfigurasi di appsettings) — kolom ini NOT NULL dan tidak ada JWT.
- GET `api/station/target-divisions` — daftar divisi hidup (untuk dropdown tujuan).

### Endpoint login biasa (JWT + RequireModule PROJECT)
- GET `api/articles/{articleId}/workflow-logs` (riwayat)
- DELETE `api/workflow-logs/{id}` + delete_reason — hanya Role Admin.

## 3. Blazor Client

### Halaman `/station` (rute publik, tanpa AuthorizeView, TIDAK muncul di sidebar)
Desain untuk layar sentuh: tombol dan teks besar, minim ketikan.

1. **Setup perangkat**: kalau token belum ada di localStorage → form tempel token → validasi ke `api/station/me` → simpan token, tampilkan nama stasiun + divisi di header selamanya.
2. **Sesi operator**: pilih nama dari daftar resource divisi (grid tombol besar), tersimpan di localStorage sampai tombol "Ganti Operator" ditekan. Semua aksi memakai resource sesi aktif.
3. **Tab "Menunggu Diterima"**: kartu per item (project, artikel, step, qty, dari divisi mana, kapan). Tombol **Terima** dan **Terima dengan Catatan** (modal remark wajib). Bisa pilih beberapa lalu terima sekaligus.
4. **Tab "Dikerjakan"**: kartu step aktif. Tombol **Selesai** → form: qty ok / reject print / reject fabric / reject sewing / rework (default 0, input numerik besar), dropdown divisi tujuan (sembunyikan kalau step terakhir), remark opsional → simpan → kembali ke daftar.
5. **Polling**: refresh kedua daftar tiap 15 detik + tombol refresh manual. Badge jumlah item di tiap tab.
6. JS Interop `IJSRuntime` untuk localStorage (pola yang sudah ada), HttpClient terpisah yang menyertakan header `X-Station-Token` (jangan pakai handler JWT).

### Halaman Edit Article (login biasa)
Tambah section read-only "Riwayat Log Workflow": tabel dari sp_WorkflowLog_ListByArticle (step, status, divisi, resource, qty, tujuan, remark, waktu). Tombol hapus hanya untuk Admin: konfirmasi + alasan wajib.

## Aturan tetap berlaku

Soft delete, filter deleted_at IS NULL, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan buat scan QR / alur per-bundle — Prompt 12.
- Jangan buat pembuatan bundle — Prompt 10.
- Jangan tambah kolom di article_workflow_logs; pakai kolom yang sudah ada (received_at/received_by_resource_id boleh dibiarkan tidak terpakai).
- Jangan tambah menu sidebar untuk `/station`.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

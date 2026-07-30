# Prompt 34 — Auto-Terima per Step Workflow

## Konteks

Serah terima saat ini selalu manual: divisi tujuan harus menekan Terima (action RECEIVE) untuk mengisi `received_at`. Di lapangan ada transisi yang tidak butuh konfirmasi, contoh: QC → Buang Benang.

Fitur baru: flag **auto-terima** melekat di **step PENERIMA**. Jika step penerima punya `auto_receive = 1`, maka setiap baris log yang diserahkan ke step itu langsung dianggap diterima saat baris dibuat — `received_at` terisi di transaksi yang sama, tanpa aksi RECEIVE.

Aturan yang disepakati:
- Flag ada di `workflow_template_steps` DAN `article_workflows` (ter-copy saat APPLY, bebas diedit per artikel setelahnya — pola sama dengan `requires_bundle`).
- Penerima otomatis: `received_by_resource_id` = resource pelaksana PENGIRIM (boleh NULL jika pengirim tanpa resource), `received_remark = 'Otomatis: auto-terima'`.
- Berlaku untuk step ber-bundle maupun non-bundle.
- Berlaku juga di pembuatan bundle: jika step station pertama (penerima log Bundling) ber-flag auto, log Bundling langsung diterima saat bundle dibuat.
- Edit bundle: jika log Bundling masih `received_at IS NULL` dan step penerimanya kini ber-flag auto → langsung diterima dalam transaksi UPDATE.
- **Tidak retroaktif**: mengaktifkan flag TIDAK menyentuh log pending yang sudah ada. Hanya transaksi baru (CREATE log, CREATE bundle) dan UPDATE bundle yang men-trigger.

Data DB masih data uji — tidak perlu backfill.

## 1. Skema

### a. Edit `sql/create_tables_tmos_final.sql`
- `workflow_template_steps`: tambah setelah `requires_bundle`:
  ```sql
   auto_receive bit not null default 0,       -- serah ke step ini otomatis diterima (received_at terisi saat insert log)
  ```
- `article_workflows`: kolom sama, setelah `requires_bundle` (sebelum `is_bundling`).

### b. Buat `sql/alter_34_auto_receive.sql` (manual, idempotent)
```sql
ALTER TABLE workflow_template_steps
  ADD auto_receive bit NOT NULL CONSTRAINT DF_wts_auto_receive DEFAULT 0;
ALTER TABLE article_workflows
  ADD auto_receive bit NOT NULL CONSTRAINT DF_aw_auto_receive DEFAULT 0;
```
Bungkus dengan cek `IF COL_LENGTH(...) IS NULL`.

## 2. Definisi "step penerima" (dipakai semua SP di bawah)

Baris log dibuat oleh step pengirim S dengan `@TargetDivisionId` = D. Step penerima = step HIDUP artikel yang sama dengan `sort_order` terkecil yang > sort_order S dan `division_id = D`. Tidak ketemu → tidak ada auto-terima (perilaku lama).

Untuk rantai ber-bundle, step penerima praktis = step hidup tepat berikutnya (pola penentuan target yang sudah dipakai `SIS_WorkflowLog_Manage` / `SIS_Bundle_Manage`) — pakai referensi step itu langsung, jangan hitung ulang lewat division saja.

## 3. SIS_WorkflowLog_Manage (`sql/sp_WorkflowLog_Manage.sql`)

### CREATE
Setelah semua validasi lolos, sebelum/saat INSERT: bila step penerima ada dan `auto_receive = 1` → insert baris dengan `received_at = SYSDATETIME()`, `received_by_resource_id = @ResourceId` (boleh NULL), `received_remark = 'Otomatis: auto-terima'`. Selain itu perilaku lama (received NULL).

Catatan:
- Step Bundling (`is_bundling = 1`) tidak pernah jadi target CREATE ini — tidak ada perlakuan khusus.
- RECEIVE / UNRECEIVE / UPDATE / REVISE_HANDOVER / CANCEL_HANDOVER / DELETE: **tidak diubah**. UNRECEIVE tetap boleh membatalkan baris yang auto-received (guard lama tetap berlaku).

## 4. SIS_Bundle_Manage (`sql/sp_Bundle_Manage.sql`)

### CREATE
Saat insert log Bundling: bila step penerima (step hidup berikutnya setelah step Bundling) ber-`auto_receive = 1` → isi `received_at = SYSDATETIME()`, `received_by_resource_id = @BundlingResourceId` (boleh NULL), `received_remark = 'Otomatis: auto-terima'` pada insert yang sama.

### UPDATE
Setelah guard lama lolos dan sinkronisasi qty log Bundling selesai, tambahan dalam transaksi yang sama: bila log Bundling bundle ini masih hidup dengan `received_at IS NULL`, DAN step penerimanya `auto_receive = 1` → set trio received seperti CREATE (`received_by_resource_id` = `@BundlingResourceId` bila dikirim, kalau tidak pakai `resource_id` log Bundling saat ini; boleh NULL).

Guard UPDATE/DELETE lama ("Bundle sudah diproses") **tidak diubah** — auto-received dihitung sama dengan diterima manual: bundle yang lognya sudah received menolak edit/hapus. Konsekuensinya wajar dan diterima.

## 5. SIS_ArticleWorkflow_Manage & Template

- `SIS_WorkflowTemplate_Manage` CREATE/UPDATE: terima `AutoReceive` di JSON steps, simpan ke kolom.
- `SIS_ArticleWorkflow_Manage`:
  - APPLY: copy `auto_receive` dari template step ke `article_workflows`. Step Bundling sisipan sistem: `auto_receive = 0`.
  - SAVE: terima `AutoReceive` di JSON steps, update/insert seperti kolom lain. Baris `is_bundling = 1` tetap dikecualikan.
- SAVE/UPDATE **tidak** menyentuh log pending (tidak retroaktif).

## 6. Select SP

- `sp_WorkflowTemplate_GetById`: kembalikan `auto_receive` di steps.
- `sp_ArticleWorkflow_Select`: kembalikan `auto_receive`.
- SP lain (ScanInfo, Station, Report, WorkflowLog list): **tidak perlu perubahan logika** — status tetap diturunkan dari `received_at`. Baris auto-received tampil sebagai sudah diterima, tidak pernah muncul di tab Masuk / pending receives, dan langsung siap untuk step berikutnya. Cukup verifikasi wajar.

## 7. API & Shared

- `WorkflowTemplateModels` / `ArticleWorkflowModels`: tambah `AutoReceive` (bool) di step model + payload save.
- Service terkait: teruskan parameter ke SP.

## 8. Client

- **Editor template workflow** (grid steps): tambah kolom checkbox **"Auto Terima"** per baris.
- **Editor workflow artikel** (`ArticleEdit.razor`): checkbox "Auto Terima" per baris step; baris Bundling read-only tanpa checkbox.
- **Riwayat log / timeline scan**: baris dengan `received_remark = 'Otomatis: auto-terima'` tampil dengan label penerima "Otomatis" bila `received_by` kosong (jangan tampil kosong melompong).
- UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan auto-terima log pending lama saat flag diaktifkan (SAVE workflow / update template) — hanya CREATE log, CREATE bundle, UPDATE bundle.
- Jangan ubah action RECEIVE / UNRECEIVE / REVISE_HANDOVER — REVISE_HANDOVER yang mengganti divisi tujuan TIDAK men-trigger auto-terima.
- Jangan tambah flag di step Bundling implisit (selalu 0, tetap read-only di UI).
- Jangan ubah format serial, bundle_no, payload label, alur print.
- Jangan eksekusi SQL ke database — script manual di `sql/` saja.

## Verifikasi

1. `dotnet build` sukses.
2. Skenario manual (setelah `alter_34`):
   - Template: centang Auto Terima di step Buang Benang → apply ke artikel baru → flag ter-copy.
   - QC serahkan bundle ke Buang Benang → log langsung `received_at` terisi, penerima = resource pengirim, remark otomatis; bundle TIDAK muncul di tab Masuk station Buang Benang, langsung bisa dikerjakan.
   - Step station pertama ber-flag auto → buat bundle → log Bundling langsung diterima.
   - Bundle lama pending (dibuat sebelum flag aktif) → edit bundle → log langsung diterima.
   - Step tanpa flag → perilaku lama utuh (RECEIVE manual).
3. Di akhir: daftar file diubah/dibuat + script SQL yang harus dijalankan manual.


Script Opsional — Aktifkan Auto-Terima untuk Buang Benang

Buat sql/seed_34_auto_receive_buang_benang.sql (manual, opsional, idempotent). Isinya mengaktifkan auto_receive = 1 untuk semua step Buang Benang yang sudah ada:

workflow_template_steps: semua baris hidup yang division_id mengarah ke divisi bernama Buang Benang.
article_workflows: semua baris hidup dengan divisi sama, di semua artikel yang sudah ada.

Cari divisi berdasarkan nama (LIKE '%trim%' case-insensitive) — jangan hardcode id. Tampilkan jumlah baris ter-update per tabel. Jika nama divisi di DB ternyata berbeda (mis. "Trim"), cukup ganti pola LIKE di script — beri komentar jelas di bagian atas script.
# Prompt 18 — Status Project & Penguncian Aksi Produksi

> Dieksekusi SETELAH Prompt 17 selesai dan lolos tes (menyentuh SP yang sama).

## Konteks

Project butuh status supaya mudah dicari mana yang masih berjalan, dan supaya aktivitas produksi terkunci saat project selesai/ditahan/dibatalkan. Desain yang disepakati — 5 status:

| Status | Sumber | Arti |
|---|---|---|
| Not Started | Otomatis | `manual_status` NULL dan belum ada log workflow hidup di artikel project |
| On Going | Otomatis | `manual_status` NULL dan sudah ada log workflow hidup |
| On Hold | Manual | Dijeda (bahan belum datang, menunggu buyer, dll.) |
| Completed | Manual | Selesai — keputusan bisnis, bukan hitungan sistem |
| Cancelled | Manual | PO batal — terkunci, tersembunyi dari daftar default, data tetap ada |

Prinsip:
1. Status otomatis TIDAK disimpan — diturunkan (derived) di SP select. Satu sumber kebenaran, tidak bisa basi.
2. Status manual di-set lewat **tombol aksi + konfirmasi** (bukan input teks); nilai divalidasi di SP.
3. Penguncian: `manual_status IS NOT NULL` → semua aksi produksi ditolak. Not Started HARUS tetap bisa input (kalau tidak, log pertama tak pernah bisa masuk).
4. Operator/station TIDAK bisa membuka project — hanya user login ber-privilege lewat halaman project. Station cukup menampilkan pesan error SP apa adanya.
5. `status_reason` WAJIB saat Tahan/Batalkan — jadi komunikasi lintas divisi (tampil di detail project dan pesan error penolakan).

## 1. Skema

### a. Edit `sql/create_tables_tmos_final.sql` — tabel `projects`, sebelum `created_at`:
```sql
 manual_status varchar(20) null,            -- NULL = otomatis (Not Started/On Going); ON_HOLD / COMPLETED / CANCELLED
 status_reason varchar(255) null,           -- wajib utk ON_HOLD & CANCELLED (komunikasi lintas divisi)
 status_changed_at datetime2 null,
 status_changed_by int null,
```
Tambah komentar penjelasan konsep derived vs manual di atas tabel.

### b. Buat `sql/alter_18_project_status.sql` (dijalankan manual)
`ALTER TABLE projects ADD` keempat kolom di atas.

## 2. SIS_Project_Manage (`sql/sp_Project_Manage.sql`)

Action baru `SET_STATUS`, parameter baru `@ManualStatus VARCHAR(20) = NULL`, `@StatusReason VARCHAR(255) = NULL`:
1. Project harus hidup.
2. `@ManualStatus` hanya boleh: `ON_HOLD`, `COMPLETED`, `CANCELLED`, atau NULL (= Lanjutkan/Buka Kembali → status kembali otomatis). Nilai lain → RAISERROR.
3. `ON_HOLD`/`CANCELLED`: `@StatusReason` wajib (trim tidak kosong). `COMPLETED` dan NULL: reason opsional, dan saat NULL kolom `status_reason` ikut dikosongkan.
4. Set `manual_status`, `status_reason`, `status_changed_at = SYSDATETIME()`, `status_changed_by = @UserId`, plus `updated_at/updated_by`.

Aksi `DELETE` project: tetap seperti sekarang (soft delete beda urusan dengan Cancelled).

## 3. Penguncian di SP produksi

Buat pengecekan seragam (copy pola yang sama, komentar merujuk Prompt 18) di awal aksi berikut, setelah entitas ditemukan:

```sql
DECLARE @ManualStatus VARCHAR(20), @StatusReason VARCHAR(255);
SELECT @ManualStatus = p.manual_status, @StatusReason = p.status_reason
FROM projects p
INNER JOIN articles a ON a.project_id = p.project_id
WHERE a.article_id = @ArticleId;

IF @ManualStatus IS NOT NULL
BEGIN
    -- pesan per status, sertakan alasan bila ada
    RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, <label>, <alasan>);
    RETURN;
END
```
Label pesan: `ON_HOLD` → "sedang ditahan", `COMPLETED` → "sudah ditandai selesai", `CANCELLED` → "sudah dibatalkan". Bila `status_reason` terisi, tampilkan: `... (Alasan: xxx)`.

Terapkan di:
1. **`SIS_Bundle_Manage`** — CREATE, UPDATE, DELETE (artikel didapat dari `@ArticleId` saat CREATE; dari bundle saat UPDATE/DELETE). `SIS_Bundle_ReprintLabel` TIDAK dikunci.
2. **`SIS_WorkflowLog_Manage`** — CREATE, UPDATE, RECEIVE, UNRECEIVE (artikel via `article_workflow_id` → `article_workflows.article_id`; untuk RECEIVE/UNRECEIVE via baris log `@Id`). DELETE log TIDAK dikunci (koreksi data oleh admin tetap boleh).

TIDAK mengunci: edit master project/artikel/workflow/attachment/foto, pembuatan project baru.

## 4. Select & tampilan

### `sql/sp_Project_Select.sql`
- `SIS_Project_GetAll`: kembalikan kolom `derived_status` —
  ```sql
  CASE WHEN p.manual_status IS NOT NULL THEN p.manual_status
       WHEN EXISTS (SELECT 1 FROM article_workflow_logs awl
                    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
                    INNER JOIN articles a ON a.article_id = aw.article_id
                    WHERE a.project_id = p.project_id
                      AND awl.deleted_at IS NULL AND aw.deleted_at IS NULL AND a.deleted_at IS NULL)
            THEN 'ON_GOING' ELSE 'NOT_STARTED' END
  ```
  plus `status_reason`, `status_changed_at`. Tambah parameter filter opsional `@Status VARCHAR(20) = NULL` (filter berdasarkan derived_status).
- `SIS_Project_GetById`: kembalikan kolom yang sama + nama user `status_changed_by`.

### API & Shared
- `ProjectModels.cs`: tambah `DerivedStatus`, `StatusReason`, `StatusChangedAt`(+nama pengubah di detail); request `SetStatus`.
- `ProjectService.cs` / `ProjectController.cs`: endpoint `SET_STATUS` + filter status di list. Endpoint set-status memakai privilege modul PROJECT yang sudah ada untuk update (tidak bikin privilege baru — kalau pola privilege per-aksi sudah ada di modul lain, ikuti pola itu).

### Client
- **`Project.razor` (list)**: dropdown filter status 5 nilai + "Semua". Default: tampilkan Not Started + On Going + On Hold (Completed & Cancelled tersembunyi). Badge status berwarna per baris (label Indonesia: Belum Dimulai / Berjalan / Ditahan / Selesai / Dibatalkan); untuk Ditahan tampilkan alasan sebagai tooltip/subteks.
- **`ProjectEdit.razor` (detail)**: panel status — badge besar + alasan + kapan/oleh siapa diubah. Tombol sesuai kondisi:
  - Otomatis (Not Started/On Going): **Tandai Selesai**, **Tahan**, **Batalkan**
  - On Hold: **Lanjutkan**, **Tandai Selesai**, **Batalkan**
  - Completed/Cancelled: **Buka Kembali**
  Tahan & Batalkan memunculkan dialog konfirmasi dengan input alasan wajib; lainnya konfirmasi biasa. Semua teks Indonesia.

## Aturan tetap berlaku
Soft delete, `deleted_at IS NULL`, prefix `SIS_`, pola `@Action`, UI Indonesia, CloseButton/navigasi sesuai konvensi.

## Yang TIDAK boleh dilakukan
- Jangan simpan Not Started/On Going sebagai data — hanya derived di select.
- Jangan buat kolom status teks bebas atau input teks status di UI.
- Jangan tambah mekanisme reopen di station/API stasiun.
- Jangan kunci SIS_Bundle_ReprintLabel, DELETE log, atau SP master data.
- Jangan ubah logika Prompt 17 (step Bundling) selain menambah cek status di awal action.

## Verifikasi
1. `dotnet build` sukses.
2. Skenario manual (setelah `alter_18` dijalankan):
   - Project baru = Belum Dimulai; input Hasil Cutting pertama → otomatis Berjalan.
   - Tahan dengan alasan → buat bundle / catat log / RECEIVE di station ditolak dengan pesan berisi alasan; Lanjutkan → normal lagi.
   - Tandai Selesai → semua aksi produksi ditolak; Buka Kembali (privilege) → normal.
   - Batalkan tanpa alasan → ditolak; dengan alasan → project hilang dari list default, muncul lewat filter.
   - Reprint label tetap bisa pada project selesai.
3. Di akhir: daftar file diubah/dibuat + script SQL manual.

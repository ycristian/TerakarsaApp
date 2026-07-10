# Prompt 12d — Jejak Revisi Log + Pemisahan Pencatat vs Pelaksana

## Konteks

Dua masalah pada article_workflow_logs:
1. Action UPDATE (revisi qty/size sebelum diterima) tidak meninggalkan jejak apa pun.
2. Semantik identitas membingungkan: label form "Resource Pencatat" salah — pencatat
   sebenarnya adalah user login (`created_by`), sedangkan resource adalah **pelaksana**
   pekerjaan. Riwayat juga menampilkan `created_by` sebagai angka mentah tanpa nama.

Ketentuan identitas (berlaku ke seluruh tampilan):
- **Pencatat** = user (`created_by` → users). Dari halaman login = user asli;
  dari stasiun = user sistem 'station'.
- **Pelaksana** = resource (`resource_id` → resources), opsional untuk step non-bundle.
Tidak ada kolom employee di log — karyawan pelaksana didaftarkan sebagai resource
(employees.resource_id sudah tersedia untuk penautan di master).

## 1. Skema SQL

Perbarui `sql/create_tables_tmos_final.sql` (tabel article_workflow_logs) dan buat
`sql/alter_12d_log_update_audit.sql` (idempotent):
- ADD `updated_at datetime2 null`
- ADD `updated_by int null` — user pengubah (dari halaman login = user asli;
  dari stasiun = user sistem 'station')
- ADD `updated_by_resource_id int null`
  + `FK_awl_updated_by_resource` → resources(resource_id) — operator sesi aktif,
  hanya terisi bila revisi dari stasiun
- Komentar: trio updated_* hanya diisi action UPDATE (revisi sebelum diterima);
  log tetap tidak boleh diubah setelah received_at terisi.

## 2. SIS_WorkflowLog_Manage — action UPDATE

- Parameter baru: @UpdatedByResourceId INT = NULL.
- @UserId WAJIB untuk UPDATE ('User pengubah tidak dikenal.') — API stasiun mengirim
  user sistem 'station' (pola created_by yang sudah ada), halaman login mengirim
  user JWT.
- Jika @UpdatedByResourceId diisi: resource harus hidup dan milik divisi baris log
  ('Operator bukan milik divisi ini.').
- SET tambahan: updated_at = SYSDATETIME(), updated_by = @UserId,
  updated_by_resource_id = @UpdatedByResourceId.
- Aturan lain UPDATE tidak berubah (tolak jika sudah diterima, dsb).

## 3. SP read — nama, bukan angka

- `SIS_WorkflowLog_ListByArticle`: JOIN users untuk CreatedByName; LEFT JOIN untuk
  UpdatedAt, UpdatedByName (users), UpdatedByResourceName (resources).
- `SIS_Station_PendingHandover` dan `SIS_Station_PendingReceives`: tambah UpdatedAt
  (untuk badge "direvisi"; nama tidak perlu di kartu stasiun).

## 4. API & Client

- StationLogUpdateRequest: tambah ResourceId (operator sesi aktif) → diteruskan
  sebagai @UpdatedByResourceId; @UserId diisi user sistem 'station' di API.
  Endpoint revisi dari halaman login (jika ada / ditambah nanti) mengirim user JWT
  dan @UpdatedByResourceId = NULL.
- Halaman stasiun: kirim resource sesi aktif saat revisi.
- **Label form** di WorkflowInputManager: "Resource Pencatat" → "Pelaksana (opsional)".
- **Riwayat** (Edit Article + riwayat di halaman Hasil Cutting):
  - Kolom "Pencatat" = CreatedByName.
  - Kolom "Pelaksana" = ResourceName (tampil "-" bila kosong).
  - Kolom "Direvisi" = "{UpdatedAt} oleh {UpdatedByResourceName ?? UpdatedByName}"
    bila UpdatedAt terisi, selain itu "-".
- Kartu "Menunggu Diserahkan" / "Menunggu Diterima" di stasiun: badge kecil
  "Direvisi {waktu}" bila UpdatedAt terisi.
- Model Shared: tambah CreatedByName, UpdatedAt, UpdatedByName,
  UpdatedByResourceName di DTO terkait.

## Yang TIDAK boleh dilakukan

- Jangan izinkan UPDATE setelah received_at terisi — aturan ini tetap.
- Jangan tambah kolom employee di log dalam bentuk apa pun.
- Jangan ubah action CREATE/RECEIVE/DELETE, alur scan, bundle, print.
- Jangan pindahkan input non-bundle kembali ke stasiun.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

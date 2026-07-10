# Prompt 13 — Modul Laporan Arus Bundle

## Konteks

Modul laporan baru untuk supervisor via UI login: memantau arus bundle dari data
article_workflow_logs (model 1 baris: baris dibuat saat divisi selesai/serah,
received_at terisi saat divisi tujuan menerima).

Tiga laporan:
A. WIP — posisi setiap bundle saat ini
B. Progres — matriks step × bundle per artikel dalam satu project
C. Riwayat — timeline perjalanan satu bundle

## 1. Definisi posisi bundle (dipakai laporan A & B)

"Log terakhir" bundle = baris article_workflow_logs hidup (deleted_at IS NULL)
dengan sort_order step (article_workflows) terbesar, tie-break created_at terbesar.

| Kondisi log terakhir | Status | Posisi |
|---|---|---|
| Tidak ada log | BELUM_MULAI | divisi step bundle pertama artikel |
| received_at NULL, target_division_id NOT NULL | TRANSIT | selesai di division_id, menunggu target_division_id |
| received_at NOT NULL, target_division_id NOT NULL | DIKERJAKAN | di target_division_id |
| target_division_id NULL (step terakhir) | SELESAI | - |

## 2. Stored procedures (read-only, nama fungsional, prefix SIS_)

`sql/sp_Report_Bundle.sql` berisi tiga SP:

### SIS_Report_BundleWip
- Param: @ProjectId INT = NULL, @ArticleId INT = NULL, @DivisionId INT = NULL
  (posisi saat ini), @Status VARCHAR(20) = NULL.
- Hasil per bundle: BundleId, Serial, BundleNo, ProjectName, ArticleName, SizeName,
  Qty, Status (sesuai tabel di atas), PosisiDivisionName, StepName (step log
  terakhir / step pertama utk BELUM_MULAI), TailorName (resource_person_name ??
  resource_name), UpdatedInfo (created_at / received_at log terakhir — kapan
  posisi ini terjadi).
- Urut: ProjectName, ArticleName, BundleNo.

### SIS_Report_ArticleProgress
- Param: @ProjectId INT (wajib).
- Result set 1 — per artikel per step bundle (requires_bundle = 1, urut sort_order):
  ArticleId, ArticleName, ArticleWorkflowId, StepName, DivisionName, SortOrder,
  TotalBundle (bundle hidup artikel), BundleSelesai (punya log di step ini),
  BundleDiterima (log step ini received_at NOT NULL), QtyOk (SUM qty_ok step ini),
  QtyReject (SUM 3 kolom reject + rework).
- Result set 2 — per artikel per step non-bundle (requires_bundle = 0):
  ArticleId, StepName, DivisionName, SortOrder, QtyTarget (SUM article_sizes.qty
  artikel), QtyOk, QtyReject.

### SIS_Report_BundleHistory
- Param: @Serial VARCHAR(20) = NULL, @ProjectId INT = NULL, @BundleNo INT = NULL —
  wajib salah satu: @Serial, ATAU pasangan @ProjectId + @BundleNo.
- Result set 1 (header): info bundle + project + artikel + size + qty + tailor +
  status/posisi (logika bagian 1).
- Result set 2 (timeline, urut sort_order): StepName, DivisionName,
  TargetDivisionName, QtyOk, QtyReject (gabungan), Remark, PelaksanaName
  (resource), CreatedAt, CreatedByName (JOIN users), ReceivedAt,
  ReceivedByResourceName, ReceivedRemark.
- Boleh memakai ulang logika SIS_Bundle_ScanInfo bila cocok, tapi SP scan publik
  TIDAK boleh diubah.

Semua SP hanya membaca baris hidup (deleted_at IS NULL) dan mengembalikan nama
(JOIN), bukan id mentah, untuk kolom tampilan.

## 3. Module & menu

- Module baru `REPORT_BUNDLE`, nama menu "Laporan Bundle" — seed idempotent
  `sql/seed_report_bundle_module.sql`, ikuti pola seed_workflow_input_module.sql.
- Akses: role yang sama dengan BUNDLE_MANAGE.

## 4. API

`ReportBundleController` (`api/report-bundle/...`), JWT + cek module REPORT_BUNDLE:
- GET `wip?projectId=&articleId=&divisionId=&status=`
- GET `progress?projectId=`
- GET `history?serial=` atau `history?projectId=&bundleNo=`
- DTO di TerakarsaApp.Shared, satu file area laporan.

## 5. Client

Halaman `/report-bundle` (module REPORT_BUNDLE), tiga tab:

### Tab WIP
- Filter: Project (SearchableSelect, opsional), Artikel (terisi setelah project),
  Divisi posisi, Status (dropdown 4 nilai). Tombol Terapkan.
- Tabel: Bundle No, Serial, Project, Artikel, Size, Qty, Step, Posisi, Status
  (badge warna: BELUM_MULAI abu, TRANSIT kuning, DIKERJAKAN biru, SELESAI hijau),
  Penjahit, Waktu.
- Klik baris → buka tab Riwayat dengan bundle tsb.
- Baris ringkasan jumlah bundle per status di atas tabel.

### Tab Progres
- Filter: Project (wajib).
- Per artikel satu kartu: judul artikel + total bundle, tabel step (urut
  sort_order): Step, Divisi, Selesai/Total bundle (mis. "8/12"), Diterima,
  Qty OK, Qty Reject, bar progres sederhana (BundleSelesai/TotalBundle).
  Step non-bundle tampil di tabel yang sama dengan Qty OK/QtyTarget sebagai
  ukuran progres dan tanpa kolom bundle.

### Tab Riwayat
- Input pencarian: Serial (ketik/tempel hasil scan) ATAU pilih Project + Bundle No.
- Tampilan: kartu header bundle + timeline vertikal per step (pola visual boleh
  meniru halaman scan publik): waktu, step, divisi asal → tujuan, qty, pelaksana,
  pencatat, status diterima + waktu + penerima, remark.

Bahasa UI Indonesian. Navigasi ikuti aturan 11e (tidak ada halaman anak di sini,
semua dalam satu halaman ber-tab).

## Yang TIDAK boleh dilakukan

- Jangan mengubah SP/endpoint/halaman yang sudah ada (stasiun, scan publik,
  bundle, workflow input) — modul ini murni tambahan read-only.
- Jangan menulis apa pun ke database selain seed module.
- Jangan membuat export Excel/PDF — ditunda.
- Jangan tambah kolom/tabel baru.

Setelah selesai: daftar file dibuat/diubah + script SQL yang harus dijalankan
manual (sp_Report_Bundle.sql, seed_report_bundle_module.sql).

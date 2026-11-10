# Prompt 82 — Audit laporan & query (bagian "Laporan dan query")

Status: **audit selesai + fondasinya dibuat; pengalihan tiap laporan BELUM dikerjakan.**

Prompt 82 (revisi) menetapkan **dua jalur** selama PO lama masih jalan:

- baris log dengan `created_at` **<** `app_settings.bundle_split_migrated_at` → reject/hilang
  dibaca dari `qty_reject_*` / `qty_lost` (seperti hari ini, kolomnya tidak disentuh migrasi)
- sesudah tanggal itu → dari **bundle anak** (`bundles.status`/`reject_category`) dan
  `bundles.missing_qty`

Karena migrasi versi revisi **tidak melahirkan anak dari reject lama**, angka laporan untuk
data lama **tidak berubah sedikit pun** setelah migrasi. Yang perlu ditambahkan adalah
sumber KEDUA untuk data baru. Menjumlahkan dua sumber tanpa batas tanggal = **dobel**.

## Fondasi yang sudah dibuat

[sql/v_84_reject_unified.sql](../sql/v_84_reject_unified.sql) → view
`v_bundle_reject_unified`, satu baris per (bundle, step, kategori):

| Kolom | Isi |
|---|---|
| `BundleId` | bundle INDUK sumber reject-nya |
| `ChildBundleId` | id bundle anak (NULL untuk baris gaya lama) |
| `ArticleWorkflowId`, `DivisionId`, `ResourceId`, `EmployeeId` | step & pelaksana |
| `WorkflowLogId` | baris log sumber — penyambung ke `lock_id` → periode gajian |
| `CreatedAt` | waktu kejadian (basis filter periode) |
| `Category` | RejectBahan \| RejectJahit \| RejectPrint \| Perbaikan \| TidakLengkap \| Hilang |
| `Qty` | jumlah pcs |
| `Source` | `LAMA` \| `ANAK` |

Batas tanggalnya ada **di dalam view**, jadi tiap laporan cukup `SUM(Qty)` dengan filter
kategori/periode dan tidak perlu mengulang aturan tanggalnya sendiri-sendiri.

## Definisi baru (acuan semua perubahan)

| Angka | Sumber baru |
|---|---|
| Total pcs PO | `SUM(bundles.qty)` bundle aktif **+** `SUM(bundles.missing_qty)` (boleh negatif) |
| Qty awal bundle | `qty_after` baris log PERTAMA (`log_kind = 'Creation'`), bukan `bundles.qty` |
| Qty bundle saat ini | `bundles.qty` (cermin `qty_after` baris log terakhir) |
| Reject per kategori | `v_bundle_reject_unified` |
| Hilang / Lebih | `bundles.missing_qty` induk utama (`sequence_no = 0`) |
| Rekap per penjahit | `employee_id` baris log `Kirim` induk untuk OK + `v_bundle_reject_unified` untuk sisanya |

Bundle anak dikenali `sequence_no > 0`; induk utama `sequence_no = 0`; `root_bundle_id`
mengikat satu pohon.

## A. Laporan yang membaca `qty_reject_*` / `qty_lost`

Semua di bawah **tetap benar untuk data lama**; yang hilang adalah data baru (kolomnya 0).
Perubahannya seragam: ganti penjumlahan kolom dengan `v_bundle_reject_unified`.

| File | Baris | Yang dibaca | Perlu jadi |
|---|---|---|---|
| [sp_Report_Produksi.sql](../sql/sp_Report_Produksi.sql) | 144–165 | 5 kolom reject per kategori per periode | `v_bundle_reject_unified` difilter periode lewat `WorkflowLogId` → `lock_id` → `workflow_locks.payroll_period_id` |
| [sp_Report_Produksi.sql](../sql/sp_Report_Produksi.sql) | 191 | `SUM(qty_ok + semua reject)` sebagai "qty keluar" | `qty_ok` saja |
| [sp_Report_Bundle.sql](../sql/sp_Report_Bundle.sql) | 178, 263, 283, 418 | `qty_reject` agregat 5 kolom | `SUM(Qty)` dari view, per `BundleId` |
| [sp_Report_Bundle.sql](../sql/sp_Report_Bundle.sql) | 483 | `QtyKeluar = qty_ok + semua reject` | `qty_ok` saja |
| [sp_Report_LineDetail.sql](../sql/sp_Report_LineDetail.sql) | 88, 361–362, 437–442, 595 | reject & lost per baris log / per line | view, join `WorkflowLogId` |
| [sp_Dashboard_TargetHarian.sql](../sql/sp_Dashboard_TargetHarian.sql) | 59 | `QtyReject` 3 kategori | view, kategori Reject* saja |
| [sp_Report_RekapStruk.sql](../sql/sp_Report_RekapStruk.sql) | 161–165, 405–409 | 5 kolom per baris struk | view, join `WorkflowLogId` |
| [sp_Report_RekapStruk.sql](../sql/sp_Report_RekapStruk.sql) | 234–235, 276–277 | `TercatatQty` = qty_ok + semua reject | `qty_ok` saja |
| [sp_Station_RekapProduksi.sql](../sql/sp_Station_RekapProduksi.sql) | 90, 117 | `qty_ok + qty_reject_fabric` (reject BAHAN tetap dibayar) | `qty_ok` + view kategori `RejectBahan` |
| [sp_Report_ActivityLog.sql](../sql/sp_Report_ActivityLog.sql) | 96–100 | kolom mentah per baris log | tambahkan `log_kind`, `qty_delta`, `qty_after`, `reason` + daftar anak |
| [sp_Article_Wip.sql](../sql/sp_Article_Wip.sql) | 86 | total reject+lost per step | view, semua kategori |
| [sp_Print_Render.sql](../sql/sp_Print_Render.sql) | 181–185, 365–369, 421–424 | kupon borongan & nota reject | kupon: tetap boleh 0; nota reject diganti stiker bundle anak (dicetak otomatis `SIS_BundleSplit_PrintLabel`) |

### Sengaja TIDAK diubah

- [sp_WorkflowLock_Manage.sql](../sql/sp_WorkflowLock_Manage.sql) 165–172 dan
  [sp_UnlockRequest_Select.sql](../sql/sp_UnlockRequest_Select.sql) 73–74, 147–148, 175–190 —
  `snap_qty_*` adalah **snapshot historis** saat lock dipasang; harus tetap merekam isi baris
  saat itu, apa pun modelnya.
- [sp_SuperAdmin_Manage.sql](../sql/sp_SuperAdmin_Manage.sql) 239–243, 421–425 — jalur koreksi
  Super Admin atas baris LAMA.
- `SIS_WorkflowLog_Manage` action `ADJUST` — mekanisme gaya lama yang **memang
  dipertahankan** untuk bundle ber-reject gaya lama (lihat bagian C).
- `migration_33_*`, `golive_55_*`, `lock_periode_*`, `adhoc_*`, `test_55_*` — script sekali
  jalan yang sudah selesai.

## B. Rantai qty / `bundles.qty` sebagai "qty awal"

| File | Baris | Status |
|---|---|---|
| [sp_Bundle_ScanInfo.sql](../sql/sp_Bundle_ScanInfo.sql) | `@StepQuota` + frontier | **SUDAH diubah**: QtyMasuk = `bundles.qty` (qty saat ini), frontier = step di atas baris `log_kind IN ('Creation','Kirim')` terakhir |
| [sp_Station_Operations.sql](../sql/sp_Station_Operations.sql) | `SIS_Station_InProgress` + `SIS_Station_Counts` | **SUDAH diubah**, definisi frontier identik |
| [sp_WorkflowLog_Select.sql](../sql/sp_WorkflowLog_Select.sql) | 93 (`SIS_WorkflowLog_QuotaInfo`) | **belum** — masih rumus kuota lama. Sejak modal Kirim Hasil pindah ke `SIS_BundleSplit_Info`, SP ini hanya dipakai jalur non-bundle |
| [fn_55_workflow_saldo.sql](../sql/fn_55_workflow_saldo.sql) | 51, 97 | **belum** — penjaga saldo Prompt 55 masih menjumlahkan 6 kolom. Untuk baris baru 5 di antaranya 0, jadi efektif = `qty_ok`; aman tapi perlu disederhanakan |
| [sp_WorkflowLog_Manage.sql](../sql/sp_WorkflowLog_Manage.sql) | kuota CREATE/UPDATE | **belum, sengaja** — jalur log lama (non-bundle, admin, ADJUST). Kirim Hasil ber-bundle sudah tidak lewat sini |
| [sp_Bundle_Select.sql](../sql/sp_Bundle_Select.sql) | 125 (`TotalBundleQty`) | `SUM(b.qty)` kini mencakup induk **dan** anak, jadi totalnya tetap ≈ output cutting dikurangi `missing_qty`. `BundleCount` ikut menghitung anak |
| [sp_Station_Operations.sql](../sql/sp_Station_Operations.sql) | 332 (kartu Buat Bundle) | sama seperti di atas |
| [sp_Report_DivisionWip.sql](../sql/sp_Report_DivisionWip.sql) | 270 | `BundleQty` project — ikut mencakup anak |
| [sp_Project_Select.sql](../sql/sp_Project_Select.sql) | 9 | progres per size dari `SUM(bundles.qty)` — ikut mencakup anak |

## C. Yang sudah dikerjakan di Prompt 82

- `app_settings.bundle_split_migrated_at` — batas dua jalur, diisi migrasi.
- `v_bundle_reject_unified` — satu sumber reject/hilang lintas dua jalur.
- Panel **Penyesuaian (ADJUSTMENT)** di kartu scan kini hanya muncul untuk bundle yang
  punya reject gaya lama (`qty_reject_*` > 0 pada baris log **sebelum** tanggal migrasi) —
  filter tanggal ditambahkan di `@AdjustSteps`, [sp_Bundle_ScanInfo.sql](../sql/sp_Bundle_ScanInfo.sql).
- `SIS_Bundle_Manage` CREATE/UPDATE + `SIS_CuttingSpread_Manage` + `SIS_CuttingBundle_Take`:
  `root_bundle_id`, dan baris log pertama (Bundling) jadi `log_kind = 'Creation'` dengan
  `qty_delta`/`qty_after` terisi — sama rumus dengan migrasi.
- Generator serial (`MAX(CAST(RIGHT(serial,6) AS INT))`) di 3 tempat kini menyaring
  `sequence_no = 0` — tanpa itu serial anak (`B26-005742-1`) membuat `CAST` gagal.
- Tab OUT / `DikirimCount` / `OutUnlockedCount` / chip "Belum lock": baris
  `log_kind IN ('Hilang','Ketemu','Creation')` tanpa tujuan serah tidak ikut tampil
  (qty 0, tidak ada yang bisa direvisi di sana).

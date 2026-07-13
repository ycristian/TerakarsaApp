# Prompt 22 — Dashboard WIP per Divisi & Resource

Prasyarat: Prompt 17 (Bundling implisit) dan Prompt 18 (status project) sudah
dieksekusi. Modul ini murni READ-ONLY — tidak menulis apa pun ke database
selain seed module.

## Tujuan

Dashboard pemantauan WIP untuk mendeteksi bottleneck: siapa sedang memegang
bundle apa, berapa banyak, dan sejak kapan. Hanya mencakup step ber-bundle
(`requires_bundle = 1`) — step non-bundle (mis. Cutting) tidak muncul karena
alirannya berbasis qty per size, bukan bundle.

## Definisi (WAJIB konsisten dengan sp_Report_Bundle.sql)

"Log terakhir" bundle = baris `article_workflow_logs` hidup dengan `sort_order`
step terbesar, tie-break `created_at` terbesar.

- **DIKERJAKAN** di divisi D oleh resource R: log terakhir punya
  `target_division_id = D`, `received_at NOT NULL`,
  `received_by_resource_id = R` (R boleh NULL → kelompok "(Tanpa penerima)").
  Artinya: bundle sudah diterima D tapi D belum membuat log hasil kerjanya
  sendiri (kalau sudah, log itulah yang jadi log terakhir).
- **BELUM DITERIMA** di divisi D: log terakhir punya `target_division_id = D`,
  `received_at IS NULL`. Belum ada resource — agregat di level divisi saja.
- Bundle dengan log terakhir `target_division_id IS NULL` = SELESAI, tidak
  tampil.
- **Pcs** = `qty_ok` log terakhir (jumlah yang benar-benar dikirim/diterima,
  bukan qty asli bundle).
- Project dengan `manual_status` Completed/Cancelled dikecualikan seluruhnya.
  On Hold TETAP tampil (barangnya masih ada di lantai produksi).

## 1. Stored procedures — file baru `sql/sp_Report_DivisionWip.sql`

### SIS_Report_DivisionWip (tanpa parameter)

Dua result set:

1. **Dikerjakan**, agregat per (divisi, resource penerima):
   DivisionId, DivisionName, ResourceId (NULL boleh), ResourceName,
   BundleCount, TotalPcs, OldestReceivedAt, dan ArticlesJson
   (`FOR JSON PATH`: ProjectName, ArticleName, BundleCount) untuk ringkasan
   "Sedang dikerjakan" di kartu.
2. **Belum diterima**, agregat per divisi:
   DivisionId, DivisionName, BundleCount, TotalPcs, OldestSentAt
   (`created_at` log tertua), ArticlesJson (format sama).

Urutkan per DivisionName lalu ResourceName. Hanya baris hidup
(`deleted_at IS NULL`) di semua join, kembalikan nama (JOIN), bukan id mentah
untuk kolom tampilan.

### SIS_Report_DivisionWipBundles

Parameter: `@DivisionId INT`, `@Mode VARCHAR(20)` ('DIKERJAKAN' | 'PENDING'),
`@ResourceId INT = NULL` (dipakai hanya untuk mode DIKERJAKAN; NULL = kelompok
tanpa penerima — bedakan "filter tidak dipakai" vs "resource NULL" dengan
parameter tambahan `@FilterResource BIT = 0` atau pendekatan setara yang
eksplisit).

Result set (daftar bundle untuk popup): BundleId, BundleNo, Serial,
ProjectName, ArticleName, SizeName, QtyOk (pcs), TailorName
(`ISNULL(b.resource_person_name, r.resource_name)`), StepName (step log
terakhir — step yang MENGIRIM), ReceivedAt (mode DIKERJAKAN) / SentAt =
created_at (mode PENDING), ReceivedByResourceName (mode DIKERJAKAN). Urutkan
dari yang paling lama (ReceivedAt/SentAt ASC).

Validasi `@Mode` dengan RAISERROR pesan Indonesia bila nilai tidak dikenal.

## 2. Module & menu

Module baru `REPORT_WIP`, nama menu "Dashboard WIP", Category 'Order',
Route 'wip-dashboard', SortOrder 54 — seed idempotent
`sql/seed_report_wip_module.sql`, ikuti pola seed_report_bundle_module.sql
(assign ke role Admin).

## 3. API

`ReportWipController` (`api/report-wip/...`), JWT + cek module REPORT_WIP:

- GET `summary` → hasil SIS_Report_DivisionWip (dua list dalam satu DTO
  response).
- GET `bundles?divisionId=&mode=&resourceId=` → SIS_Report_DivisionWipBundles.

DTO di TerakarsaApp.Shared, satu file area (mis. `ReportWipDtos.cs`).

## 4. Client — halaman `/wip-dashboard`

Bahasa UI Indonesia. Bootstrap. Satu halaman, tanpa tab.

Layout:

- **Section per divisi** (hanya divisi yang punya minimal satu kartu):
  header = nama divisi + ringkasan "N bundle · X pcs dikerjakan" (total semua
  resource-nya).
- Di bawah header, grid kartu:
  - **Satu kartu per resource** (mode dikerjakan): nama resource, angka besar
    BundleCount + pcs, ringkasan "Sedang dikerjakan" per project—artikel
    (dari ArticlesJson, format `Project — Artikel (n)`), baris kecil
    "Terlama diterima {tanggal jam} ({umur})".
  - **Satu kartu "Belum diterima" per divisi** (bila ada), gaya warning
    (border/teks kuning): BundleCount + pcs, ringkasan artikel, baris
    "Terkirim sejak {tanggal jam} ({umur})".
- Umur dihitung di client dari sekarang: `< 24 jam` → "X jam", selebihnya
  "X hari". Bulatkan ke bawah.
- **Tombol "Lihat" di setiap kartu** → modal Bootstrap berisi tabel bundle
  dari endpoint `bundles`: Bundle No, Serial, Project, Artikel, Size, Pcs,
  Penjahit, Step asal, Diterima/Terkirim (waktu + umur). Judul modal =
  "{Divisi} — {Resource}" atau "{Divisi} — Belum diterima".
- Tombol refresh manual di atas halaman (tanpa auto-polling).
- Empty state: bila tidak ada data sama sekali, tampilkan pesan
  "Tidak ada bundle on progress saat ini."

## Yang TIDAK boleh dilakukan

- Jangan mengubah SP/endpoint/halaman yang sudah ada — modul ini murni
  tambahan read-only.
- Jangan menulis ke database selain seed module.
- Jangan tambah kolom/tabel baru.
- Jangan buat laporan periode mingguan — itu prompt terpisah berikutnya.
- Jangan tambahkan auto-refresh/polling — refresh manual saja dulu.
- Jangan buat export Excel/PDF.

Setelah selesai: daftar file dibuat/diubah + script SQL yang harus dijalankan
manual (sp_Report_DivisionWip.sql, seed_report_wip_module.sql), masing-masing
sebagai markdown link.

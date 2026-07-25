# Prompt 30 — Laporan Produksi Periode Gajian

## Konteks
Laporan produksi per divisi untuk dasar penggajian mingguan. Periode gajian = **Sabtu 10:00 → Sabtu 10:00 berikutnya** (waktu server lokal). Satu halaman: filter di atas, kartu ringkasan, lalu tab gaya station (tombol besar) — tab pertama **Semua** (agregat), tab berikutnya per pelaksana (penjahit/operator). Generik untuk semua divisi. UI bahasa Indonesia.

Baca dulu: `sql/create_tables_tmos_final.sql`, `sql/sp_WorkflowLog_Manage.sql`, `sql/sp_Article_Wip.sql`, halaman station (pola tab), halaman report WIP (Prompt 22, pola halaman report + otorisasi module).

## Definisi (kunci — jangan diubah)
Periode = `[@PeriodStart, @PeriodEnd)`. Semua query hanya baris `deleted_at IS NULL`.
Log milik divisi = `article_workflow_logs.division_id = @DivisionId`.

1. **Qty Done** = SUM `qty_ok` log milik divisi yang **sudah dikonfirmasi penerima dalam periode**:
   - `target_division_id IS NOT NULL AND received_at >= @PeriodStart AND received_at < @PeriodEnd`
   - Khusus step terakhir (`target_division_id IS NULL`, tidak ada serah-terima): pakai `created_at` dalam periode.
2. **Menunggu QC** = SUM `qty_ok` log milik divisi yang **sudah diserahkan tapi belum dikonfirmasi sampai akhir periode** (snapshot akhir periode):
   - `target_division_id IS NOT NULL AND created_at < @PeriodEnd AND (received_at IS NULL OR received_at >= @PeriodEnd)`
3. **WIP** = qty yang **sudah diterima divisi ini tapi belum dicatat hasilnya**, snapshot akhir periode. Hitung per step milik divisi:
   - Masuk = SUM `qty_ok` log step sebelumnya dengan `target_division_id = @DivisionId AND received_at < @PeriodEnd`.
   - Tercatat = SUM (`qty_ok` + ketiga `qty_reject_*`) log step ini dengan `created_at < @PeriodEnd`.
   - WIP step = Masuk − Tercatat (floor 0). Step pertama workflow tanpa serah masuk (mis. Cutting sebagai step awal) tidak punya WIP.
   - Untuk step ber-bundle, hitung per bundle (satu baris hidup per step+bundle, jadi bundle WIP = bundle yang step sebelumnya sudah diterima divisi ini tapi log step ini belum ada / dibuat ≥ `@PeriodEnd`; qty = qty masuk bundle tsb).
4. **Reject** = SUM (`qty_reject_print + qty_reject_fabric + qty_reject_sewing`) log milik divisi, timing sama dengan Qty Done (received_at dalam periode; step terakhir pakai created_at).
5. **Line / Resource** (kolom pengelompokan) = `bundles.resource_id` via `awl.bundle_id`. Log non-bundle (`bundle_id IS NULL`) masuk grup **"Tanpa Line"** (`ResourceId = NULL`). Filter Resource spesifik = hanya log dengan `bundles.resource_id = @ResourceId`.
6. **Pelaksana** (tab) = `awl.resource_id` (nama dari `resources`). NULL → tab **"Tanpa Nama"**. Atribusi **WIP per pelaksana** = `received_by_resource_id` pada log masuk (perkiraan — beri catatan kecil di UI: "WIP per pelaksana adalah perkiraan berdasarkan penerima bundle").

## 1. SQL — `sql/sp_Report_Produksi.sql` (file baru)
Read-only, tanpa `@Action`. Dua SP:

### `SIS_Report_ProduksiAgg`
Param: `@DivisionId INT`, `@ResourceId INT = NULL` (NULL = All), `@PeriodStart DATETIME2`, `@PeriodEnd DATETIME2`.
Satu result set, satu baris per **Line × PO × Article** (hanya baris yang salah satu angkanya > 0):
`LineResourceId, LineResourceName` (NULL → tampilkan "Tanpa Line"), `PoId, PoNumber, PoName, ArticleId, ArticleName, QtyDone, QtyMenungguQc, QtyWip, QtyReject`.
Urut: `LineResourceName, PoNumber, ArticleName`.

### `SIS_Report_ProduksiDetail`
Param sama. Satu result set, satu baris per **Pelaksana × PO × Article × (Bundle | Size)**:
`LineResourceId, LineResourceName, PelaksanaResourceId, PelaksanaName` (NULL → "Tanpa Nama"), `PoNumber, PoName, ArticleName, BundleId, BundleNo, BundleSerial, SizeName` (bundle: size dari bundle; non-bundle: dari `article_size_id`), `QtyDone, QtyMenungguQc, QtyWip, QtyReject`.
Urut: `LineResourceName, PelaksanaName, PoNumber, ArticleName, BundleNo`.
Baris WIP per pelaksana (dari `received_by_resource_id`, belum ada log hasil) tetap muncul sebagai baris dengan `QtyDone = 0`.

Daftar periode gajian **tidak perlu SP** — dihitung di client.

## 2. API
- `GET /api/reports/produksi?divisionId=&resourceId=&periodStart=&periodEnd=` → `{ Summary, Agg: [...], Detail: [...] }`. Summary dihitung dari hasil SP (total done, menunggu QC, WIP, reject, jumlah pelaksana dengan done > 0).
- Otorisasi module baru **`REPORT_PRODUKSI`** (pola sama `REPORT_WIP`). Tambah seed module + assignment default mengikuti pola migrasi module sebelumnya.
- Endpoint dropdown Resource: pakai endpoint list resource per divisi yang sudah ada; kalau belum ada yang cocok, tambah `GET /api/reports/produksi/resources?divisionId=` (resource hidup divisi tsb yang pernah jadi `bundles.resource_id`).

## 3. Client — halaman `/reports/produksi`
- Menu "Laporan Produksi" di grup report, tampil bila user punya `REPORT_PRODUKSI`.
- **Filter**: Divisi (dropdown, wajib), Resource (`- All -` default + daftar line divisi), Periode gajian (dropdown 12 periode terakhir, label `Sab {dd MMM} 10:00 — Sab {dd MMM} 10:00 ({yyyy})`, default = periode berjalan). Perhitungan periode di client: cari Sabtu 10:00 terakhir ≤ sekarang sebagai start periode berjalan, mundur per 7 hari. Tombol **Tampilkan** memuat data.
- **Kartu ringkasan**: Qty Done, Menunggu QC (aksen biru), WIP (warna warning), Reject (warna danger), Pelaksana Aktif.
- **Tab** gaya station (label + total done pcs di bawahnya):
  - Tab **Semua**: tabel `Resource | No PO | Nama PO | Article | Qty Done | Menunggu QC | WIP | Reject` + baris TOTAL. Kolom Resource hanya diisi baris pertama tiap line + garis pemisah antar line. Bila filter Resource ≠ All, kolom Resource disembunyikan.
  - Saat Resource = `- All -`: tab pelaksana dikelompokkan per line — sisipkan pembagi vertikal kecil berlabel nama line sebelum kelompok tab pelaksananya (urut nama line; "Tanpa Line" terakhir).
  - Tab pelaksana: tabel `No PO | Nama PO | Article | Bundle | Size | Qty Done | Menunggu QC | WIP | Reject` + baris `Total {nama}`. Bundle non-bundle log → kolom Bundle "-".
- Angka format `id-ID`. WIP > 0 warna warning, Menunggu QC > 0 warna aksen. Halaman child tidak ada; tidak perlu tombol Close.

## 4. Kriteria selesai
- Build hijau, halaman tampil sesuai mockup yang disepakati.
- Angka Done/Menunggu QC/WIP/Reject konsisten antara kartu ringkasan, tab Semua, dan penjumlahan seluruh tab pelaksana (kecuali WIP pelaksana yang berupa perkiraan — total WIP mengikuti tab Semua).
- Ganti periode/divisi/resource memuat ulang data dengan benar.
- User tanpa `REPORT_PRODUKSI` tidak melihat menu dan ditolak API (403).

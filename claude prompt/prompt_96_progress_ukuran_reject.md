# Prompt 96 — Laporan Progress per Ukuran: Rincian Reject & Hilang + Drill-down per Line

## Konteks & tujuan

Kartu **"Laporan Progress per Ukuran"** di halaman Data Project (`Pages/Project.razor`, sumber
`SIS_Report_ArticleSizeProgress` di `sql/sp_Report_Bundle.sql`) hanya menampilkan qty **OK**
(`SUM(qty_ok)`) per step × ukuran. Reject dan hilang tidak terlihat sama sekali, padahal user
perlu tahu:

1. Berapa yang reject di tiap step, **dipecah per kategori**, dan berapa yang **hilang** (terpisah).
2. Kalau mau lebih dalam: **line mana yang paling banyak** reject untuk kategori/step itu.

Sekaligus memperbaiki **dobel hitung barang Perbaikan** di kolom step tempat dia dikerjakan ulang
(lihat bagian 1b).

### Batas tegas

- Sumber angka reject/hilang **hanya** `v_bundle_reject_unified` (`sql/v_84_reject_unified.sql`).
  View itu sudah memegang batas tanggal gaya LAMA vs bundle ANAK — **jangan** menjumlah ulang dari
  kolom `qty_reject_*`/`qty_lost` atau tabel `bundles` secara mentah, dan **jangan** mengubah view-nya.
- Tidak ada perubahan tabel / kolom. Tidak perlu menyentuh `create_tables_tmos_final.sql`.
- Kolom PO, CUTTING (rumus hamparan revisi 2026-10-26), baris `%`, dan kartu Artikel/Bundle
  **tidak diubah** perilakunya (kecuali koreksi 1b yang memang menyentuh isi sel).
- Laporan lain yang memakai `qty_ok` (upah, rekap produksi, WIP, dashboard) **tidak disentuh**.
- SQL **tidak** dieksekusi oleh Claude Code — developer menjalankan manual.

---

## 0. Verifikasi dulu sebelum mengubah (WAJIB, laporkan hasilnya)

Asumsi di bagian 1b berasal dari membaca kode, belum dari data. Sebelum mengubah result set 3,
cek dan tuliskan di ringkasan akhir:

- Saat bundle anak **Perbaikan** dikirim ulang (aksi `SPLIT` di `SIS_BundleSplit_Manage` dipanggil
  untuk bundle anak itu), apakah baris log-nya berisi `qty_ok` penuh dan `bundles.status` anak
  berubah jadi `'OK'`? (lihat `sql/sp_BundleSplit_Manage.sql` sekitar langkah (2)).
- Apakah anak Perbaikan dikembalikan ke step ber-bundle **sebelum** step tempat ia dipecah
  (`@PerbaikanStepId`), sehingga `qty_ok`-nya masuk lagi ke kolom step yang dulu sudah menghitung
  pcs itu lewat induknya?
- Sertakan query cek (read-only) di `sql/query_cek_96_dobel_perbaikan.sql`: per artikel × step,
  berapa `qty_ok` yang berasal dari bundle anak (`sequence_no > 0`) di step dengan `sort_order`
  **lebih kecil** dari step kelahirannya. Ini angka yang akan hilang setelah koreksi 1b.

Kalau ternyata asumsinya salah (tidak ada dobel), **lewati 1b** dan sebutkan alasannya.

---

## 1. SQL — `sql/sp_Report_Bundle.sql` (update di tempat, `CREATE OR ALTER`)

### 1a. `SIS_Report_ArticleSizeProgress` — tambah result set 4: reject per step × kategori

Result set 1–3 tetap (urutan & kolom sama). Tambahkan **result set 4**:

```
ArticleWorkflowId INT, Category VARCHAR(20), Qty INT
```

- Dari `v_bundle_reject_unified v` JOIN `bundles b ON b.bundle_id = v.BundleId`
  WHERE `b.article_id = @ArticleId`, GROUP BY `v.ArticleWorkflowId, v.Category`, `SUM(v.Qty)`.
- Baris dengan `ArticleWorkflowId IS NULL` dikembalikan juga (UI menampilkannya sebagai
  "proses tidak diketahui" di tooltip total, bukan kolom baru).
- Tidak dipecah per ukuran — reject ditampilkan per step saja.
- Kategori: `RejectBahan | RejectJahit | RejectPrint | Perbaikan | TidakLengkap | Hilang`.
  Catatan semantik yang harus ditulis di komentar SP: `Perbaikan` dari bundle anak = yang
  **belum selesai** diperbaiki (view menyaring `status <> 'OK'`); `Hilang` gaya baru = saldo
  `missing_qty` per induk, steps-nya dari log `Hilang` terakhir.

### 1b. Result set 3 — koreksi dobel hitung bundle anak

Hanya jika bagian 0 mengonfirmasi. Aturan: baris log milik bundle **anak** (`bundles.sequence_no > 0`)
hanya dihitung `qty_ok`-nya di step dengan `sort_order >=` `sort_order` step **kelahirannya**.
Step kelahiran = `article_workflow_id` baris log induk yang membawa `split_id` pemecahan yang
melahirkan anak itu (`bundle_split_results.bundle_id = anak` → `bundle_splits` → log dengan
`split_id` tsb pada `source_bundle_id` — sama persis dengan `OUTER APPLY src` di
`v_bundle_reject_unified` cabang B). Alasannya: di step-step sebelum itu, pcs anak sudah dihitung
lewat induknya; di step kelahiran, induk hanya mencatat qty OK, jadi pcs anak belum terhitung.

- Berlaku juga untuk anak hasil `FOUND` (kind `'found'`) dan anak-dari-anak.
- Bundle induk (`sequence_no = 0`) dan baris log non-bundle tidak berubah.
- Tulis komentar revisi di atas SP (format sama dengan catatan revisi 2026-10-26 yang sudah ada).

### 1c. SP baru `SIS_Report_ArticleRejectByLine`

```
@ArticleId INT, @ArticleWorkflowId INT = NULL, @Category VARCHAR(20)
```

Dipanggil saat user klik angka di baris kategori. Atribusi:

| Kategori | Diatribusikan ke |
|---|---|
| RejectJahit, RejectPrint, Perbaikan, TidakLengkap | **Line pemilik bundle**: `bundles.resource_id` + penjahit `bundles.employee_id` dari bundle **induk** (`v.BundleId`) — bukan station yang menemukan |
| Hilang | `v.ResourceId` (pelaksana yang mencatat hilang = yang memegang barang) |
| RejectBahan | **Tidak** ke line. Kelompokkan per `v.ResourceId` dengan label "Dicatat oleh" |

Verifikasi dulu bahwa `bundles.resource_id` memang berisi Line yang mengklaim bundle (lihat
`SIS_CuttingBundle_Take` / pembuatan bundle). Kalau ternyata bukan, laporkan dan pakai kolom yang
benar — jangan menebak.

Result set:
1. **Per line**: `ResourceId, ResourceName, Qty` — urut `Qty DESC`. `ResourceId NULL` →
   "(tanpa line)".
2. **Per line × penjahit**: `ResourceId, EmployeeId, EmployeeName, Qty` — urut `ResourceId, Qty DESC`.
   Untuk Hilang & RejectBahan kosongkan (penjahit tidak relevan).
3. **Header**: `StepName, CategoryLabel, TotalQty, AttributionLabel`
   (`'Line pemilik bundle'` / `'Pemegang barang saat hilang'` / `'Dicatat oleh'`).

Validasi: `@Category` harus salah satu dari 6 kategori → `RAISERROR` pesan Indonesia.
`@ArticleWorkflowId NULL` = semua step.

---

## 2. Shared — `TerakarsaApp.Shared/Reports/ReportBundleModels.cs`

- `ArticleSizeProgressRejectDto { ArticleWorkflowId (int?), Category, Qty }`
- `ArticleSizeProgressResultDto.Rejects : List<ArticleSizeProgressRejectDto>` (default kosong).
- `ArticleRejectByLineResultDto { StepName, CategoryLabel, TotalQty, AttributionLabel,
  Lines : List<ArticleRejectLineDto>, Employees : List<ArticleRejectEmployeeDto> }`.

## 3. API

- `ReportBundleService.GetArticleSizeProgressAsync`: baca result set 4 (`NextResultAsync`).
- `ReportBundleService.GetArticleRejectByLineAsync(articleId, articleWorkflowId, category)`.
- `ArticleController`: `GET api/article/{id}/reject-by-line?stepId=&category=` — di samping
  endpoint size-progress yang sudah ada, otorisasi sama.
- Client: method baru di `ArticleApi` (service yang sama dengan `GetSizeProgressAsync`).

## 4. UI — `Pages/Project.razor`, kartu "Laporan Progress per Ukuran"

Tambahkan baris **di bawah baris "Total"**, sebelum baris `%`:

```
Total            | 42405 | 43606 | 42255 | 41890 | ...
▸ Total Reject   |    20 |    11 |    79 |    12 | ...   (merah)
    Reject Bahan |    20 |     5 |     3 |     0 |
    Reject Jahit |     – |     – |    52 |     8 |       ← tersembunyi sampai ▸ diklik
    Reject Print |     – |     – |     – |     – |
    Perbaikan    |     – |     – |    24 |     4 |       (kuning)
    Tidak Lengkap|     – |     6 |     – |     – |
  Hilang         |     0 |     0 |     4 |     0 | ...   (oranye)
%                | ...
```

- **Total Reject** = semua kategori **kecuali** Hilang. Default tertutup; klik `▸` membuka 5 baris
  kategori (state per artikel, tidak disimpan).
- Baris kategori yang **nol di semua step** tidak dirender.
- Sel nol tampil `–` (abu), bukan `0`.
- Kolom PO dan ukuran: kosong untuk baris-baris ini.
- Angka di baris kategori dan Hilang **bisa diklik** (gaya link, hanya kalau > 0) → modal
  "Reject per Line". Total Reject tidak bisa diklik (pecahannya beda atribusi).
- Kalau ada qty dengan `ArticleWorkflowId NULL`, tampilkan catatan kecil di bawah tabel:
  "N pcs reject tanpa proses tercatat".
- Warna lewat kelas CSS (tambahkan di stylesheet halaman yang sudah dipakai), bukan inline style.

### Modal "Reject per Line"

```
SEW + QC — Reject Jahit · 52 pcs
Atribusi: Line pemilik bundle

Line 3   ████████████ 28   ▾
         Siti 12 · Ani 9 · Dewi 7
Line 1   ██████ 14
Line 5   ████ 10
```

- Bar horizontal sederhana (div dengan lebar %, Bootstrap), urut terbesar; baris teratas ditandai
  "terbanyak".
- Klik line → buka daftar penjahit di line itu (hanya kategori yang punya penjahit).
- Pakai pola modal yang sudah ada di project (mis. modal line detail Prompt 45), bukan halaman baru.

---

## 5. Yang TIDAK boleh dilakukan

- Mengubah `v_bundle_reject_unified`, `SIS_BundleSplit_Manage`, atau SP laporan lain.
- Menambah kolom reject per ukuran di tabel matriks.
- Menghitung reject dari tabel mentah di luar view.
- Menjalankan SQL ke database / `dotnet run`.

## 6. Verifikasi

- `dotnet build TerakarsaApp.slnx -v q` bersih.
- Ringkasan akhir berisi: hasil pengecekan bagian 0, apakah 1b dikerjakan, daftar file
  dibuat/diubah, dan script SQL yang harus dijalankan manual (urutan: `sql/sp_Report_Bundle.sql`,
  lalu `sql/query_cek_96_dobel_perbaikan.sql` sebagai cek sebelum/sesudah).
- Uji manual yang disarankan: artikel TSHIRT LORENG PH (KODE 963) — Total Reject + Hilang per step
  harus sama dengan rekap `sql/query_cek_cacat_per_proses.sql` untuk artikel yang sama.

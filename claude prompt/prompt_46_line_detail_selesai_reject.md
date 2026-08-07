# Prompt 46 — Tab "Selesai" dan "Reject" pada Modal Detail Line

## Konteks

Prompt 45 membangun modal detail line dengan dua tab: "Per Penjahit" dan "PO Berjalan". Prompt ini menambahkan dua tab lagi ke modal yang **sama**: "Selesai" dan "Reject".

**Prasyarat:** Prompt 45 sudah selesai dan ter-deploy. Prompt ini menyentuh file yang sama (`sql/sp_Report_LineDetail.sql`, controller dan komponen modal dari Prompt 45), jadi harus dieksekusi setelahnya, bukan paralel.

Prompt ini tetap **read-only**: tidak ada aksi tulis, tidak mengubah SP/endpoint/rumus yang sudah ada.

## 1. Perubahan pada modal

- Tambahkan dua tab setelah "PO Berjalan": **"Selesai"** dan **"Reject"**. Total menjadi empat tab.
- Badge angka: Selesai = jumlah bundle selesai pada periode aktif; Reject = jumlah pcs reject. Badge Reject berwarna merah bila > 0.
- Baris konteks di header modal menyesuaikan tab aktif:
  - Selesai: periode · total pcs selesai · jumlah PO
  - Reject: periode · pcs reject dari total output · persen
- Pakai ulang komponen grup + tabel bundle yang dibuat di Prompt 45. Jangan menyalin markup baru.
- Tab "Per Penjahit" dan "PO Berjalan" tidak boleh berubah perilakunya.

## 2. Pemilih periode

Kedua tab baru punya pemilih periode di atas daftar (tab lama tidak):

- **"Hari ini"** (default) — mengikuti tanggal yang aktif di dashboard, bukan selalu hari ini
- **"7 hari"** — 7 hari ke belakang dari tanggal aktif
- **"Periode gajian"** — Sabtu 10:00 → Sabtu berikutnya 10:00, definisi **sama persis** dengan Prompt 30. Jangan bikin definisi periode baru; pakai ulang logika yang sudah ada.

Mengganti periode hanya memuat ulang tab yang aktif, tidak memengaruhi tab lain.

## 3. Tab "Selesai"

Rekap bundle yang **sudah selesai** dikerjakan di line ini, dikelompokkan per project + artikel.

**Header grup:**
- Nama project (tebal) + nama artikel + color/style
- Jumlah bundle selesai · OK (hijau) · Rjk · Hlg · sisa qty PO itu yang masih berada di line ini

**Tabel bundle per grup:**

| No Bundle | Serial | Size | Qty | OK | Rjk | Hlg | Penjahit | Selesai | Lama |

- **Selesai** = waktu bundle diserahterimakan keluar dari line ini. Format jam saja bila periode "Hari ini"; tanggal + jam bila periode lebih panjang.
- **Lama** = durasi bundle berada di line ini (`received_at` → selesai), dalam jam dengan satu desimal. Ini yang menunjukkan bundle lambat meski akhirnya kelar.
- **Hlg** = qty hilang (`qty_lost`), tepat setelah Rjk. Angka > 0 diberi warna merah, sama seperti Rjk.
- Urut dari waktu selesai terbaru ke terlama. Grup diurutkan dari OK terbesar.
- Maksimal 5 bundle per grup + baris "+ N lainnya" yang bisa diperluas, sama seperti tab PO Berjalan.
- Baris **TOTAL** di bawah seluruh grup: jumlah bundle · jumlah PO · total OK · total Rjk · total Hlg · rata-rata jam per bundle.
- Periode tanpa data: tampilkan state kosong yang ramah, bukan tabel kosong.

## 4. Tab "Reject"

Menjawab: reject terkonsentrasi di PO mana dan penjahit mana.

**Header grup:**
- Nama project (tebal) + nama artikel + color/style
- "Rjk N dari M" (N = pcs reject, M = total output PO itu di line ini pada periode tersebut) · persentase, diberi warna merah bila melewati ambang reject

**Tabel bundle per grup:**

| No Bundle | Serial | Size | Rjk | Hlg | Penjahit | Jenis | Waktu |

- Hanya bundle dengan Rjk > 0 atau Hlg > 0 yang ditampilkan.
- **Jenis** — diambil dari `log_type` (Prompt 28/29) untuk membedakan reject biasa dan hasil ADJUSTMENT. Bila `log_type` tidak menyimpan pembeda yang berguna untuk ditampilkan, **hapus kolom ini** dan jangan mengarang kategori baru.
- Urut dari Rjk terbesar ke terkecil. **Grup diurutkan dari persentase reject tertinggi**, bukan jumlah absolut — supaya PO kecil dengan reject tinggi tetap terlihat di atas.
- Maksimal 5 bundle per grup + baris "+ N lainnya".
- Baris **TOTAL**: jumlah bundle bermasalah · jumlah PO · total Rjk · total Hlg · persen terhadap total output line pada periode itu.
- Bila tidak ada reject sama sekali pada periode tersebut, tampilkan state kosong yang ramah ("Tidak ada reject pada periode ini").

## 5. Stored Procedure

Tambahkan dua SP read-only ke file `sql/sp_Report_LineDetail.sql` yang sudah dibuat di Prompt 45. Jangan bikin file SQL baru dan jangan mengubah dua SP yang sudah ada di file itu.

### SIS_Report_LineCompletedBundles
- Param: `@DivisionId INT`, `@ResourceId INT`, `@DariTanggal DATETIME`, `@SampaiTanggal DATETIME`
- Satu result set: ProjectId, ProjectName, ArticleId, ArticleName, Style, Color, BundleId, BundleNo, Serial, SizeName, Qty, QtyOk, QtyReject, QtyLost, EmployeeName, ReceivedAt, SelesaiAt.
- Kolom "Lama" dihitung di client dari ReceivedAt → SelesaiAt, bukan di SP.

### SIS_Report_LineRejectBundles
- Param sama dengan SP di atas.
- Satu result set: kolom project/artikel yang sama + BundleNo, Serial, SizeName, QtyReject, QtyLost, EmployeeName, LogType, WaktuAt, TotalOutputPo (total output PO tersebut di line ini pada periode itu, untuk menghitung persen).
- Persentase dihitung di client.

Basis perhitungan qty dan penentuan "selesai" **menyalin logika SP dashboard target harian dan `SIS_Report_LineEmployeeProgress`** — jangan bikin definisi baru.

Aturan tetap: prefix `SIS_`, filter `deleted_at IS NULL`, LEFT JOIN dengan filter deleted pada klausa `ON`, bukan `WHERE`.

## 6. API

Dua endpoint baru pada controller yang sama dengan Prompt 45, privilege modul identik:

- `GET .../line-detail/completed?divisionId=&resourceId=&periode=&tanggal=`
- `GET .../line-detail/rejects?divisionId=&resourceId=&periode=&tanggal=`

Parameter `periode` bernilai `hari` / `7hari` / `gajian`. Konversi ke rentang datetime dilakukan **di API**, bukan di client, supaya definisi periode gajian tetap satu sumber.

DTO baru diletakkan di file model dashboard target harian yang sudah ada.

## 7. Ambang reject

Tambahkan ke tempat konstanta yang sama dengan ambang mandek/penumpukan dari Prompt 45 — jangan bikin lokasi konfigurasi baru:

- **Reject tinggi**: persentase reject PO ≥ 3% → merah.

## 8. Verifikasi

- Modal menampilkan empat tab; dua tab lama tetap berfungsi persis seperti sebelumnya.
- Total OK tab "Selesai" pada periode "Hari ini" harus **sama** dengan OK baris line di dashboard.
- Total Rjk tab "Reject" pada periode "Hari ini" harus **sama** dengan Rjk baris line di dashboard.
- Total Rjk tab "Selesai" dan total Rjk tab "Reject" pada periode yang sama harus konsisten satu sama lain.
- Ganti periode: angka dan daftar berubah, tab lain tidak ikut ter-refresh.
- Periode gajian: rentang yang dipakai sama persis dengan laporan produksi Prompt 30 pada tanggal yang sama.
- Grup dengan lebih dari 5 bundle: baris "+ N lainnya" muncul dan bisa diperluas.
- Tab Reject tanpa data: tampil state kosong, bukan tabel kosong atau error.
- Ganti tanggal di dashboard lalu buka modal → "Selesai"/"Reject" periode "Hari ini" mengikuti tanggal itu.

## Yang TIDAK boleh dilakukan

- Jangan mengubah perilaku tab "Per Penjahit" dan "PO Berjalan" dari Prompt 45.
- Jangan mengubah SP, endpoint, DTO, atau rumus dashboard target harian yang sudah ada.
- Jangan membuat definisi periode gajian, status bundle, atau basis qty baru — pakai yang sudah ada.
- Jangan menambah aksi tulis apa pun di modal.
- Jangan menambah library baru.

Setelah selesai: daftar file dibuat/diubah + script SQL manual.

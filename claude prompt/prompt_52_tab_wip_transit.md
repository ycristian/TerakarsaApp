# Prompt 52 — Pisah Tab "WIP" dan "Transit" pada Modal Detail Line/Divisi

## Konteks

Modal detail line/divisi saat ini punya tab "PO Berjalan" yang mencampur dua kondisi bundle: yang sudah diterima dan sedang dikerjakan (DIKERJAKAN), dan yang masih menggantung di serah terima (TRANSIT). Dua kondisi ini punya penanggung jawab berbeda — DIKERJAKAN adalah masalah line yang mengerjakan, TRANSIT adalah masalah pihak yang belum menerima — jadi dicampur membuat keduanya sulit ditindaklanjuti.

Selain itu ada ketidakselarasan aturan yang harus diperbaiki di prompt ini. Lihat Bagian 2.

Prompt ini:
1. Mengganti nama tab **"PO Berjalan" → "WIP"**, isinya dipersempit hanya bundle DIKERJAKAN.
2. Menambah tab baru **"Transit"** khusus bundle TRANSIT.
3. Menyelaraskan **kepemilikan transit ke divisi/resource penerima**.
4. Memastikan tab **WIP, Transit, dan Reject tersedia juga di mode divisi**.

**Prasyarat:** Prompt 45, 46, dan 51 sudah selesai dan ter-deploy. Prompt ini menyentuh file yang sama, jadi dieksekusi setelahnya, bukan paralel.

Tetap **read-only**: tidak ada aksi tulis, tidak mengubah SP/endpoint/rumus dashboard yang sudah ada.

## 2. Aturan kepemilikan transit (perbaikan penting)

**Bundle transit dimiliki oleh divisi/resource TUJUAN, bukan pengirim.**

Contoh: bundle sudah diserahkan Buang Benang ke Press DTF tetapi Press DTF belum menerimanya. Bundle itu adalah transit **milik Press DTF** — karena Press DTF yang belum menjalankan penerimaan. Bukan transit milik Buang Benang.

Kondisi saat ini:
- **Kartu divisi di dashboard sudah benar** — angka "Transit" di kartu Press DTF sudah berarti "yang belum saya terima". Jangan diubah.
- **Modal masih memakai aturan lama** (transit dianggap milik pengirim). Ini yang harus diselaraskan.

Karena itu, setelah perubahan, sebuah bundle yang dikirim BB → DTF dan belum diterima:
- **tidak lagi muncul** di tab mana pun milik Buang Benang;
- **muncul** di tab Transit milik Press DTF.

Verifikasi kesesuaian ini wajib: total tab Transit harus sama persis dengan angka Transit di kartu divisi yang bersangkutan. Bila berbeda, ikuti definisi kartu dashboard — jangan bikin definisi ketiga.

**Bila serah terima tidak mencantumkan resource tujuan** (hanya divisi tujuan), bundle tersebut hanya bisa dihitung di level divisi. Dalam mode resource, kelompokkan ke satu grup penampung bernama "Belum ditentukan line" agar tidak hilang dari hitungan divisi. Laporkan bila kasus ini ternyata tidak ada di data.

## 3. Susunan tab setelah perubahan

Mode line: **WIP · Transit · Per Penjahit · Selesai · Reject · Tren · Per Jam**
Mode divisi: **WIP · Transit · Selesai · Reject · Tren · Per Jam** (Per Penjahit tetap disembunyikan)

Tab "WIP" menjadi tab default saat modal dibuka, menggantikan posisi "PO Berjalan".

Badge angka: WIP = jumlah bundle dikerjakan; Transit = jumlah bundle transit, diberi warna peringatan bila ada yang melewati ambang mandek.

## 4. Tab "WIP" (sebelumnya "PO Berjalan")

Struktur, kolom, pengelompokan per project+artikel, batas 5 bundle per grup, dan pewarnaan ambang mandek **tidak berubah** dari implementasi Prompt 45. Yang berubah:

- Nama tab menjadi "WIP".
- **Hanya menampilkan bundle berstatus DIKERJAKAN** — yaitu bundle yang sudah diterima line/divisi ini dan belum diserahkan keluar.
- Kolom "Status" **dihapus** — seluruh baris pasti DIKERJAKAN, jadi kolomnya tidak lagi membedakan apa pun.
- Kolom "Sejak" tetap memakai `received_at`.

Kolom akhir: **No Bundle · Serial · Size · Qty · Penjahit · Sejak · Umur**

## 5. Tab "Transit" (baru)

Menjawab: bundle mana yang sudah dikirim ke sini tetapi belum saya terima, dan sudah berapa lama menggantung.

Satu arah saja — **bundle yang menunggu diterima oleh line/divisi ini**. Tidak ada pemilih arah; bundle yang sudah diserahkan keluar oleh line ini bukan urusan line ini lagi, melainkan muncul di tab Transit milik step tujuan.

Struktur visual mengikuti tab WIP: dikelompokkan per project + artikel, header ringkasan, maksimal 5 bundle per grup + baris "+ N lainnya". Pakai ulang komponen grup+tabel yang sudah dibuat, jangan salin markup baru.

**Header grup:**
- Nama project (tebal) + nama artikel + color/style
- Jumlah bundle · total qty
- "Terlama N hari" — diwarnai sesuai ambang mandek

**Tabel bundle per grup:**

| No Bundle | Serial | Size | Qty | Dari | Diserahkan | Umur |

- **Dari** = divisi + resource **pengirim** (mis. "Buang Benang · Trim A2"). Ini yang dibutuhkan untuk menelusuri fisik barangnya.
- **Diserahkan** = `created_at` baris log serah terima yang belum diterima. Format tanggal pendek (dd MMM) + jam.
- **Umur** = selisih dari "Diserahkan" sampai sekarang. "N hari" bila ≥ 24 jam, "N jam" bila kurang.
- Baris melewati ambang mandek diberi latar warna tipis + angka umur berwarna tebal, sama seperti tab WIP.
- Urut dari umur terlama ke terbaru. Grup diurutkan dari yang punya bundle terlama di atas.
- Bukan laporan harian — tampilkan seluruh bundle yang saat ini berstatus transit menuju line/divisi ini, apa pun tanggalnya. Tanggal dashboard tidak memfilter tab ini.
- Bila tidak ada bundle transit, tampilkan state kosong yang ramah ("Tidak ada bundle menunggu diterima").

Baris **TOTAL** di bawah seluruh grup: jumlah bundle · jumlah PO · total qty · umur terlama.

## 6. Mode divisi

Tab WIP, Transit, dan Reject harus berfungsi penuh di mode divisi (`resourceId` kosong), mengagregasi seluruh resource divisi yang ikut hitungan dashboard.

Untuk tab Transit di mode divisi, batas transit dihitung di **batas divisi**: perpindahan bundle antar resource **di dalam divisi yang sama** tidak dihitung sebagai transit divisi. Tanpa aturan ini, angka transit divisi menggelembung oleh perpindahan internal dan tidak akan cocok dengan kartu dashboard.

Sebaliknya di mode resource, perpindahan antar resource dalam satu divisi **tetap** dihitung sebagai transit bagi resource tujuan.

## 7. Stored Procedure

Ubah dan tambah pada file `sql/sp_Report_LineDetail.sql` yang sudah ada:

### SIS_Report_LineActiveBundles (ubah)
- Persempit hanya bundle DIKERJAKAN pada line/divisi tersebut. Bundle TRANSIT tidak lagi keluar dari SP ini.
- Definisi status tetap mengikuti `sp_Report_Bundle.sql` — jangan definisikan ulang.

### SIS_Report_LineTransitBundles (baru)
- Param: `@DivisionId INT`, `@ResourceId INT = NULL`
- Mengembalikan bundle yang **menunggu diterima** oleh divisi/resource tersebut.
- Satu result set: ProjectId, ProjectName, ArticleId, ArticleName, Style, Color, BundleId, BundleNo, Serial, SizeName, Qty, AsalDivisionName, AsalResourceName, DiserahkanAt.
- Bila `@ResourceId` NULL, terapkan aturan batas divisi dari Bagian 6.
- Umur dihitung di client dari `DiserahkanAt`, bukan di SP.
- **Definisi "menunggu diterima" wajib menyalin logika yang dipakai kartu divisi dashboard** untuk angka Transit. Beri komentar penunjuk ke SP sumbernya agar tetap sinkron saat berubah.

Aturan tetap: prefix `SIS_`, filter `deleted_at IS NULL`, LEFT JOIN dengan filter deleted pada klausa `ON`, bukan `WHERE`.

## 8. API

- `GET .../line-detail/bundles?divisionId=&resourceId=` — tetap, isinya kini hanya DIKERJAKAN.
- `GET .../line-detail/transit?divisionId=&resourceId=` — baru.

DTO baru diletakkan di file model dashboard target harian yang sudah ada.

## 9. Verifikasi

- Tab "PO Berjalan" tidak lagi ada; tab "WIP" muncul di posisi pertama dan menjadi default.
- Tab WIP hanya berisi bundle DIKERJAKAN; tidak ada satu pun baris TRANSIT.
- **Uji kasus BB → DTF**: ambil satu bundle yang sudah diserahkan Buang Benang dan belum diterima Press DTF. Bundle itu harus muncul di tab Transit **Press DTF**, dan **tidak muncul** di tab mana pun milik Buang Benang.
- Total tab Transit harus **sama persis** dengan angka Transit di kartu divisi dashboard untuk divisi yang sama.
- Total WIP tab WIP harus sama dengan angka WIP baris line/divisi di dashboard.
- Mode divisi: perpindahan bundle antar resource dalam divisi yang sama tidak muncul di tab Transit divisi, tetapi muncul di tab Transit resource tujuan saat modal dibuka per line.
- Bundle transit tanpa resource tujuan masuk ke grup "Belum ditentukan line" di mode resource, dan tetap terhitung di mode divisi.
- Mode line: perilaku tab Per Penjahit, Selesai, Reject, Tren, Per Jam tidak berubah sama sekali.
- Line/divisi tanpa bundle transit: state kosong yang ramah, bukan error.
- Mode TV: baris tetap tidak bisa diklik.

## Yang TIDAK boleh dilakukan

- Jangan mengubah angka Transit di kartu divisi dashboard — itu sudah benar dan menjadi acuan.
- Jangan mengubah perilaku tab Per Penjahit, Selesai, Reject, Tren, dan Per Jam.
- Jangan mengubah SP, endpoint, DTO, atau rumus dashboard target harian yang sudah ada.
- Jangan membuat definisi status bundle atau definisi transit baru — salin dari yang sudah ada.
- Jangan menambah aksi tulis apa pun di modal (tidak ada terima, kirim ulang, atau pindah bundle).
- Jangan menambah library baru.

Setelah selesai: daftar file dibuat/diubah + script SQL manual + laporan hasil uji kasus BB → DTF.

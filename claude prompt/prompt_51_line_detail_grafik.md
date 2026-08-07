# Prompt 51 — Tab "Tren" dan "Per Jam" pada Modal Detail Line/Divisi

## Konteks

Prompt 45 membangun modal detail line (tab "Per Penjahit", "PO Berjalan"), Prompt 46 menambahkan tab "Selesai" dan "Reject". Prompt ini menambahkan dua tab grafik ke modal yang **sama**: **"Tren"** dan **"Per Jam"**, sekaligus membuat modal bisa dibuka di level **divisi**, bukan hanya level line.

**Prasyarat:** Prompt 45 dan 46 sudah selesai dan ter-deploy. Prompt ini menyentuh file yang sama, jadi harus dieksekusi setelahnya, bukan paralel.

Tetap **read-only**: tidak ada aksi tulis, tidak mengubah SP/endpoint/rumus yang sudah ada.

## 1. Modal di level divisi

Selain baris line yang sudah bisa diklik, **nama divisi di header** juga menjadi bisa diklik — baik header kartu divisi (Cutting, Bundling, dll.) maupun header tabel divisi (Sew + QC, Trim). Klik → membuka modal yang sama dalam mode divisi.

Aturan mode divisi:

- Semua angka adalah **total seluruh resource** divisi tersebut yang ikut hitungan dashboard. Jangan menumpuk garis per line di grafik; satu garis untuk total divisi.
- Tab yang **tersedia** di mode divisi: "PO Berjalan", "Selesai", "Reject", "Tren", "Per Jam".
- Tab **"Per Penjahit" disembunyikan** di mode divisi — tab itu hanya bermakna dalam konteks satu line.
- Untuk divisi yang mode tampilannya per divisi (tanpa resource), perlakuannya sama saja: `resourceId` dikirim kosong.
- Judul modal: nama divisi saja, tanpa nama line.

Secara teknis: `resourceId` menjadi opsional di seluruh endpoint modal. Bila kosong, SP mengagregasi seluruh resource divisi tersebut. Ini berlaku juga untuk endpoint dari Prompt 45 dan 46 — sesuaikan SP-nya agar menerima `@ResourceId` NULL, **tanpa mengubah perilaku saat `@ResourceId` diisi**.

## 2. Tab "Tren"

Dua bagian dalam satu tab: grafik harian di atas, tabel rekap mingguan di bawah.

### 2a. Grafik harian (bagian atas)

- Tipe: line chart, dua seri — **Terima** (garis putus-putus) dan **Qty OK** (garis penuh).
- Sumbu X: per hari. Pemilih rentang: **14 hari** (default) dan **30 hari**, dihitung mundur dari tanggal aktif di dashboard.
- Sumbu Y mulai dari nol.
- Hari tanpa aktivitas tetap muncul sebagai titik bernilai 0, jangan dilewati — libur yang hilang dari sumbu X membuat grafik menipu.
- Tooltip mode index: hover satu tanggal menampilkan kedua angka sekaligus.
- Di atas grafik, empat kartu ringkasan: rata-rata terima/hari, rata-rata OK/hari, total OK, dan selisih kumulatif terima − OK (merah bila positif, karena berarti menumpuk).

### 2b. Tabel rekap mingguan (bagian bawah)

- **10 periode gajian terakhir**, dihitung mundur dari tanggal aktif. Definisi periode: Sabtu 10:00 → Sabtu berikutnya 10:00, **sama persis dengan Prompt 30** — jangan bikin definisi baru.
- Orientasi: **metrik sebagai baris, minggu sebagai kolom**, memanjang ke kanan dengan scroll horizontal. Kolom label metrik dikunci (sticky) agar tetap terlihat saat di-scroll.
- Header kolom: kode minggu (mis. W31) di baris atas, tanggal mulai periode di bawahnya dengan warna lebih redup.
- Baris metrik, berurutan: **Terima · Qty OK · Selisih · Rjk · Rjk % · Org · org/hari**
  - **Selisih** = OK − Terima. Negatif berarti tertinggal dari beban masuk; warnai merah.
  - **Rjk %** = Rjk ÷ (OK + Rjk). Warnai merah bila melewati ambang reject dari Prompt 46.
  - **Org** = jumlah orang yang diinput PPIC untuk periode itu. Bila berbeda-beda antar hari dalam satu minggu, pakai rata-rata dibulatkan. Bila PPIC tidak input sama sekali, tampilkan "–".
  - **org/hari** = OK ÷ Org ÷ jumlah hari kerja pada periode itu. Bila Org kosong, tampilkan "–" (jangan bagi nol).
- Minggu tanpa data sama sekali tetap tampil sebagai kolom bernilai 0, jangan dilewati.

## 3. Tab "Per Jam"

Grafik output per jam pada **tanggal yang aktif di dashboard** (bukan selalu hari ini).

- Tipe: bar chart berdampingan, dua seri — **Qty OK** dan **Terima**.
- Sumbu X: jam, dari jam masuk sampai target jam pulang yang diinput PPIC untuk divisi itu pada tanggal tersebut. Bila PPIC tidak input, pakai jam kerja default.
- **Jam istirahat diarsir** dengan latar abu transparan, dan batangnya dikosongkan (null, bukan 0) — supaya jam kosong yang wajar tidak terbaca sebagai masalah.
- **Garis target per jam**: garis horizontal **putus-putus** berwarna abu melintang seluruh lebar grafik. Nilainya = target harian ÷ jumlah jam efektif (jam kerja minus istirahat).
- Bila divisi tidak punya target hari itu, garis target tidak digambar dan kartu "Target / jam" tidak ditampilkan — jangan menampilkan 0 atau angka karangan.
- Tooltip menampilkan rentang jam ("14:00 – 15:00") sebagai judul, lalu kedua angka.
- Empat kartu ringkasan di atas grafik: jam paling produktif (jam + pcs), jumlah jam tanpa output (merah bila > 0, tidak menghitung jam istirahat dan jam yang belum terlewati), rata-rata pcs/jam, dan target/jam.
- Bila tanggal aktif adalah hari ini, jam yang belum terlewati tidak digambar sebagai batang 0 — potong sumbu X di jam berjalan.

## 4. Stored Procedure

Tambahkan tiga SP read-only ke file `sql/sp_Report_LineDetail.sql` yang sudah ada. Jangan bikin file SQL baru.

### SIS_Report_LineTrendDaily
- Param: `@DivisionId INT`, `@ResourceId INT = NULL`, `@DariTanggal DATE`, `@SampaiTanggal DATE`
- Satu result set, satu baris per hari: Tanggal, QtyTerima, QtyOk.
- Hari tanpa aktivitas tetap menghasilkan baris dengan nilai 0 (gunakan tally/calendar CTE, jangan andalkan data log).

### SIS_Report_LineTrendWeekly
- Param: `@DivisionId INT`, `@ResourceId INT = NULL`, `@SampaiTanggal DATE`, `@JumlahPeriode INT = 10`
- Satu result set, satu baris per periode gajian: PeriodeMulai, PeriodeSelesai, KodeMinggu, QtyTerima, QtyOk, QtyReject, JumlahOrang, JumlahHariKerja.
- Selisih, Rjk %, dan org/hari dihitung di client, bukan di SP.
- Batas periode gajian memakai logika yang sudah ada di Prompt 30.

### SIS_Report_LineHourly
- Param: `@DivisionId INT`, `@ResourceId INT = NULL`, `@Tanggal DATE`
- Satu result set, satu baris per jam dalam jam kerja: Jam, QtyTerima, QtyOk, IsIstirahat (bit).
- Sertakan juga jam masuk, target pulang, dan target harian divisi pada tanggal itu — boleh sebagai result set kedua bila lebih rapi.

**Basis perhitungan Qty OK dan Terima wajib identik dengan SP dashboard target harian dan `SIS_Report_LineEmployeeProgress`.** Jangan bikin definisi baru; bila logikanya disalin, beri komentar penunjuk ke SP sumbernya.

Aturan tetap: prefix `SIS_`, filter `deleted_at IS NULL`, LEFT JOIN dengan filter deleted pada klausa `ON`, bukan `WHERE`.

## 5. API

Tiga endpoint baru pada controller yang sama, privilege modul identik:

- `GET .../line-detail/trend-daily?divisionId=&resourceId=&rentang=&tanggal=` (`rentang` = `14hari` / `30hari`)
- `GET .../line-detail/trend-weekly?divisionId=&resourceId=&tanggal=`
- `GET .../line-detail/hourly?divisionId=&resourceId=&tanggal=`

Parameter `resourceId` opsional di seluruh endpoint modal (termasuk endpoint Prompt 45 dan 46); kosong berarti mode divisi. Konversi rentang dan periode ke datetime dilakukan di API, bukan di client.

## 6. Grafik

Pakai library chart yang **sudah ada di proyek**. Bila belum ada satu pun, laporkan dan berhenti — jangan menambah dependensi baru tanpa keputusan (lihat konvensi: no new library dependencies unless explicitly decided).

Warna mengikuti palet yang sudah dipakai dashboard: hijau untuk OK, biru untuk Terima, abu untuk garis target dan arsir istirahat, merah untuk angka bermasalah.

## 7. Verifikasi

- Klik nama divisi di header kartu dan header tabel → modal terbuka di mode divisi, tab "Per Penjahit" tidak muncul.
- Klik baris line → modal terbuka di mode line, kelima/keenam tab muncul, perilaku tab lama tidak berubah.
- Angka OK hari terakhir pada grafik "Tren" harus **sama** dengan OK baris line/divisi di dashboard.
- Total OK tab "Per Jam" harus **sama** dengan OK baris line/divisi di dashboard pada tanggal yang sama.
- Mode divisi: total grafik harus sama dengan jumlah seluruh line divisi itu.
- Ganti rentang 14/30 hari: grafik berubah, tabel mingguan tidak ikut ter-refresh.
- Hari libur di tengah rentang tetap muncul sebagai titik 0, bukan hilang dari sumbu X.
- Divisi tanpa target hari itu: garis target dan kartu target/jam tidak muncul, grafik tetap tampil normal.
- Jam istirahat terarsir dan batangnya kosong, bukan 0.
- Tanggal aktif = hari ini: sumbu X tab "Per Jam" berhenti di jam berjalan.
- Ganti tanggal di dashboard lalu buka modal → tab "Tren" dan "Per Jam" mengikuti tanggal itu.
- Line/divisi tanpa data sama sekali: grafik kosong yang rapi dengan sumbu tetap tergambar, bukan error.

## Yang TIDAK boleh dilakukan

- Jangan mengubah perilaku tab dari Prompt 45 dan 46 saat `resourceId` diisi.
- Jangan mengubah SP, endpoint, DTO, atau rumus dashboard target harian yang sudah ada.
- Jangan membuat definisi periode gajian atau basis qty baru — pakai yang sudah ada.
- Jangan menambah aksi tulis apa pun di modal.
- Jangan menambah library chart baru tanpa keputusan eksplisit.
- Jangan menampilkan WIP di grafik mana pun — dihilangkan dari cakupan secara sengaja.

Setelah selesai: daftar file dibuat/diubah + script SQL manual.

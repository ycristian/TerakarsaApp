# Prompt 45 — Drill-Down per Penjahit pada Dashboard Target Harian

## Konteks

Dashboard Target Harian menampilkan progres per divisi dan per resource (line). Supervisor butuh melihat lebih dalam: di dalam satu line, penjahit mana yang menumpuk dan PO mana yang mandek.

Sumber penjahit: `bundles.employee_id` → tabel `employees` (Prompt 32). Fallback tampilan nama mengikuti aturan yang sudah ada: `EmployeeName` → `ResourcePersonName` → `ResourceName` → "-".

Prompt ini **read-only**: tidak menambah/mengubah data, tidak menyentuh `SIS_WorkflowLog_Manage`, `SIS_Bundle_Manage`, atau SP dashboard yang sudah ada.

## 1. Interaksi UI

Baris resource (line) pada tabel divisi di dashboard target harian menjadi bisa diklik → membuka modal detail line.

- Hanya aktif untuk pengguna dengan modul dashboard target harian. Di mode TV (`?tv=1`) baris **tidak** bisa diklik.
- Beri penanda visual bahwa baris bisa diklik (kursor pointer + hover state), jangan tambah kolom tombol baru.
- Modal punya **dua tab**: "Per Penjahit" dan "PO Berjalan". Tab "PO Berjalan" menampilkan badge jumlah bundle.
- Header modal: nama divisi + nama line (+ nama resource person bila ada) di baris atas; baris kedua berisi konteks — untuk tab Per Penjahit: tanggal, jumlah orang, OK/target line; untuk tab PO Berjalan: "Kondisi saat ini" + jumlah bundle + total qty.
- Modal mengikuti pola modal Bootstrap yang sudah dipakai di aplikasi (tutup lewat backdrop/tombol X).
- Tanggal yang dikirim ke API = tanggal yang sedang aktif di dashboard, bukan selalu hari ini.

## 2. Tab 1 — Progres per Penjahit

Target per orang tidak diinput PPIC (PPIC hanya set target per line), jadi tab ini **tidak menampilkan Target, Progress, Selisih, atau Sisa**. Fokusnya melihat penumpukan, bukan menilai target individu.

Kolom:

| Penjahit | OK | Kontribusi | org/jam | WIP | Rjk |

- **Kontribusi** = OK penjahit ÷ total OK line pada tanggal tersebut, dalam persen, ditampilkan sebagai bar + angka. Bila total OK line = 0, seluruh baris tampil 0% dengan bar kosong (jangan dibagi nol).
- Baris **TOTAL** di bawah: jumlah orang, total OK, 100%, rata-rata org/jam line, total WIP, total reject. Angka-angka ini harus sama dengan baris line di dashboard.

Aturan perhitungan:

- **Baris penjahit** = seluruh `employees` hidup yang terdaftar di line ini, digabung dengan penjahit mana pun yang punya bundle/aktivitas di line ini pada tanggal tersebut. Penjahit tanpa output tetap tampil dengan OK 0 — justru baris inilah yang paling penting, karena WIP-nya bisa besar.
- **Baris "Tanpa Penjahit"** — bundle tanpa `employee_id` (data lama) dikelompokkan di sini, jangan dibuang. Tampilkan dengan gaya italic/abu agar beda dari nama orang. Kolom org/jam diisi "–".
- **OK / Reject** — memakai basis perhitungan yang **identik** dengan dashboard divisi yang sudah berjalan (jangan bikin definisi baru), difilter per `bundles.employee_id`.
- **WIP** — bundle milik penjahit ini yang saat ini berstatus dikerjakan di divisi tersebut (definisi status mengikuti `sp_Report_Bundle.sql` — jangan definisikan ulang).
- **org/jam** — rumus sama dengan dashboard (OK ÷ jam efektif berjalan), tapi per orang tunggal, jadi tanpa pembagian jumlah orang.
- **Urutan baris**: kontribusi terendah di atas, supaya penjahit bermasalah langsung terlihat. Baris "Tanpa Penjahit" selalu diletakkan tepat sebelum TOTAL, di luar urutan.
- Beri penanda warna merah pada angka WIP yang melewati ambang penumpukan (lihat Bagian 7).
- Di atas tabel, tampilkan satu baris keterangan singkat bahwa urutan disusun dari kontribusi terendah.

## 3. Tab 2 — PO Berjalan di Line Ini

Menjawab: PO apa yang sedang jalan di line ini, dan bundle mana yang mandek sejak kapan.

Struktur: dikelompokkan per **project + artikel** (satu project dengan dua artikel = dua grup), tiap grup punya header ringkasan dan tabel bundle di dalamnya.

**Header grup:**
- Nama project (tebal) + nama artikel + color/style
- Jumlah bundle di line ini · total qty
- "Terlama N hari" — diwarnai sesuai ambang mandek (merah/kuning/normal)

**Tabel bundle per grup:**

| No Bundle | Serial | Size | Qty | Penjahit | Status | Sejak | Umur |

- **Status** — mengikuti definisi status bundle yang sudah ada (`TRANSIT` / `DIKERJAKAN`), tampilkan sebagai "Transit" / "Dikerjakan". Bundle `SELESAI` tidak ditampilkan di sini.
- **Sejak** = waktu bundle masuk status tersebut: `received_at` untuk DIKERJAKAN, `created_at` baris log untuk TRANSIT. Format tanggal pendek (dd MMM).
- **Umur** = selisih dari "Sejak" sampai sekarang: "N hari" bila ≥ 24 jam, "N jam" bila kurang.
- Baris yang melewati ambang mandek diberi latar warna tipis (merah untuk lewat ambang, kuning untuk mendekati) + angka umur ditebalkan berwarna.
- Urut dari umur terlama ke terbaru. Grup diurutkan dari yang punya bundle terlama di atas.
- Tampilkan maksimal 5 bundle per grup, sisanya diringkas jadi baris "+ N bundle lainnya" yang bisa diklik untuk memperluas grup itu.
- Cakupan tanggal: tab ini **bukan** laporan harian — tampilkan seluruh bundle yang saat ini berada di line tersebut, apa pun tanggal masuknya. Tanggal dashboard tidak memfilter tab ini.

## 4. Stored Procedure

Buat file `sql/sp_Report_LineDetail.sql` berisi dua SP read-only:

### SIS_Report_LineEmployeeProgress
- Param: `@DivisionId INT`, `@ResourceId INT`, `@Tanggal DATE`
- Satu result set: baris per penjahit — EmployeeId (NULL untuk baris "Tanpa Penjahit"), EmployeeName, QtyOk, QtyReject, Wip, JamEfektifBerjalan.
- Kontribusi persen dihitung di client dari QtyOk ÷ total, bukan di SP.
- Perhitungan qty, jendela waktu harian, dan definisi WIP **menyalin logika SP dashboard target harian yang sudah ada** — bila logika itu bisa dipakai ulang tanpa menduplikasi, lakukan; bila tidak, salin dengan komentar penunjuk ke SP sumbernya supaya tetap sinkron saat berubah.

### SIS_Report_LineActiveBundles
- Param: `@DivisionId INT`, `@ResourceId INT`
- Satu result set: baris per bundle aktif di line tersebut — ProjectId, ProjectName, ArticleId, ArticleName, Style, Color, BundleId, BundleNo, Serial, SizeName, Qty, EmployeeName, Status, SejakAt.
- Pengelompokan per project+artikel dilakukan di client dari kolom-kolom ini, jangan buat result set terpisah untuk header grup.
- Umur dihitung di client dari `SejakAt`, bukan di SP (supaya tidak basi saat modal dibuka lama).

Aturan tetap: prefix `SIS_`, filter `deleted_at IS NULL`, LEFT JOIN dengan filter deleted pada klausa `ON`, bukan `WHERE`.

## 5. API

Dua endpoint baru pada controller dashboard target harian yang sudah ada, privilege modul **sama persis** dengan endpoint dashboard tersebut:

- `GET .../line-detail/employees?divisionId=&resourceId=&tanggal=`
- `GET .../line-detail/bundles?divisionId=&resourceId=`

DTO baru diletakkan di file model dashboard target harian yang sudah ada.

## 6. Ambang penumpukan & mandek

Ambang tidak boleh di-hardcode tersebar di beberapa tempat. Simpan sebagai konstanta di satu tempat (mis. konfigurasi client atau appsettings), dengan nilai awal:

- **Bundle mandek**: umur ≥ 4 hari → merah; ≥ 3 hari → kuning; di bawah itu normal.
- **WIP penumpukan per penjahit**: di atas 3× rata-rata WIP penjahit di line yang sama → merah.

Nilai ini kemungkinan akan dipindah ke setting per divisi di prompt berikutnya, jadi pastikan mudah dipindahkan.

## 7. Verifikasi

- Klik baris line → modal terbuka dengan judul benar, dua tab berfungsi.
- Total OK dan WIP di baris TOTAL tab "Per Penjahit" harus **sama** dengan angka baris line di dashboard. Bila berbeda, berarti basis perhitungannya menyimpang — perbaiki, jangan biarkan.
- Bundle tanpa `employee_id` masuk ke baris "Tanpa Penjahit" dan ikut terhitung di TOTAL.
- Line dengan total OK 0: kolom Kontribusi tampil 0% semua, tidak error pembagian nol.
- Line tanpa aktivitas: modal tetap terbuka dengan tabel kosong yang rapi, bukan error.
- Grup dengan lebih dari 5 bundle: baris "+ N lainnya" muncul dan bisa diperluas.
- Mode TV: baris tidak bisa diklik.
- Ganti tanggal di dashboard lalu buka modal → tab "Per Penjahit" ikut tanggal itu, tab "PO Berjalan" tetap menampilkan kondisi saat ini.

## Yang TIDAK boleh dilakukan

- Jangan mengubah SP, endpoint, DTO, atau rumus dashboard target harian yang sudah ada.
- Jangan menambah kolom Target/Progress/Selisih di tab per penjahit — target per orang belum ada sumbernya.
- Jangan menambah aksi tulis apa pun di modal (tidak ada edit, hapus, atau pindah bundle).
- Jangan membuat definisi status bundle atau basis qty baru — pakai yang sudah ada.
- Jangan menambah library baru.

Setelah selesai: daftar file dibuat/diubah + script SQL manual.

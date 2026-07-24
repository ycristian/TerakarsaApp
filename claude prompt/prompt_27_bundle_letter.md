# Prompt 27 — Kode Huruf Bundle per Project (bundle_letter)

## Konteks

`bundle_no` reset per project, jadi antar project ada nomor kembar (Project X dan Y sama-sama punya No. 1, 2, 3) — membingungkan di lapangan. Solusi: setiap project mendapat **satu huruf** (A → B → ... → Z → kembali ke A). Tampilan nomor bundle menjadi `{huruf}-{bundle_no}`, mis. `B-27`. Logika `bundle_no` sendiri TIDAK berubah.

Keputusan yang sudah disepakati:
- Huruf melekat di **project** (kolom baru di `projects`), naik setiap project baru dibuat.
- Setelah Z kembali ke A — duplikasi setelah 26 project diterima (project lama sudah selesai saat huruf berputar).
- Nomor tetap reset per project seperti sekarang (`A-1...`, project berikutnya `B-1...`).
- Backfill: semua project **aktif** (hidup, bukan COMPLETED/CANCELLED) diberi huruf sekarang, urut `created_at`. Project selesai/batal/terhapus dibiarkan tanpa huruf — bundle mereka tampil angka saja. Label fisik lama tidak berubah.

## 1. Skema SQL

a. Di `sql/create_tables_tmos_final.sql`, tabel `projects`: tambah `bundle_letter char(1) null` dengan komentar "kode huruf bundle per project (A-Z berputar), generate di SIS_Project_Manage; NULL = project lama tanpa huruf".

b. Buat `sql/alter_27_bundle_letter.sql` (idempotent):
   1. `ALTER TABLE projects ADD bundle_letter char(1) NULL;` (cek kolom belum ada)
   2. Backfill hanya project dengan `deleted_at IS NULL` dan `manual_status` bukan COMPLETED/CANCELLED, urut `created_at, project_id`:
      `bundle_letter = CHAR(65 + ((ROW_NUMBER() - 1) % 26))`.
      Hanya sentuh baris yang `bundle_letter IS NULL` (aman dijalankan ulang).

Tidak perlu unique — huruf memang berulang setelah 26 project.

## 2. Stored Procedures

### SIS_Project_Manage (CREATE)
- Di dalam applock (lock baru mis. `project_bundle_letter`, exclusive, scoped transaksi): ambil huruf project ber-huruf terakhir (`MAX(project_id)` yang `bundle_letter IS NOT NULL`, termasuk yang deleted — huruf tidak dipakai ulang), huruf baru = huruf berikutnya; Z → A; belum ada sama sekali → A. Simpan di INSERT.
- UPDATE/DELETE tidak menyentuh `bundle_letter`.

### SIS_Bundle_Manage & SIS_Bundle_ReprintLabel
- Logika generate `bundle_no` TIDAK berubah.
- Payload `print_jobs` (BUNDLE_LABEL): tambah field `bundle_letter` (string, boleh null).

### SP Select
Semua SP yang mengembalikan `bundle_no`, tambahkan kolom `BundleLetter` (dari project via JOIN yang sudah ada): `SIS_Bundle_ListByArticle`, `SIS_Article_BundleSummary`, `SIS_Bundle_ScanInfo`, `SIS_Station_PendingReceives`, `SIS_Station_InProgress`, `SIS_Station_Outbound`, `SIS_Report_Bundle*`, SP packing/surat jalan yang menampilkan bundle_no, dan SP lain yang relevan (cari `bundle_no` di folder sql).

## 3. API & Client

- Shared: tambah `BundleLetter` (string?, nullable) di model yang punya `BundleNo`; payload `BundleLabelPayload` juga.
- Buat satu helper format di Client (mis. extension/static `BundleDisplay(letter, no)` → `"B-27"` atau `"27"` bila letter null) dan pakai di SEMUA tempat bundle_no tampil: daftar kelola bundle, pesan sukses ("Bundle B-27 dibuat"), kartu scan, tab station (Masuk/Dikerjakan/Dikirim), laporan, packing. Jangan format manual berulang di tiap halaman.

## 4. PrintService (TSPL, label 6×4)

- Elemen terbesar berubah dari `"No. 27"` menjadi `"No. B-27"` bila `bundle_letter` terisi; tanpa huruf tetap `"No. 27"`. Pastikan lebar teks 6 karakter (mis. `No. Z-999`) tetap muat rata kanan tanpa menabrak kolom QR.
- Elemen lain tidak berubah.

## Yang TIDAK boleh dilakukan

- Jangan ubah format `serial`, isi `qr_content`, atau logika generate `bundle_no`.
- Jangan buat mekanisme pakai-ulang huruf atau lompatan huruf.
- Jangan beri huruf ke project COMPLETED/CANCELLED/terhapus saat backfill.
- Jangan ubah alur station/log di luar penambahan kolom tampilan.

## Verifikasi

1. `dotnet build` sukses.
2. Setelah `alter_27` dijalankan: project aktif lama punya huruf urut created_at; project selesai tetap NULL.
3. Buat project baru → dapat huruf lanjutan; buat 2 bundle → tampil `X-1`, `X-2` di daftar, pesan sukses, dan scan card.
4. DryRun print: file .tspl memuat `No. X-1`.
5. Di akhir: daftar file diubah/dibuat + script SQL yang harus dijalankan manual.

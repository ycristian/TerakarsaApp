# Prompt 75 — Stok Benang: Riwayat & Review Log, Ringkasan Landing, Export

Dijalankan SETELAH Prompt 74.

## 1. SP baca — `sql/inv/sp_75_ThreadReport.sql`

- `inv.SIS_ThreadMovement_List` — paged; filter: rentang tanggal (default 7 hari), movement
  type (multi), reason_code, thread_item_id, location (from/to), resource_id, project_id,
  created_by. Kolom: tanggal, tipe, SKU (nama·kode warna·merk), kones/berat, dari → ke,
  line, project, alasan, keterangan, user, opname session_no (join lewat opname_line).
- `inv.SIS_ThreadStock_Summary` — untuk landing: total SKU aktif, total kones whole, total
  split (count + gram), kones split ISSUED (di line), movement hari ini per tipe, sesi
  opname OPEN (kalau ada), 5 SKU dengan stok whole terkecil yang masih punya movement ISSUE
  dalam 30 hari (sekadar peringatan, bukan stok minimum).
- `inv.SIS_ThreadStock_ByLocation` — matriks lokasi × jumlah SKU/kones (halaman lokasi).
- `inv.SIS_ThreadUsage_ByProject` — pemakaian benang per project dalam rentang tanggal:
  per SKU, total kones whole ISSUE + gram split ISSUE_SPLIT − RETURN (kembali dari project
  itu). Angka gram ekuivalen whole tidak perlu dikonversi.

## 2. API

`GET movements` (paged, filter), `GET summary`, `GET stocks/by-location`,
`GET usage/by-project`, `GET movements/export` (Excel, ClosedXML, kolom sama dengan list,
tanpa paging, maks 10.000 baris).

## 3. Client

**Baca dulu** `claude prompt/benang/mockup/TabletBeranda.dc.html`: bagian "Riwayat
terakhir" (tabel tanggal · tipe berwarna · uraian · user · ±qty) dan tiga kartu ringkasan
(Whole / Split / Dipakai di line) adalah arahan untuk halaman riwayat dan ringkasan landing.

| Route | Isi |
|---|---|
| `/gudang/benang/riwayat` | Filter bar (tanggal, tipe chips, alasan, SKU, lokasi, line, project, user), tabel movement. Tipe diberi warna: ISSUE hijau tua, RETURN oranye, MOVE abu, ADJUST merah, RECEIVE biru. Baris ADJUST menampilkan alasan tebal. Klik baris → detail (termasuk link ke sesi opname). Tombol **Export Excel**. Tablet: tabel penuh; HP: kartu per baris seperti riwayat di mockup `TabletBeranda.dc.html` bagian bawah. |
| `/gudang/benang` (landing, perbarui) | Di atas daftar SKU tambahkan ringkasan: kartu Whole / Split / Di line, kartu "Hari ini: n ambil · n kembali", kartu opname berjalan. Tablet: ringkasan di panel kanan saat belum ada SKU dipilih. |
| `/gudang/benang/pemakaian` | Pemakaian per project: pilih rentang + project → tabel SKU & jumlah, Export Excel. |

## 4. Review oleh owner

Semua halaman di atas memakai module `INV_THREAD` yang sama — owner (Admin) sudah bisa
akses. Tidak perlu module terpisah.

## 5. Verifikasi

Build; buka riwayat dengan filter tipe ADJUST menampilkan kolom alasan; export menghasilkan
file .xlsx.

## Yang TIDAK boleh dilakukan

- Tidak ada SP tulis di prompt ini.

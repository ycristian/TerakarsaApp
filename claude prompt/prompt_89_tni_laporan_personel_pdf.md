# Prompt 89 — PDH TNI AD: Laporan Personel & Status Packing (PDF A4, unduh)

> Module PDH TNI AD. Aturan module: CLAUDE.md bagian "Module PDH TNI AD"
> (schema `tni`, SP `tni.SIS_…`, UI bahasa Indonesia, kode bahasa Inggris).
> Mockup PDF: `claude prompt/tni/mockup_laporan_personel_a4.html` — ikuti
> susunannya **persis**.

## Konteks

Halaman `/tni/personel` sekarang menampilkan daftar personel sesuai filter
(satuan / rawatan / status / kata kunci). Owner butuh **laporan PDF A4** dari
daftar itu, yang bisa diserahkan ke Kodam: siapa saja personelnya, statusnya
saat laporan dicetak, dan **ada di box nomor berapa**.

PDF **hanya diunduh** dari HP/PC, seperti PDF isi box (Prompt 67). Tidak lewat
print job, tidak disimpan ke disk, tidak menyentuh PrintService.

## 1. SQL — `sql/tni/sp_LaporanPersonel.sql`

`tni.SIS_LaporanPersonel` — parameter **sama persis** dengan SP yang dipakai
daftar `/tni/personel` sekarang (baca SP-nya dulu; biasanya `@OrderId`,
`@AreaId`, `@SatuanId`, `@Status`, `@Cari`), tanpa paging. 3 result set:

1. **Header** — judul order, nama area (bila difilter), nama satuan (bila
   difilter), total baris. Tidak ada ringkasan status.
2. **Baris personel** urut `satuan_code, kode_ref`: `kode_ref, satuan_code,
   satuan_name, pangkat, nama, nrp, no_hp, gender, pola_kemeja_kode, pola_celana_kode, box_no, box_code` (box NULL
   bila belum masuk box; `box_no` = nomor urut box yang sudah ada di tabel
   box). Box dari `tni.v_personel` — **jangan** menulis ulang logika status.
3. **Rekap box** lingkup itu: `box_no, box_code, gabungan (bit), status, isi,
   isi_dari_lingkup` (jumlah personel lingkup ini di dalam box — beda dari
   `isi` hanya untuk box gabungan), `packed_at, shipped_at`. Urut status
   Terkirim → Tertutup → Terbuka, lalu `box_code`.

ANSI_NULLS / QUOTED_IDENTIFIER ON (tabel tni punya filtered index).

## 2. API

- `TerakarsaApp.Shared/Tni/TniLaporanPersonelModels.cs`.
- `TniLaporanPersonelPdfService` — **SkiaSharp** (`SKDocument.CreatePdf`), pola
  yang sama dengan `TniBoxPdfService`; jangan menambah library PDF.
- `TniPersonelController`: GET `api/tni/personel/laporan-pdf` dengan query
  string yang sama dengan endpoint daftar (`areaId, satuanId, status, cari`),
  module `TNI_PDH`. Balasan `application/pdf`, nama file:
  - satu satuan → `Laporan_{satuan_code}_{yyyyMMdd-HHmm}.pdf`
  - satu area → `Laporan_{area_code}_{yyyyMMdd-HHmm}.pdf`
  - lainnya → `Laporan_Personel_{yyyyMMdd-HHmm}.pdf`
- Batas: bila baris > **2.000**, balas 400 "Terlalu banyak baris (n). Persempit
  filter (satuan/rawatan/status)." Angka ini jadi konstanta, bukan setting.

### Susunan PDF (A4 **landscape**, margin ±10 mm, Arial / fallback sans-serif)

Landscape karena kolomnya 11–12; kalau portrait, NRP dan No HP tidak muat.

Ikuti mockup. Ringkasnya:

1. **Kepala (hanya halaman 1)**: kiri "LAPORAN PERSONEL & BOX",
   judul order besar navy, baris filter ("Rawatan X · Satuan Y", atau "Rawatan X
   · Semua satuan (n orang) · Status Z", atau "Seluruh Kodam · n orang ·
   Pencarian \"…\""). Kanan: tanggal-jam cetak (lokal, format
   `dddd, d MMM yyyy · HH:mm` Indonesia) dan "Data per saat cetak". **Tanpa**
   nama pencetak. Garis tebal navy. **Tidak ada ringkasan progres** — langsung
   tabel.
2. **Tabel**: No · Kode · Pangkat · Nama · NRP · **No HP** · **Gender**
   (Pria/Wanita) · Kemeja · Celana · **No. Box** (`#` + box_no, rata tengah) · **Kode Box**. **Tidak ada
   kolom status.**
   Bila lingkup mencakup **lebih dari satu satuan**, sisipkan kolom **Satuan**
   setelah Kode. Kode, No. Box & Kode Box monospace tebal; kode pola monospace.
   Baris yang **belum masuk box** ditulis abu-abu dengan No. Box dan Kode Box
   "—". Header tabel diulang tiap halaman. Target ±28 baris per halaman penuh (landscape).
3. **Setelah baris terakhir**: dua kotak berdampingan — kiri **Rekap box**
   (Box · Status · Isi · Ditutup/dikirim; box gabungan ditandai "Gabungan" dan
   isinya ditulis "n dari lingkup ini"), kanan tanda tangan **Diserahkan
   oleh** dan **Diterima oleh (satuan)** masing-masing dengan garis Nama /
   tanggal. Kalau tidak muat di sisa halaman, pindah ke halaman baru.
   Di bawahnya catatan kecil: "Data mengikuti kondisi sistem saat laporan
   dicetak. Personel yang belum masuk box ditulis abu-abu dengan No. Box —.
   No. Box = nomor urut box di satuannya, Kode Box = kode di kardus."
4. **Kaki tiap halaman**: kiri "Dicetak dari Terakarsa · data per {tgl jam}",
   kanan "{satuan_code atau area_code atau judul order} · hal x/y".

## 3. Client — `/tni/personel`

- Tombol **⬇ Laporan PDF** di baris yang sama dengan tombol Filter (kanan,
  menggantikan posisi teks "n orang" — pindahkan teks itu ke dalam tombol atau
  ke bawah filter). Nonaktif saat daftar kosong.
- Klik → konfirmasi singkat bila baris > 300: "Laporan n orang ≈ m halaman.
  Lanjutkan?" (m = ceil(n / 28) + 1). Di bawah 300 langsung unduh.
- Unduh memakai pola yang sudah ada (`GetPdfAsync` + `downloadFileFromBytes`).
  Tampilkan spinner di tombol selama proses, toast "Laporan {nama file}
  diunduh.", dan pesan 400 dari API apa adanya.
- Kirim **filter yang sedang aktif** persis seperti yang dipakai memuat daftar.

## Verifikasi

1. Filter satu satuan (±90–120 orang) → PDF landscape ±4 halaman: kepala di
   halaman 1, header tabel berulang, rekap box + tanda tangan di akhir; No HP
   dan Gender terisi sesuai data import.
2. Filter rawatan + status "Masuk box" → hanya baris masuk box; kolom Satuan
   muncul; No. Box dan Kode Box terisi semua.
3. Personel di box gabungan menampilkan kode box gabungannya; rekap box
   menulis "n dari lingkup ini".
4. Filter tanpa batas di order 7.279 orang → 400 dengan pesan persempit filter.
5. Nama file sesuai aturan; `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan membuat print job, jangan menyentuh PrintService / `print_devices`.
- Jangan menyimpan PDF ke disk.
- Jangan menambah library PDF selain SkiaSharp.
- Jangan mengubah SP/endpoint daftar personel yang ada — tambah SP baru.
- Jangan menulis ulang logika status; pakai `tni.v_personel`.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi + satu
contoh PDF hasil uji (satu satuan), sebagai markdown link.

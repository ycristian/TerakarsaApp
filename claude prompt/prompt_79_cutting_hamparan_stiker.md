# Prompt 79 — Module Cutting: Buat Hamparan, Daftar/Detail Hamparan, Stiker QR

Lanjutan Prompt 78. Baca `claude prompt/cutting/module-cutting-keputusan-desain.md` dan mockup layar 2, 3, 4 di `claude prompt/cutting/mockup/`.

## 1. Buat Hamparan (`/cutting/hamparan/baru`) — mockup layar 2

Kolom kiri:
- **Artikel / PO** dropdown: tampil `<PO> · <nama artikel>`, hanya artikel aktif.
- **Kode hamparan**: otomatis `H` + urut 2 digit per artikel (hamparan terakhir artikel + 1), boleh diganti; validasi unik per artikel.
- **Tanggal hampar** (default hari ini), **Jumlah set**, **Lembar per set**. Tampilkan total `set × lembar` pcs.
- **Rincian set per size**: baris per size artikel (ambil daftar size dari tempat yang ditemukan di inspeksi Prompt 78). Input set per size; kolom Pcs dan rentang numbering (`<size>-<from> s/d <size>-<to>`) dihitung live dari `SIS_Cutting_NextNumber`. Indikator "n / N set terisi"; tombol simpan terkunci kalau belum pas.

Kolom kanan — **Pembagian bundle**:
- Judul "Saran sistem · target X pcs/bundle (dari artikel)" dan ringkasan `lembar → n bundle × qty`.
- Satu baris per **set** (Size · Set ke- · input qty per bundle · Total · tombol +). Saran dari `SIS_Cutting_SuggestBundles` diisi sama untuk semua set; user boleh edit per set. Baris yang totalnya ≠ lembar diberi latar kuning dan angka merah; tombol simpan terkunci.
- Catatan aturan di bawah tabel (teks seperti mockup).
- Bar bawah: "Akan dibuat N bundle · M pcs", preview rentang kode (`H07-M-01 … H07-M-24, H07-L-01 … H07-L-24`), tombol **Simpan draft** dan **Simpan & cetak N stiker**.

Simpan:
- Satu panggilan API → `SIS_Spread_Manage CREATE` (header, sizes, semua bundle dengan `source=CUTTING`, `stock_status=STOCK`, kode, `set_no`, `bundle_seq`, `number_from/to`).
- Penomoran bundle: urut per spread per size, set 1 dulu (01..k), lanjut set 2, dst. `number_from` bundle = lanjutan dalam set; set berikutnya lanjut dari set sebelumnya di size yang sama.
- "Simpan & cetak" → setelah CREATE, enqueue print job untuk semua bundle (§3) dan `MARK_PRINTED`. "Simpan draft" → status DRAFT, tanpa cetak.
- Setelah simpan, arahkan ke Detail Hamparan.

## 2. Daftar & Detail Hamparan

- `/cutting/hamparan`: daftar hamparan (kode, PO · artikel, tanggal, set × lembar, bundle, STOCK/TAKEN, status DRAFT/PRINTED). Filter artikel + status. Tombol "+ Buat Hamparan".
- `/cutting/hamparan/{id}` — mockup layar 3:
  - Header: kode · PO · artikel, chip status (DRAFT abu / Sudah dicetak hijau), tombol **Cetak ulang semua** (DRAFT → tombolnya "Cetak semua").
  - 5 kartu: hampar, total, di stok cutting, diambil, dibuat (tanggal · nama).
  - Filter chip: Semua / per size / Masih di stok.
  - Tabel bundle: Kode · Set · Nomor (`M-111 – M-165`) · Qty · Status (chip "Stok cutting" hijau; "Diambil" abu + `line · tanggal jam`; badge kecil "perlu cetak ulang" kalau `needs_reprint`) · tombol Edit & Cetak.
  - **Edit** qty → modal angka; panggil `SIS_SpreadBundle_Manage UPDATE_QTY`; tolak dengan pesan SP kalau tidak boleh. Tombol Edit nonaktif (abu) untuk bundle TAKEN. Tambah/hapus bundle di set: tombol kecil di modal yang sama (ADD/REMOVE).
  - **Cetak** per bundle → enqueue satu job, reset `needs_reprint=0`.
  - **Hapus hamparan** (menu ⋯ di header): hanya jika tidak ada bundle TAKEN; soft delete; konfirmasi.
  - Teks catatan di bawah tabel seperti mockup.

## 3. Stiker bundle (mockup layar 4)

- Pakai antrian print job yang sudah ada untuk stiker penyerahan bundle (job type baru `CUTTING_BUNDLE_LABEL`, printer & ukuran label mengikuti job stiker penyerahan bundle — periksa builder TSPL yang ada dan buat varian baru, jangan ubah yang lama).
- Isi: kode bundle (besar), `<PO> · <artikel>`, Size / Qty / Set, "Nomor M-111 s/d M-165", baris kecil `Hamparan H06 · <tanggal> · Cutting`, **QR** di kanan. Isi QR = **format QR bundle yang sudah dipakai sistem** (hasil inspeksi Prompt 78), supaya scanner station bundle langsung mengenali. Di bawah QR cetak kode bundle kecil.
- Cetak semua = satu job per bundle, urut kode.

## 4. API

Endpoint di `CuttingController`: `GET articles` (dropdown + target), `GET next-number`, `POST suggest`, `POST spreads` (create, flag `print`), `GET spreads`, `GET spreads/{id}`, `PUT spreads/{id}/bundles/{bundleId}/qty`, `POST …/bundles` (ADD), `DELETE …/bundles/{bundleId}` (REMOVE), `POST spreads/{id}/print` (semua / `bundleIds`), `DELETE spreads/{id}`.

## 5. Verifikasi
- Build lolos. Uji alur: buat hamparan 12 set × 220 (6 M, 6 L) target 50 → 48 bundle, kode & rentang nomor benar, hamparan kedua artikel sama lanjut dari M-1321. Edit satu bundle di set 2 jadi 60 → SP tolak (total ≠ 220); ubah dua bundle 60 & 50 → diterima, rentang bergeser, `needs_reprint` benar.
- Laporan akhir: ringkas + "Catatan".

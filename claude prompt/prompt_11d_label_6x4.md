# Prompt 11d — Revisi Label Bundle ke 6×4 cm

## Konteks

Label bundle pindah dari 10×5 cm ke stok label **6×4 cm**. Hanya menyentuh perakitan TSPL di TerakarsaApp.PrintService — payload, SP, API, dan isi QR TIDAK berubah.

## Tugas: ubah layout TSPL BUNDLE_LABEL di PrintService

Setup: `SIZE 60 mm, 40 mm`, `GAP 3 mm, 0`, `DIRECTION 1`, `CLS`, `PRINT 1,1`.

Komposisi (koordinat dalam dot, 8 dot/mm — 480 × 320 dot):

**Kolom kiri:**
- QR code dari `qr_content`: level M, target ukuran fisik ± 23 mm (pilih cell size yang menghasilkan mendekati itu), posisi kiri ± x=24, y=72, sisakan quiet zone ± 2 mm.
- Tepat di bawah QR: `serial` font kecil, rata tengah terhadap QR (teks cadangan bila QR rusak).

**Kolom kanan (mulai ± x=250):**
- Kanan atas: `project_name` font kecil, rata kanan, uppercase, potong maks 22 karakter.
- Di bawahnya: `"No. " + bundle_no` — **elemen paling besar di label** (font terbesar yang tersedia + pembesaran, target tinggi ± 10–11 mm), rata kanan.
- Garis pemisah horizontal.
- Baris size & qty: `size_name` besar di kiri kolom, `qty + " pcs"` sedang rata kanan.
- Garis pemisah horizontal.
- `article_name` font sedang, potong maks 20 karakter.
- `style` + " · " + `color` font kecil, potong maks 24 karakter.
- Baris terbawah font terkecil: nama step pertama tidak perlu — cukup tanggal cetak (dd/MM) + `"Line "` + nama resource bila ada di payload.

Aturan pemotongan teks: potong dengan "…" bila melebihi batas; jangan biarkan teks menabrak kolom QR.

## Verifikasi

- DryRun = true: buat 1 bundle → periksa file .tspl: SIZE 60 mm, semua elemen dalam batas 480×320 dot.
- Uji nilai panjang: article_name 40 karakter dan qty 4 digit tidak tumpang tindih.

## Yang TIDAK boleh dilakukan

- Jangan ubah payload, SP, endpoint, atau isi/format `qr_content`.
- Jangan ubah penanganan job_type lain.

Setelah selesai: daftar file yang diubah.

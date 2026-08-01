# Prompt XX — Mode TV & Pemadatan Tampilan Dashboard Target Harian

## Konteks

Dashboard Target Harian sudah jalan. Masalahnya saat ditampilkan di TV di line jahit:

- Tiap baris line makan tinggi berlebihan karena persen progres diletakkan **di bawah** progress bar (jadi dua baris) — akibatnya hanya ~8 line yang muat, sisanya kepotong.
- Font terlalu kecil dan warna abu terlalu muda untuk dibaca dari jarak 3–5 meter.
- Kartu divisi yang belum di-set target tingginya sama dengan kartu bertarget, memakan ruang percuma.
- Navbar, sidebar, dan datepicker ikut tampil di TV padahal tidak dipakai.

Prompt ini **hanya menyentuh presentasi**. Tidak ada perubahan SP, API, DTO, atau logika perhitungan.

## Tugas

### 1. Mode TV via query string

Halaman dashboard target harian menerima parameter `?tv=1`.

Saat `tv=1` aktif:

- Sembunyikan navbar, sidebar, breadcrumb, dan datepicker — halaman render full-bleed tanpa layout aplikasi.
- Tanggal dikunci ke hari ini (abaikan parameter tanggal bila ada).
- Halaman tidak boleh scroll: `overflow: hidden` pada container utama, semua konten harus muat dalam satu viewport.
- Auto-refresh tetap berjalan seperti sekarang; indikator "Update terakhir HH:mm" tetap tampil di header, ukuran kecil.

Saat `tv=1` tidak ada: tampilan tetap seperti sekarang (layout aplikasi normal, datepicker aktif, boleh scroll).

Implementasikan dengan satu CSS class pembungkus (mis. `tv-mode`) sehingga aturan ukuran di bawah hanya berlaku di mode TV dan tidak mengganggu tampilan desktop.

### 2. Pemadatan baris tabel line

- Pindahkan angka persen dari bawah progress bar ke **sejajar di kanan bar** dalam satu baris flex. Bar `flex: 1`, angka persen lebar tetap (mis. `min-width: 3.5ch`, rata kanan).
- Kunci tinggi tiap baris tabel agar seragam dan tidak melar mengikuti isi.
- Hapus padding vertikal berlebih pada sel tabel.
- Nama line dan nama operator digabung dalam satu sel: kode line tebal, nama operator lebih kecil dan abu di sampingnya (mis. **A1** Heru).
- Progress bar dikunci maksimum 100% lebar visualnya walau nilai persen melebihi 100 — angka persennya tetap ditampilkan apa adanya.

### 3. Kolom yang tampil di mode TV

Di mode TV, tampilkan hanya: **Line · Org · OK · Target · Progress · Selisih**.

Sembunyikan kolom `org/jam` dan `Sisa` (tetap tampil di mode non-TV). Jangan hapus datanya dari model — cukup sembunyikan kolomnya.

### 4. Kartu divisi

- Kartu divisi yang **belum di-set target**: tampilkan versi ringkas — nama divisi, angka OK besar, dan WIP/Reject kecil di kanan. Tanpa progress bar, tanpa baris selisih, tanpa jam kerja.
- Ganti badge pill "Belum di-set" menjadi teks kecil abu di kanan atas kartu, sejajar dengan nama divisi.
- Kartu divisi yang **sudah di-set target**: susunan tetap, tapi dipadatkan — nama divisi + jam kerja + jumlah orang di baris atas, angka OK / target dan persen besar di baris kedua, progress bar, lalu baris selisih + sisa.
- Samakan penulisan nama divisi (jangan campur UPPERCASE dan Title Case) — pakai satu gaya konsisten.

### 5. Ukuran font responsif terhadap layar

Di mode TV, jangan pakai ukuran font px tetap. Pakai satuan relatif viewport (`vh` atau `clamp()`) agar ikut membesar pada layar TV besar. Panduan proporsi:

- Judul halaman & nama divisi pada kartu: paling besar setelah angka utama
- Angka OK pada kartu divisi: elemen terbesar di kartu
- Nama line, OK, target, selisih pada tabel: satu tingkat di atas ukuran sekarang
- Header kolom tabel dan teks WIP/Reject: paling kecil

Ketentuan keterbacaan jarak jauh:

- Angka (OK, persen, selisih) pakai bobot font tebal.
- Ganti warna teks abu muda menjadi abu lebih gelap — abu muda tidak terbaca dari jarak jauh.
- Warna status tetap: hijau surplus, kuning defisit <10%, merah defisit ≥10%, abu untuk bar "seharusnya".

### 6. Target: 10 line per divisi muat penuh

Pastikan divisi dengan 10 line tampil seluruhnya tanpa scroll pada layar 1920×1080. Bila jumlah line melebihi kapasitas layar, perkecil tinggi baris secara proporsional — jangan munculkan scrollbar dan jangan potong baris.

## Verifikasi

- Buka `?tv=1` pada 1920×1080: tidak ada scrollbar, semua divisi dan 10 line per divisi tampil penuh.
- Buka tanpa `tv=1`: layout aplikasi normal, datepicker berfungsi, kolom `org/jam` dan `Sisa` kembali muncul.
- Divisi tanpa target: kartu ringkas tampil, tidak ada bar kosong atau baris selisih.
- Line dengan progres >100%: bar mentok di 100%, angka persen tetap menampilkan nilai aslinya.
- Nilai panjang (OK 5 digit, selisih 4 digit + persen 3 digit) tidak membuat kolom melar atau teks terpotong.

## Yang TIDAK boleh dilakukan

- Jangan ubah SP, endpoint API, DTO, atau rumus perhitungan progres/selisih/org-jam.
- Jangan ubah interval auto-refresh.
- Jangan ubah tampilan mode non-TV selain memindahkan posisi persen ke samping bar.
- Jangan tambahkan library CSS/JS baru.

Setelah selesai: daftar file yang diubah.

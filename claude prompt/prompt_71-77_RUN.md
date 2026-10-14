# Seri Prompt 71–77 — Module Stok Benang + App Android Terakarsa

Kerjakan **berurutan** 71 → 72 → 73 → 74 → 75 → 76 → 77 tanpa berhenti menunggu
persetujuan di antara prompt. Owner akan menguji di akhir seri.

## Aturan seri

- Baca `claude prompt/benang/module-benang-keputusan-desain.md` dulu (keputusan desain). Kalau prompt
  dan dokumen itu bertentangan, prompt menang.
- **Mockup adalah arahan UI, bukan sekadar referensi.** File di
  `claude prompt/benang/mockup/*.dc.html` (pembungkus `<x-dc>`, `<helmet>`, dan blok
  `<script type="text/x-dc">` abaikan; isi `<div>` root-nya adalah layarnya). Sebelum
  membuat halaman, **baca mockup yang ditunjuk prompt**, lalu ikuti: urutan dan
  pengelompokan elemen, teks label/tombol/pesan (bahasa Indonesia persis seperti mockup),
  ukuran font relatif, warna aksen (`#0f766e` aksi utama/Ambil, `#b45309` Kembali/selisih,
  `#1d4ed8` Opname, header gelap `#1b1f24`, latar `#f4f5f3`), tombol aksi utama sticky di
  bawah pada HP, dan layout dua panel pada tablet. Terjemahkan ke Bootstrap/CSS yang ada di
  Client; boleh membuat CSS kecil `benang.css` untuk warna & komponen kartu. Data di mockup
  (warna "Merah Cabe", "Rina", rak A1/B5/X12) hanya contoh.

  | Mockup | Layar |
  |---|---|
  | `Main.dc.html` | Landing HP: scan, cari, 3 tombol aksi, daftar SKU |
  | `Sku.dc.html` | Detail SKU HP |
  | `Ambil.dc.html` | Form Ambil |
  | `Kembali.dc.html` | Form Kembali & timbang + preview label |
  | `Opname.dc.html` | Opname satu rak, HP |
  | `TabletBeranda.dc.html` | Tablet: daftar SKU kiri + detail kanan + riwayat, bar menu atas |
  | `TabletOpname.dc.html` | Tablet: daftar rak kiri + tabel hitung kanan |

  Halaman yang tidak punya mockup (form SKU, master lokasi, terima, pindah, tutup sesi,
  riwayat, pemakaian) dibuat dengan gaya yang sama mengikuti komponen dari mockup di atas.
- Schema database `inv`: tabel `inv.<tabel>`, SP `inv.SIS_<Nama>`, view `inv.v_<nama>`.
  API wajib memanggil SP lengkap dengan schema.
- **Eksekusi DDL langsung ke database** diizinkan untuk seri ini (seperti seri 60–69).
  Di awal Prompt 71: baca connection string dari `TerakarsaApp.API/appsettings*.json`,
  tampilkan nama server + database yang akan dipakai, lalu lanjut. Setiap script tetap
  disimpan di `sql/inv/` (idempotent) dan `sql/create_tables_tmos_final.sql` ikut diperbarui.
- Setelah tiap prompt: `dotnet build TerakarsaApp.slnx -v q` harus sukses, lalu
  `git commit` dengan pesan `Prompt NN — <judul>`. Jangan push.
- Berhenti dan bertanya **hanya** kalau ada hal yang membuat prompt tidak bisa dikerjakan
  (mis. tabel/SP yang dirujuk tidak ada dan tidak ada padanannya). Pertanyaan kecil:
  ambil keputusan paling masuk akal, catat di ringkasan akhir.
- Di akhir seri: tulis `claude prompt/benang/RINGKASAN_71-77.md` berisi daftar file
  per prompt, script SQL yang sudah dieksekusi, keputusan yang diambil sendiri, dan
  langkah uji manual untuk owner.

## Yang TIDAK boleh dilakukan (berlaku untuk seluruh seri)

- Jangan ubah SP/tabel produksi (`bundles`, `article_workflow_logs`, `SIS_Bundle_Manage`,
  `SIS_WorkflowLog_Manage`, dst). Module ini hanya **membaca** `projects`, `resources`,
  `users`, dan menulis `print_jobs` lewat SP yang sudah ada.
- Jangan ubah perilaku PrintService Windows untuk job type yang sudah ada.
- Jangan refactor kode lama di luar cakupan.

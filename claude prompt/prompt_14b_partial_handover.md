# Prompt 14b — Baris Susulan per Step + Konfirmasi Serahan Tidak Lengkap

## Prasyarat

Dijalankan SETELAH Prompt 14 (memakai mekanisme kuota @QtyMasuk/@QtySudah dan
pola konfirmasi @ConfirmExceed yang dibangun di sana). Boleh sebelum/sesudah
Prompt 15 — tidak saling bergantung, tapi keduanya menyentuh
SIS_WorkflowLog_Manage, jadi jalankan berurutan, jangan paralel.

## Konteks & keputusan

Aturan lapangan: bundle diserahkan lengkap. Realita: kadang serahan kurang
(barang tercecer) dan sisanya ketemu belakangan. Keputusan:
1. Satu bundle pada satu step boleh punya BEBERAPA baris log (susulan), masing-
   masing diserahkan dan diterima terpisah. Blok "satu baris per bundle per step"
   dihapus.
2. Serahan yang membuat total step KURANG dari qty masuk tetap boleh, tapi harus
   lewat dialog konfirmasi — simetris dengan kelebihan (QTY_EXCEED) dari Prompt 14.

## 1. SIS_WorkflowLog_Manage

### Hapus blok satu-baris
Pada action CREATE step ber-bundle, HAPUS validasi:
`'Step ini sudah pernah dicatat untuk bundle ini.'`
Validasi lain di sekitarnya (bundle sesuai artikel, prasyarat diterima, kuota
Prompt 14) tetap.

Periksa dan pastikan validasi "Bundle belum diterima divisi ini" untuk step
lanjutan tetap benar dengan multi-baris: cukup EXISTS satu baris step sebelumnya
yang received_at NOT NULL dan target_division_id = divisi ini.

### Validasi kekurangan (pasangan QTY_EXCEED)
Pada action CREATE dan UPDATE step ber-bundle, SETELAH lolos pemeriksaan exceed:
- Jika (@QtySudah + qty baris ini) < @QtyMasuk DAN @ConfirmShort = 0 →
  RAISERROR format tetap:
  'QTY_SHORT|Total baru %d dari %d — serahan tidak lengkap. Sisa bisa dicatat
  sebagai baris susulan.'
- Parameter baru: @ConfirmShort BIT = 0. Jika 1 → lolos.
- Kedua pemeriksaan independen: exceed dan short tidak mungkin terjadi bersamaan.

## 2. API & Client

- Request add/update hasil (stasiun + Hasil Cutting): tambah ConfirmShort
  (default false), diteruskan ke SP.
- UI: pesan berprefix QTY_SHORT| → dialog konfirmasi isi pesan tsb +
  "Yakin tetap simpan?" → jika ya, kirim ulang dengan ConfirmShort = true.
  ConfirmExceed dan ConfirmShort dikirim terpisah, jangan digabung satu flag.
- Panel scan bundle di stasiun: bundle yang stepnya sudah punya baris TIDAK lagi
  dianggap selesai-terkunci — tombol catat hasil tetap tersedia selama sisa kuota
  > 0, dengan info "Tercatat {QtySudah} dari {QtyMasuk}" (pakai
  SIS_WorkflowLog_QuotaInfo dari Prompt 14). Bila sisa kuota 0, tampilkan
  keterangan "Step ini sudah lengkap" tanpa tombol.

## 3. Pemeriksaan dampak multi-baris (wajib diverifikasi, perbaiki bila perlu)

- SIS_Bundle_ScanInfo / halaman scan publik: timeline harus menampilkan semua
  baris satu step (urut created_at), bukan mengasumsikan satu baris per step.
- SIS_Report_BundleWip (posisi bundle): definisi "log terakhir" sort_order
  terbesar lalu created_at terbesar — sudah aman untuk multi-baris, pastikan
  implementasinya memang begitu.
- SIS_Report_ArticleProgress: BundleSelesai pakai COUNT(DISTINCT bundle) — bukan
  COUNT baris. BundleDiterima: DISTINCT bundle yang punya baris received.
- SIS_Report_BundleVariance & SIS_Report_BundleHistory: agregasi per step pakai
  SUM semua baris.
- Prompt 15 (bila sudah ada): pemeriksaan UNRECEIVE "ada log step berikutnya"
  tetap benar per-bundle, tidak per-baris.

## Yang TIDAK boleh dilakukan

- Jangan mengubah aturan kuota exceed dari Prompt 14.
- Jangan menggabungkan ConfirmExceed dan ConfirmShort menjadi satu parameter.
- Jangan sentuh step non-bundle (tidak ada konsep kuota/lengkap di sana).
- Jangan sentuh alur receive, unreceive, print, modul lain.

Setelah selesai: daftar file dibuat/diubah + script SQL manual.

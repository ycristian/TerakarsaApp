# Prompt 82 — Bundle anak, pemecahan, dan selisih

## Konteks
Saat ini bundle harus komplit sebelum QC bisa menutupnya. Kita ubah: bundle dipecah berdasarkan hasil, yang OK langsung mengalir, yang bermasalah jadi bundle anak dengan barcode sendiri, dan pcs yang tidak ada dicatat sebagai selisih di induk. Dokumen keputusan lengkap: `claude/module-bundle-anak-keputusan-desain.md` (jika ada), ringkasannya di bawah.

## Prinsip (wajib dipegang)
1. Barcode hanya lahir untuk barang yang nyata ada. Hilang bukan bundle.
2. Satu bundle satu status: OK / Perbaikan / Reject / TidakLengkap. Campur = pecah.
3. Pernyataan Kirim Hasil boleh diedit selama baris workflow log-nya belum di-lock (mekanisme lock_id yang sudah ada). Edit hanya aditif: anak yang sudah lahir tidak bisa diubah/dihapus, qty OK hanya boleh turun untuk menambah reject atau hilang.
4. Induk setelah dipecah hanya menyatakan qty OK dan selisih.
5. `bundles.qty` tidak pernah diubah langsung dari form. Dia cermin dari workflow log (`QtyDelta` bertanda, `QtyAfter`). Reject dan hilang dihitung dari bundle anak dan selisih, bukan dari kolom `qty_reject_*` di log.
6. Satu pcs hanya hidup di satu bundle dan dicatat sekali.
7. Tidak ada penghapusan kolom dan tidak ada data lama yang diubah. Semua penambahan. Satu-satunya nilai lama yang berubah makna: `bundles.qty` dari qty awal menjadi qty saat ini (qty awal ada di qty_after log pertama).
8. Kerjakan di branch `feature/bundle-anak`. Jangan jalankan migrasi EF atau script apa pun ke database produksi; siapkan saja scriptnya.

## Data

### bundles, kolom baru
- `parent_bundle_id` int null — bundle yang langsung memecahnya (bisa induk atau anak). Null untuk induk utama
- `root_bundle_id` int not null — induk utama; self untuk induk utama
- `sequence_no` int not null default 0 — 0 induk, 1..n anak, diambil dari root
- `status` varchar(15) not null default 'OK' — OK | Perbaikan | Reject | TidakLengkap
- `reject_category` varchar(20) null — RejectBahan | RejectJahit | RejectPrint | Perbaikan | TidakLengkap
- `reject_reason` varchar(500) null — teks bebas
- `missing_qty` int not null default 0 — hanya di induk utama. Positif = hilang, negatif = lebih
- `qty` berubah makna: qty saat ini. Diisi service dari `QtyAfter` log terakhir, tidak pernah dari form

Kode/serial anak: `{serial induk}-{sequence_no}`, datar, contoh `B26-005742-1`, `B26-005742-5`. Anak yang dipecah lagi tetap bernomor dari root. Untuk tampilan pakai `{bundle_no induk}-{seq}` (K-49-1).

### article_workflow_logs, kolom baru
- `qty_delta` int not null default 0 — bertanda: +57 creation, −5 split, −2 dikembalikan, +1 ketemu
- `qty_after` int not null default 0 — qty bundle setelah baris ini
- `log_kind` varchar(15) not null default 'Kirim' — Creation | Kirim | Split | Dikembalikan | Hilang | Ketemu. (Kolom `log_type` NORMAL/ADJUSTMENT yang sudah ada tetap, jangan diubah)
- `split_id` int null — FK ke bundle_splits
- `reason` varchar(500) null
- Σ `qty_delta` per bundle harus = `bundles.qty`. Pakai sebagai cek konsistensi
- Kolom `qty_reject_print/fabric/sewing/rework` dan `qty_lost`: berhenti diisi untuk log baru (biarkan 0). Jangan dihapus, jangan dikosongkan. Laporan PO lama tetap membacanya

### Tabel baru
```
bundle_splits
  split_id int identity pk
  source_bundle_id int not null fk bundles
  source_qty_before int not null
  kind varchar(10) not null          -- split | found
  division_id int not null
  resource_id int null
  created_at datetime2 not null default sysdatetime()
  created_by int not null
  lock_id int null

bundle_split_results
  split_result_id int identity pk
  split_id int not null fk bundle_splits
  bundle_id int not null fk bundles  -- anak yang lahir (atau anak yang ditambah qty-nya)
  qty int not null
  status varchar(15) not null
  reject_category varchar(20) null
  reject_reason varchar(500) null
  is_system_choice bit not null default 0
```

### Master kategori (hardcode enum dulu, tidak perlu tabel)
RejectBahan, RejectJahit, RejectPrint, Perbaikan, TidakLengkap. `qty_reject_rework` lama dipetakan ke Perbaikan. TidakLengkap hanya ditampilkan di station Loading/Bundling.

## Modal Kirim Hasil (ganti modal yang sekarang, berlaku di semua station yang punya Kirim Hasil)

Layout, dari atas:
- Header: kode bundle, size, serial, step, "Masuk N pcs". N = qty bundle saat ini (`qty_after` log terakhir), bukan angka stiker
- **Qty OK**: input number, terisi N saat dibuka. Hapus tombol "Set All OK"
- Baris **Masalah** dengan tombol "+ Tambah baris". Awalnya kosong
- Tiap baris: `[Kode anak, otomatis: K-49-1, K-49-2, …] [Kategori dropdown] [Alasan text, wajib] [Qty number] [× hapus]`. Kode anak tampil sebelum Kirim supaya admin tahu barcode apa yang akan lahir
- **Sisa** = Masuk − OK − Σ qty baris, dihitung live:
  - Sisa > 0: kotak kuning "Sisa X pcs tidak ditemukan, akan dicatat hilang di {kode}"
  - Sisa = 0: kotak tidak tampil
  - Sisa < 0: tombol Kirim disabled, pesan merah "Melebihi qty masuk"
- Hapus field Catatan wajib. Divisi tujuan tetap satu field seperti sekarang
- Tombol: Batal, Kirim hasil

Saat Kirim (satu transaksi):
1. Buat `bundle_splits` kind=split, source_qty_before = Masuk
2. Induk: qty = OK, status = OK, missing_qty += Sisa. Workflow log satu baris log_kind=Kirim, qty_delta = OK − Masuk, qty_after = OK, split_id. Kalau Sisa > 0 tambah satu baris log_kind=Hilang, qty_delta 0, reason
3. Tiap baris masalah: buat bundle anak di root yang sama, sequence_no berikutnya (MAX(sequence_no)+1 di root, dalam lock), status dari kategori (Perbaikan → Perbaikan, TidakLengkap → TidakLengkap, lainnya → Reject), reject_category, reject_reason, qty. Workflow log log_kind=Creation di anak (qty_delta +qty, qty_after qty, split_id). Tambah `bundle_split_results`
4. Hanya induk OK yang pindah ke Divisi tujuan. Anak Perbaikan dikembalikan ke step Sewing, anak Reject tetap di station ini, anak TidakLengkap tetap di Loading sampai statusnya diubah jadi OK lewat Kirim Hasil anak itu
5. Cetak ulang stiker induk (qty baru, status OK, step, user, tanggal) dan stiker tiap anak (kode, qty, status, kategori). Stiker anak tidak mencantumkan asal. Set `needs_reprint`

Bundle anak diperlakukan sama di semua station: bisa discan, dialirkan, dan di-Kirim Hasil lagi dengan modal yang sama. Anak yang semua pcs-nya jadi OK cukup ubah status, tidak lahir nomor baru.

## Edit Kirim Hasil
- Tombol Edit aktif selama baris workflow log Kirim Hasil ini `lock_id` null. Sudah lock = disabled
- Modal sama, baris anak yang sudah lahir tampil read-only (kode, kategori, alasan, qty), tanpa tombol hapus
- Qty OK hanya boleh turun. Selisih turunannya jadi baris masalah baru atau menambah hilang
- Baris baru dapat kode anak berikutnya dari root
- Saat simpan: `bundle_splits` baru kind=split, induk qty turun (log Kirim baru dengan delta negatif), anak baru lahir, missing_qty bertambah. Split dan log lama tidak disentuh
- Status anak yang sudah tercatat tidak bisa diubah dari modal ini; hanya lewat Kirim Hasil di anak itu
- Setelah edit, induk `needs_reprint = 1`
- Lock otomatis: begitu station berikutnya membuat log Kirim di bundle ini, log station sebelumnya tidak bisa diedit lagi (cek: ada log bundle ini dengan sort_order lebih besar)
- Kasus Loading: penjahit mengembalikan sebagian karena part kurang → Loading edit Kirim Hasil-nya, tambah baris TidakLengkap dengan alasan. Tidak ada aksi baru. Setelah edit, station berikutnya melihat Masuk = qty baru

## Kartu artikel (semua station)
Di bawah Bundle dan Qty, tambah:
- **Hilang**: Σ `missing_qty` positif semua induk artikel ini, semua station. > 0 merah dan clickable → modal Barang ketemu; = 0 abu-abu, tidak clickable
- **Lebih**: Σ `missing_qty` negatif (absolut). Tampil hanya kalau > 0
- Qty tetap = Σ qty bundle nyata di station

## Modal Barang ketemu (dibuka dari angka Hilang)
Layout:
- Header: nama artikel, PO, "Hilang terbuka: S 3 · M 1"
- Size dropdown, hanya size yang punya selisih terbuka, tampilkan "selisih terbuka: N"
- Qty ketemu, number
- Kondisi dropdown: OK, Perbaikan, RejectBahan, RejectJahit, RejectPrint
- Alasan text, tampil hanya kalau kondisi bukan OK, wajib
- Blok **Akan dicatat ke**: daftar bundle tujuan hasil alokasi LIFO (induk dengan `missing_qty` > 0 di size itu, urut created_at log Hilang terakhir desc), tiap baris: kode induk, tanggal hilang, qty teralokasi, kode anak yang akan lahir. Tombol "Ubah" membuka daftar semua induk ber-selisih di size itu dengan qty manual
- Qty boleh melebihi total selisih; kelebihan ditempel ke bundle LIFO terakhir (baris ditandai kuning "melebihi selisih, dicatat Lebih"), tidak lahir anak terpisah, gabung ke anak bundle itu
- Teks bantu: "Urutan otomatis: yang paling baru hilang diisi lebih dulu."
- Tombol: Batal, Catat

Saat Catat, per bundle tujuan (satu transaksi):
1. `bundle_splits` kind=found, source = bundle tujuan
2. Bundle tujuan: missing_qty −= qty teralokasi (boleh jadi negatif). Log log_kind=Ketemu, qty_delta 0, reason, split_id. `is_system_choice` = apakah admin mengubah alokasi
3. Bundle anak baru di root bundle tujuan, sequence_no berikutnya, status/kategori dari Kondisi, qty, division = station saat ini. Log Creation di anak
4. Cetak stiker anak. Anak OK masuk WIP station ini dan mengalir normal

## Laporan dan query
- Total pcs PO = Σ qty bundle aktif + Σ missing_qty (bisa negatif)
- Reject per kategori: untuk log setelah tanggal migrasi dari bundle anak status=Reject/Perbaikan; untuk log sebelumnya tetap dari `qty_reject_*` (lihat bagian Migrasi)
- Rekap per penjahit (employee_id di log Kirim induk): OK, RejectBahan, RejectPrint, RejectJahit, Perbaikan, hilang. Tidak ada logika upah di sistem
- Audit semua tempat yang memakai `bundles.qty` sebagai qty awal → ambil dari log Creation. Dan yang mengambil angka reject dari `qty_reject_*` → arahkan ke bundle anak untuk data setelah migrasi

## Migrasi data lama (ringan: hanya kolom default dan delta, TIDAK melahirkan anak)
Kolom nyata: `article_workflow_logs` (qty_ok, qty_reject_*, qty_lost, log_type NORMAL|ADJUSTMENT, lock_id, deleted_at, created_at), `bundles` (qty, serial, bundle_no, deleted_at). Step diurutkan lewat `article_workflows.sort_order`.

Data per 30/10/2026: 28.775 log, 6.821 bundle (6.297 punya log, 382 stok cutting tanpa log), 991 log tanpa bundle_id (Cutting per size). Rantai qty_ok antar step konsisten di 6.015 bundle; 282 bundle punya selisih tak tercatat, dibiarkan.

Script sekali jalan, idempotent, satu transaksi:
1. Semua bundle lama: parent_bundle_id null, root_bundle_id = bundle_id, sequence_no 0, status 'OK', missing_qty 0. Tidak ada anak yang dilahirkan dari reject lama
2. Semua log lama dengan bundle_id, urut sort_order lalu created_at per bundle:
   - log pertama bundle: qty_delta = +qty_ok+Σreject+qty_lost (= bundles.qty, terbukti sama di semua 6.297 bundle), qty_after = nilai itu, log_kind = 'Creation'
   - log berikutnya: qty_delta = qty_ok − qty_after sebelumnya, qty_after = qty_ok, log_kind = 'Kirim'. Selisih tak tercatat terserap di delta ini, tidak dicatat terpisah
   - log ADJUSTMENT: log_kind = 'Kirim', delta mengikuti rumus yang sama
3. Bundle tanpa log (382 stok cutting): tidak perlu log Creation; bundles.qty tetap, service membuat Creation saat bundle pertama kali dikirim
4. Log tanpa bundle_id: tidak disentuh
5. bundles.qty induk = qty_after log terakhir. Jangan set needs_reprint untuk bundle lama
6. Kolom qty_reject_*, qty_lost lama tidak disentuh; tetap jadi sumber reject/lost untuk log sebelum tanggal migrasi

Verifikasi wajib, gagal = rollback: Σ qty_delta per bundle = bundles.qty untuk setiap bundle yang punya log.

Dua jalur selama PO lama masih jalan:
- Laporan reject/lost: log dengan created_at < tanggal migrasi dibaca dari qty_reject_*/qty_lost; sesudahnya dari bundle anak dan missing_qty. Simpan tanggal migrasi di app setting
- Bundle lama yang punya reject gaya lama (ada log dengan qty_reject_* > 0 sebelum migrasi): tombol ADJUSTMENT lama tetap tersedia untuk bundle itu saja, supaya reject lama yang jadi bagus masih bisa dicatat. Bundle lain pakai modal baru
- Modal Kirim Hasil baru berlaku untuk semua bundle sejak deploy, termasuk bundle lama yang masih di tengah alur; Masuk = qty_after terakhir

## Di luar scope
- Konfirmasi per part saat serah bundle ke penjahit (prompt terpisah)
- Pencocokan otomatis Hilang dan Lebih antar bundle
- Penghapusan kolom qty_reject_* / qty_lost
- Melahirkan bundle anak dari reject lama (tidak akan dilakukan; reject lama tetap angka di log)

# Prompt 24 — Buat Bundle & Cetak Ulang Label di Station

> Jalankan SETELAH Prompt 23 (memakai pola kartu WIP non-bundle yang sama).

## Konteks

Sejak Prompt 17, Bundling adalah divisi sendiri dengan step workflow implisit (`is_bundling = 1`). "Persimpangan" non-bundle → bundle = station bertoken **divisi Bundling**:

- **WIP** station Bundling: kartu per artikel aktif yang punya step Bundling, dengan tombol **"Buat Bundle"** → modal buat bundle + checkbox **"Cetak label otomatis"** (default centang).
- **OUT** station Bundling: bundle yang sudah dibuat tapi belum diterima divisi berikutnya SUDAH otomatis tampil (log Bundling `division_id` = Bundling, `received_at IS NULL` → masuk SIS_Station_PendingHandover). Di sinilah **Edit** bundle (qty/penjahit). **Hapus bundle TIDAK ada di station** — tetap admin lewat halaman Kelola Bundle.
- **Cetak Ulang** label: tombol di SEMUA kartu bundle station (IN/WIP/OUT, semua divisi) + kartu hasil scan — antisipasi label hilang di lantai produksi.

Halaman admin Kelola Bundle (`/articles/{id}/bundles`) TETAP ada — dua jalur pembuatan bundle.

Catatan penting: sejak Prompt 17 qty bundle tersimpan di DUA tempat — `bundles.qty` dan `qty_ok` baris log Bundling. Edit qty harus menyinkronkan keduanya.

## 1. SQL

### a. `sql/sp_Bundle_Manage.sql`

**CREATE** — parameter baru `@SkipPrintJob BIT = 0`: bila 1, lewati insert `print_jobs` (checkbox cetak otomatis tidak dicentang). Selain itu CREATE tidak berubah (serial, bundle_no, log Bundling, auto-receive tetap).

**UPDATE** — dua perubahan:
1. Sinkronkan `qty_ok` baris log Bundling hidup milik bundle ini = @Qty baru (dalam transaksi yang sama).
2. Perketat guard: tolak bila baris log Bundling bundle ini sudah diterima (`received_at IS NOT NULL`) — pesan jelas ("Bundle sudah diterima divisi berikutnya, tidak bisa diubah."). Guard existing (log step berikutnya) tetap.

**DELETE** dan `SIS_Bundle_ReprintLabel` tidak diubah.

### b. `sql/sp_Station_Operations.sql` — perluas SIS_Station_ActiveWork

Tambahkan baris untuk step `is_bundling = 1` milik @DivisionId (divisi Bundling), dengan kolom flag `IsBundling` supaya client membedakan tombol Kirim Hasil vs Buat Bundle. Untuk baris bundling, sertakan ringkas: jumlah bundle hidup + total qty bundle vs total qty order artikel (angka ringkas kartu; detail per size diambil saat modal dibuka). `DikerjakanCount` di SIS_Station_Counts otomatis ikut karena berbasis definisi ActiveWork (Prompt 23).

### c. Ringkasan per size untuk modal
Pakai ulang `SIS_Article_BundleSummary` (qty order, saran bundle_qty, jumlah bundle, total qty bundle per size) — tidak buat SP baru.

## 2. API — Station ([RequireStationToken])

- GET `api/station/bundling/articles/{articleId}/summary` → SIS_Article_BundleSummary. Validasi: divisi token punya step `is_bundling` (= divisi Bundling).
- POST `api/station/bundles` — CREATE via SIS_Bundle_Manage: articleId, articleSizeId, qty, resourceId/resourcePersonName (penjahit, opsional), autoPrint (bool, default true → @SkipPrintJob = !autoPrint). `@BundlingResourceId` = operator sesi station (WAJIB). Validasi divisi token = Bundling. `@PublicBaseUrl` pola existing.
- PUT `api/station/bundles/{id}` — edit qty + penjahit (guard di SP bagian 1a). Validasi divisi token = Bundling.
- POST `api/station/bundles/{id}/reprint` — SIS_Bundle_ReprintLabel. TANPA batasan divisi (semua station boleh cetak ulang), cukup token valid.
- created_by/updated_by = konvensi user sistem station yang berlaku.

## 3. Blazor Client — `StationDevice.razor`

### WIP — kartu Buat Bundle (hanya muncul di station divisi Bundling)
1. Kartu per artikel (badge "Bundling"): artikel, project, style/color, ringkas "X bundle · total {qty} dari {order}". Tombol **Buat Bundle**.
2. Modal Buat Bundle:
   - Tabel ringkasan per size (qty order, saran bundle_qty, jumlah bundle, total qty bundle) — highlight kuning bila total ≠ order (informasi, tidak memblokir).
   - Form: dropdown size, qty (prefill saran bundle_qty size terpilih), penjahit (dropdown resource + input nama orang, opsional), checkbox **"Cetak label otomatis"** default CENTANG.
   - Simpan → bundle langsung tampil di ringkasan; modal TETAP terbuka untuk input beruntun (size, qty, dan status checkbox dipertahankan). Feedback: "Bundle B26-xxxxxx dibuat" (+ "· label masuk antrian cetak" bila autoPrint).
3. Pelaksana bundling = operator sesi (tampil read-only di modal).

### OUT — baris bundle buatan divisi Bundling
- Tombol **Edit** (menggantikan Revisi generik untuk baris `is_bundling`): modal qty + penjahit → PUT `api/station/bundles/{id}` (bukan REVISE_HANDOVER — supaya qty sinkron via SIS_Bundle_Manage).
- **Batal Serah disembunyikan** untuk baris `is_bundling` (setara hapus bundle — admin saja).

### Cetak Ulang — semua divisi
- Tombol/ikon printer kecil di SETIAP kartu yang menampilkan bundle: tab IN, WIP, OUT, dan kartu hasil scan (`BundleScanCard`). Konfirmasi ringan ("Cetak ulang label {serial}?") → POST reprint → toast "Label masuk antrian cetak."

## Yang TIDAK boleh dilakukan

- Jangan ubah generate serial/bundle_no, TsplBuilder, atau Windows worker service.
- Jangan tambah aksi hapus bundle di station.
- Jangan ubah `SIS_WorkflowLog_Manage`.
- Jangan hapus/ubah halaman admin Kelola Bundle — dua jalur tetap hidup.
- Jangan ubah perilaku auto-receive (sudah diatur Prompt 23).

Setelah selesai: daftar file dibuat/diubah + script SQL yang harus dijalankan manual.

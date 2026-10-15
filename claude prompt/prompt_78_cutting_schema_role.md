# Prompt 78 — Module Cutting: Schema, Role Admin Cutting, Landing & Stok Bundle

Baca dulu `claude prompt/cutting/module-cutting-keputusan-desain.md` dan mockup di `claude prompt/cutting/mockup/`. Ikuti konvensi repo (CLAUDE.md): SP prefix `SIS_`, CUD lewat `SIS_X_Manage` dengan `@Action`, read SP terpisah per fungsi, soft delete `deleted_at` (filter di `ON` untuk LEFT JOIN), `[RequireModule]`, UI Bahasa Indonesia, kode & API Inggris. Tidak ada ID hardcoded — seed cari referensi by name.

DDL boleh dieksekusi langsung ke database (seperti seri TNI & benang). Konfirmasi target DB dulu di awal sesi, lalu jalan terus.

## 0. Inspeksi dulu (jangan asumsi)

Sebelum menulis apa pun, periksa dan ringkas di awal jawaban:
1. Struktur tabel `bundles` sekarang: kolom identitas, kode/barcode, relasi ke artikel/project, status, dan bagaimana bundle dibuat sekarang (SP & halaman admin mana).
2. Tabel `articles`: kolom size (master size / size per artikel disimpan di mana), relasi ke `projects` (PO).
3. Pola role & module dari Prompt 71 (Admin Gudang): tabel modules/roles, cara seed, redirect landing setelah login, layout landing.
4. Isi QR bundle yang sudah dipakai di stiker penyerahan bundle (format string-nya) — Prompt 79 akan pakai format yang sama.

Kalau ada yang bertentangan dengan dokumen keputusan, tulis di bagian "Catatan" dan ambil keputusan yang paling kecil dampaknya — jangan berhenti.

## 1. Schema (schema `dbo`, bukan schema baru)

### `spreads` (hamparan)
- `id` PK, `article_id` FK → articles, `spread_code` NVARCHAR(20) (unik per artikel, aktif saja), `spread_date` DATE, `set_count` INT, `sheets_per_set` INT, `status` (`DRAFT`, `PRINTED`), `printed_at`, `note`, `created_by`, `created_at`, `updated_by`, `updated_at`, `deleted_at`, `deleted_by`.
- Unique filtered index `(article_id, spread_code) WHERE deleted_at IS NULL`.

### `spread_sizes` (rincian set per size)
- `id`, `spread_id` FK, `size_code` (ikut tipe kolom size yang sudah dipakai `bundles`/`articles`), `set_count` INT, `number_from` INT, `number_to` INT, `created_at`.
- `number_from` = `MAX(number_to)` dari spread_sizes artikel+size yang sama (spread tidak dihapus) + 1; kalau belum ada = 1. `number_to = number_from + set_count × sheets_per_set − 1`.

### Kolom baru di `bundles`
- `spread_id` NULL FK, `spread_size_id` NULL FK, `set_no` INT NULL, `bundle_seq` INT NULL (urut per spread per size), `number_from` INT NULL, `number_to` INT NULL, `source` NVARCHAR(10) NOT NULL DEFAULT `MANUAL` (`MANUAL` / `CUTTING`), `stock_status` NVARCHAR(10) NULL (`STOCK` / `TAKEN`, hanya untuk source CUTTING), `taken_at`, `taken_by_resource_id` NULL FK resource, `needs_reprint` BIT NOT NULL DEFAULT 0.
- Kode bundle (kolom kode yang sudah ada) untuk source CUTTING diisi `<spread_code>-<size_code>-<bundle_seq 2 digit>`.
- Bundle lama tidak disentuh (source default MANUAL).

### Kolom baru di `articles`
- `bundle_target_qty` INT NOT NULL DEFAULT 50. Tambahkan field-nya di form artikel yang sudah ada (label "Target pcs per bundle").

## 2. Stored procedure

- `SIS_Spread_Manage` `@Action` = `CREATE` (header + sizes + bundles sekaligus, dalam transaksi), `UPDATE_HEADER` (hanya status DRAFT), `DELETE` (tolak kalau ada bundle `TAKEN`), `MARK_PRINTED`.
- `SIS_SpreadBundle_Manage` `@Action` = `UPDATE_QTY` (ubah qty satu bundle, geser `number_from/to` bundle berikutnya di set yang sama, set `needs_reprint=1` untuk bundle yang berubah; tolak kalau bundle itu atau bundle setelahnya di set yang sama sudah `TAKEN`), `ADD` (tambah bundle di akhir set), `REMOVE` (hanya bundle terakhir di set, hanya STOCK).
- Guard di SP: total qty per set harus = `sheets_per_set` setelah perubahan; kalau tidak, tolak dengan pesan jelas.
- `SIS_Cutting_NextNumber` (article_id, size_code) → number_from berikutnya.
- `SIS_Cutting_SuggestBundles` (sheets, target) → tabel qty per bundle, algoritma: `n = ROUND(sheets/target)` min 1; `base = sheets / n`, `rem = sheets % n`; bundle 1..rem = base+1, sisanya base; kalau `base + (rem>0 ? 1 : 0) > target + 10` → n+1 ulang. Boleh dihitung di C# saja kalau lebih rapi — tapi satu sumber, dipakai API.
- Read: `SIS_Cutting_StockSummary` (per artikel per size: total, STOCK, TAKEN, pcs STOCK; plus angka ringkas: bundle & pcs STOCK, TAKEN hari ini, spread DRAFT), `SIS_Spread_List` (filter artikel, status, tanggal), `SIS_Spread_Detail` (header + sizes + bundles dengan status, taken info).

## 3. Module, role, routing

- Module `CUTTING`. Role **Admin Cutting** hanya punya module ini; login → redirect ke `/cutting` (pola Admin Gudang Prompt 71). Owner/superadmin tetap bisa akses.
- Layout landing sendiri (header gelap, tab: Stok Bundle · Hamparan), responsif: tablet landscape dua kolom, HP satu kolom.
- API controller `CuttingController` dengan `[RequireModule("CUTTING")]`.

## 4. Halaman Stok Bundle (`/cutting`) — ikut mockup layar 1

- 4 kartu angka ringkas.
- Daftar per artikel (judul: `<PO> · <nama artikel>`, subjudul target pcs/bundle, jumlah hamparan), tabel per size: Size · Total bundle · Tersedia · Diambil · Pcs tersedia. Tersedia hijau, 0 oranye.
- Tombol "+ Buat Hamparan" → `/cutting/hamparan/baru` (dibuat di Prompt 79; buat placeholder route dulu).

## 5. Seed & verifikasi

- Seed module + role by name. Jangan assign ke user mana pun.
- Build client + API harus lolos. Jalankan SP suggest dengan 220/249/230/260/225 target 50 dan tulis hasilnya di laporan akhir.

## 6. Laporan akhir
Ringkas: tabel/kolom yang dibuat, SP, route, hasil uji suggest, dan "Catatan" (penyimpangan dari dokumen keputusan).

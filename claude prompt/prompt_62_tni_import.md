# Prompt 62 — PDH TNI AD: Import Data Personel dari Excel Google Form

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 61. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD".

## Konteks

Data personel berasal dari **export Google Form** (`.xlsx`, sheet pertama atau
sheet bernama `DATA MENTAH`, ±7.300 baris, 35 kolom). Import bisa **diulang**:
data sudah final tapi masih mungkin bertambah orang atau diperbaiki size-nya.
Alurnya dua langkah: **Unggah** (masuk staging + dicek) → **Simpan** (commit ke
`tni.personel`). Baris bermasalah tidak dibuang diam-diam — ditahan dan
ditampilkan alasannya.

Aturan minimal yang disepakati owner: **NRP + Nama + pola kemeja + pola celana**
wajib ada. Ukuran badan boleh kosong.

## 1. Pemetaan kolom (cari kolom berdasarkan **nama header**, bukan posisi)

| Header di Excel | Ke | Catatan |
|---|---|---|
| `Timestamp` | `submitted_at` | |
| `Email` | `email_pengisi` | email pengisi form, bukan email personel |
| `Gender` | `gender` | lihat aturan gender |
| `Pangkat` | `pangkat` | trim |
| `NAMA` | `nama` | trim, spasi ganda dirapikan |
| `NRP` | `nrp` | baca sebagai **teks**; buang apostrof di depan & spasi; jangan sampai jadi notasi ilmiah / `.0` |
| `No. HP` | `no_hp` | teks |
| `TB`, `BB` | `tinggi_badan`, `berat_badan` | angka, kosong → NULL |
| `Size Baju`, `Size Celana` | `size_baju_isian`, `size_celana_isian` | arsip saja, tidak divalidasi |
| `KATEGORI` | `kategori` | `T.U : Sizing` → `TU_SIZING`, selain itu `UKUR` |
| `Area Rawatan` | area | cocokkan ke `tni.area_rawatan.area_name` |
| `BOGOR` / `Cimahi` / `BANDUNG` | satuan | **tepat satu terisi per baris** (artefak percabangan form) — ambil yang terisi, cocokkan ke `tni.satuan.satuan_name` dalam area tadi |
| `GROUPING SIZE BAJU` | `pola_kemeja_id` | cocokkan ke `tni.pola_kemeja.kode` (hidup & aktif) |
| `GROUPING SIZE CELANA` | `pola_celana_id` | cocokkan ke `tni.pola_celana.kode` |
| 8 kolom ukuran kemeja | kolom ukuran kemeja | `Lingkar Leher`, `Lebar Bahu`, `Lingkar Dada`, `Lingkar Perut`, `Panjang Badan Depan`, `Panjang Lengan`, `Lingkar Lengan`, `Lingkar Ketiak` |
| 7 kolom ukuran celana | kolom ukuran celana | `Lingkar Pinggang Celana`, `Lingkar Pinggul`, `Lingkar Pesak`, `Lingkar Paha`, `Lingkar Lutut`, `Lingkar Celana Bawah`, `Panjang Celana` |
| `Pernyataan 1`, `Pernyataan 2` | — | diabaikan |

Ukuran bernilai `0` atau kosong → NULL. Header wajib yang tidak ditemukan →
tolak seluruh file dengan pesan menyebut header yang hilang.

### Aturan gender
- `Pria` → `PRIA`; `Wanita - Hijab` → `WANITA_HIJAB`; `Wanita - Non Hijab` →
  `WANITA_NON_HIJAB`.
- `Wanita` saja (form versi lama) → turunkan dari akhiran pola kemeja: `_WH…` →
  `WANITA_HIJAB`, `_W…` → `WANITA_NON_HIJAB`.

## 2. Aturan validasi per baris

| Kondisi | Hasil | Pesan |
|---|---|---|
| NRP kosong / nama kosong | `TOLAK` | |
| Area atau satuan tidak dikenal | `TOLAK` | sebut nilai yang tidak dikenal |
| Pola kemeja / celana tidak ada di master (atau nonaktif) | `TOLAK` | sebut kodenya — contoh nyata `LD_118_PG` |
| NRP yang sama muncul >1 kali **di file yang sama** | `TOLAK` **semua** baris NRP itu | sebut nomor baris yang bentrok |
| NRP kurang dari 12 digit | `REVIEW` | "NRP hanya n digit, umumnya 13–16" |
| Gender bentrok dengan pola kemeja (`PRIA` dengan `_W…`; `WANITA_NON_HIJAB` dengan `_WH…`; `WANITA_HIJAB` dengan `_W` non-hijab; wanita dengan `_P`/`_PG`) | `REVIEW` | "beda lengan pendek/panjang — cek" |
| Personel sudah ada, sudah **Set Jadi**, dan pola di file berbeda | `REVIEW` | pola **tidak** diubah; catat "pola berubah setelah set jadi: X → Y" |
| Selain itu | `VALID` | |

`aksi`: `PERBARUI` bila NRP sudah ada di `tni.personel` (order aktif, hidup),
selain itu `BARU`. Baris `REVIEW` tetap disimpan saat commit, dengan
`status_data = 'PERLU_REVIEW'` dan pesannya di `catatan_review`.

## 3. SQL — `sql/tni/sp_Import.sql`

- `tni.SIS_Import_Stage` (`@OrderId`, `@NamaFile`, `@Rows nvarchar(max)` JSON
  hasil parsing API, `@UserId`) — buat `tni.import_batch`, isi
  `tni.import_staging` (`raw_json` = objek baris apa adanya), jalankan seluruh
  validasi bagian 2 **di SP** (OPENJSON), isi hitungan di batch. Kembalikan
  `batch_id`.
- `tni.SIS_Import_GetBatch` (`@BatchId`) — 2 result set: ringkasan batch;
  baris `TOLAK`/`REVIEW` (baris_ke, nrp, nama, hasil, aksi, pesan).
- `tni.SIS_Import_BatchList` (`@OrderId`) — riwayat batch terbaru dulu.
- `tni.SIS_Import_Commit` (`@BatchId`, `@UserId`) — **satu transaksi**:
  - Tolak bila batch sudah pernah di-commit.
  - Baris `VALID`/`REVIEW` aksi `PERBARUI`: update identitas, kategori, ukuran,
    isian mentah, `submitted_at`; pola diubah **hanya bila `set_at IS NULL`**.
    `kode_ref`, `no_urut`, `qr_token`, dan satuan **tidak pernah diubah**
    (kalau satuan di file berbeda → jadikan `REVIEW`, jangan pindahkan).
  - Aksi `BARU`: `no_urut` = MAX + 1 per satuan (kunci dengan
    `sp_getapplock` per satuan); `kode_ref` = `satuan_code + '-' +
    RIGHT('000' + no_urut, 3)` (lebih dari 999 → biarkan 4 digit);
    `qr_token` = 10 karakter acak `[A-Za-z0-9]` dari `CRYPT_GEN_RANDOM`,
    ulangi bila bentrok dengan token yang sudah ada (termasuk baris terhapus).
  - Urutan pemberian nomor untuk personel baru: `submitted_at`, lalu `baris_ke`.
  - Isi `personel_id` di staging, `committed_at/by` di batch.
  - Personel yang ada di database tapi tidak ada di file **tidak disentuh**.

## 4. API

- `TerakarsaApp.Shared/Tni/TniImportModels.cs`.
- `TniImportService` + `TniImportController` (`api/tni/import`, `TNI_PDH`):
  - POST `upload` (multipart, `.xlsx`, maks 10 MB) → baca Excel dengan
    **ClosedXML** (pakai yang sudah terpasang untuk export Laporan Hanca; kalau
    belum ada di API, tambahkan paketnya) → bangun JSON baris → `SIS_Import_Stage`.
    File **tidak disimpan** ke disk.
  - GET `{batchId}`, GET `batches`, POST `{batchId}/commit`.
- Parsing di API hanya memetakan header & membersihkan tipe data. **Semua
  aturan validasi tetap di SP.**

## 5. Client — `/tni/import`

Gaya mockup (HP), boleh dipakai di laptop juga:
1. Kartu unggah: pilih file `.xlsx` → **Unggah & cek**, indikator proses.
2. Hasil cek: 4 angka besar — **Baru**, **Diperbarui**, **Perlu review**,
   **Ditolak**. Daftar baris Ditolak & Perlu review sebagai kartu: nomor baris
   Excel, nama, NRP, pesan. Filter Ditolak / Review.
3. Bar bawah: **Simpan n baris** (Baru + Diperbarui + Review), konfirmasi dulu.
   Nonaktif bila 0 atau batch sudah disimpan.
4. Bagian riwayat import: tanggal, nama file, hitungan, siapa.

## Verifikasi

Uji dengan file data mentah asli (`Grouping Size Kodam Siliwangi.xlsx`, sheet
`DATA MENTAH`, 7.279 baris). Hasil yang diharapkan, sesuai analisa sebelumnya:
- Ditolak **33**: 32 baris NRP kembar (16 pasang) + 1 baris pola `LD_118_PG`.
- Perlu review ±**114**: NRP < 12 digit (±109) + gender vs pola bentrok (5).
- Sisanya Baru. Simpan → ±7.246 personel; `kode_ref` per satuan mulai `-001`
  tanpa lompat; semua `qr_token` unik 10 karakter.
- Unggah ulang file yang sama → semua `PERBARUI`, 0 baru, tidak ada `kode_ref`
  atau `qr_token` yang berubah.
- Laporkan angka sebenarnya ke owner, termasuk bila berbeda dari perkiraan ini.

`dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan menghapus personel yang tidak ada di file.
- Jangan mengubah `kode_ref`, `no_urut`, `qr_token`, atau satuan personel lama.
- Jangan memvalidasi rentang ukuran badan — keputusan owner: tidak dipakai.
- Jangan menyimpan file Excel ke disk server.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi + hasil uji
import (angka per kategori), sebagai markdown link.

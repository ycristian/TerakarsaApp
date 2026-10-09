# Prompt 64 — PDH TNI AD: Stok Kemeja & Celana

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 63. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup layar 9: `claude prompt/tni/mockup_tampilan.html`.

## Konteks

Produksi menyetor kemeja & celana **bertahap** — bisa harian atau beberapa kali
sehari, **tanpa nomor surat jalan**. Stok bersifat **anonim per pola**: kemeja
`LD_102_P` mana pun boleh dipakai untuk siapa pun yang polanya sama.

Stok dicatat sebagai buku besar plus-minus di `tni.stok_mutasi` (sudah dibuat
Prompt 60). **Tidak ada tabel saldo** — saldo selalu `SUM(qty)`.

Pengurangan karena packing (`TERPAKAI`) dan pengembalian karena pembatalan
(`BONGKAR`) **tidak** diinput manual — dibuat otomatis di Prompt 66 dan 68.

### Stok bebas
Kartu yang sudah dicetak tapi belum di-scan Set Jadi dianggap "sudah dijatah".
**Stok bebas** = saldo − jumlah personel berstatus `DICETAK` yang memakai pola
itu. Angka ini dipakai untuk saran Perintah Kerja (Prompt 65) supaya dua
perintah kerja tidak menghitung barang yang sama. Cetak **tidak mengunci** stok
— scan tidak pernah ditolak karena angka ini.

## 1. SQL

### `sql/tni/v_stok.sql` — `CREATE OR ALTER VIEW tni.v_stok_pola`
Satu baris per pola (kemeja & celana, termasuk yang saldo 0) per order:
`order_id, jenis_item, pola_id, kode, is_active, masuk` (SUM MASUK),
`terpakai` (−SUM TERPAKAI, positif), `keluar_lain` (SUM RUSAK + KOREKSI),
`bongkar`, `saldo` (SUM semua), `dijatah` (COUNT personel `DICETAK` dari
`tni.v_personel` dengan pola itu), `stok_bebas` (`saldo − dijatah`),
`kebutuhan_sisa` (COUNT personel BELUM_CETAK + DICETAK dengan pola itu).
Semua SP stok membaca view ini.

### `sql/tni/sp_Stok.sql`
- `tni.SIS_Stok_Manage` — `@Action`:
  - `SETORAN` (`@OrderId`, `@Tanggal`, `@Items` JSON
    `[{jenisItem, polaId, qty}]`, `@UserId`) — **satu transaksi**; tiap item
    `qty > 0`, pola hidup & aktif dan cocok dengan `jenisItem`; insert baris
    `MASUK`. Satu pola boleh muncul sekali per setoran (gabungkan bila dobel).
  - `KELUAR` (`@JenisMutasi` `RUSAK` atau `KOREKSI`, item tunggal, `@Qty`,
    `@Alasan`) — `RUSAK`: `@Qty > 0` disimpan **negatif**, alasan wajib.
    `KOREKSI`: `@Qty` boleh + atau − (≠ 0), alasan wajib untuk keduanya.
  - Tidak ada UPDATE/DELETE mutasi — salah input dibetulkan dengan `KOREKSI`.
- `tni.SIS_Stok_Saldo` (`@OrderId`, `@JenisItem`, `@Search` null,
  `@HanyaAda` bit = 0) — dari `tni.v_stok_pola`, urut angka pola.
- `tni.SIS_Stok_Riwayat` (`@OrderId`, `@JenisItem` null, `@PolaId` null,
  `@JenisMutasi` null, `@Dari` null, `@Sampai` null, paging) — mutasi terbaru
  dulu + kode pola, nama user, `kode_ref` personel bila ada.

## 2. API

- `TerakarsaApp.Shared/Tni/TniStokModels.cs`.
- `TniStokService` + `TniStokController` (`api/tni/stok`, `TNI_PDH`):
  POST `setoran`, POST `keluar`, GET `saldo`, GET `riwayat`.

## 3. Client — `/tni/stok`

Tiga tab, gaya mockup layar 9:

**Setoran**
- Tanggal (default hari ini), segmented **Kemeja | Celana**.
- Baris isian: pola (`SearchableSelect`, hanya pola aktif sesuai jenis) +
  jumlah (input angka besar, `inputmode="numeric"`) + tombol hapus baris.
  **+ Tambah baris**. Satu setoran boleh berisi kemeja **dan** celana —
  segmented hanya memfilter pilihan pola baris baru; tiap baris menyimpan
  jenisnya sendiri.
- Kartu total: "140 kemeja · 70 celana".
- Bar bawah: **Simpan setoran** → konfirmasi ringkas → sukses: form kosong
  lagi, tampil toast.

**Keluarkan**
- Pilih jenis: **Barang rusak** atau **Koreksi stok**; pola; jumlah (koreksi:
  pilih tambah/kurangi); alasan (wajib). Simpan dengan konfirmasi.

**Sisa stok**
- Segmented Kemeja | Celana, cari kode, toggle "hanya yang ada stoknya".
- Kartu per pola: kode besar; **saldo**; stok bebas; dijatah; kebutuhan sisa.
  Saldo **minus → merah** dengan keterangan "setoran belum dicatat?".
  Stok bebas < kebutuhan → chip kuning "kurang n".
- Tap kartu → riwayat mutasi pola itu.

## Verifikasi

1. Setoran 80 `LD_102_P` + 60 `LD_104_P` + 70 celana `32_P` dalam satu simpan
   → tiga baris `MASUK`; saldo & stok bebas sesuai.
2. `RUSAK` 2 tanpa alasan → ditolak SP; dengan alasan → saldo turun 2.
3. `KOREKSI` +3 dan −1 dengan alasan → saldo menyesuaikan.
4. Pola nonaktif tidak muncul di pilihan setoran.
5. Tampilan 360px rapi. `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan membuat tabel/kolom saldo.
- Jangan menyediakan input manual `TERPAKAI` atau `BONGKAR`.
- Jangan menyediakan edit/hapus mutasi.
- Jangan memblokir apa pun berdasarkan stok bebas — hanya informasi.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi, sebagai
markdown link.

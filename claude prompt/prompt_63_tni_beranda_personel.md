# Prompt 63 — PDH TNI AD: Beranda Module & Halaman Personel

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 62. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup layar 1: `claude prompt/tni/mockup_tampilan.html`.

## Konteks

Beranda menjadi pintu masuk module di HP. Halaman Personel dipakai siapa saja
untuk mencari satu orang (kode, NRP, atau nama), melihat posisinya di alur, dan
membetulkan data — terutama 147 baris yang sedang dikonfirmasi ke satuan
(NRP kembar/kurang digit, gender vs pola).

## 1. SQL — `sql/tni/sp_Personel.sql`

Semua status diambil dari `tni.v_personel.status_progres`.

- `tni.SIS_Beranda_Summary` (`@OrderId`) — satu baris: `total`,
  `dicetak` (status ≠ BELUM_CETAK), `dapat_set` (SET_JADI + MASUK_BOX +
  TERKIRIM), `masuk_box` (MASUK_BOX + TERKIRIM), `terkirim`,
  `set_belum_box` (SET_JADI), `kartu_belum_scan` (DICETAK),
  `perlu_review` (`status_data = 'PERLU_REVIEW'`),
  `pembatalan_menunggu` (dari `tni.pembatalan` status MENUNGGU — tabel sudah
  ada sejak Prompt 60 walau halamannya di Prompt 68).
- `tni.SIS_Personel_List` (`@OrderId`, `@Search` null, `@AreaId` null,
  `@SatuanId` null, `@Status` null, `@PerluReview` bit = 0, `@PageNumber`,
  `@PageSize`) — `@Search` dicocokkan ke `kode_ref` (awalan), `nrp` (awalan),
  atau `nama` (LIKE). Kolom: id, kode_ref, pangkat, nama, nrp, satuan_code,
  satuan_name, kode pola kemeja & celana, `status_progres`, `box_code`,
  `status_data`. Urut `kode_ref`. Kembalikan juga total baris (pola paging yang
  ada).
- `tni.SIS_Personel_GetById` (`@Id`) — semua kolom personel + area/satuan +
  pola + ukuran jadi pola (untuk perbandingan) + nama user `printed_by`,
  `set_by`, `boxed_by` + `box_code`, `packed_at`, `shipped_at`.
- `tni.SIS_Personel_Manage` — `@Action`:
  - `UPDATE` — `nrp`, `nama`, `pangkat`, `no_hp`, `gender`. NRP harus unik di
    order aktif (pesan jelas bila bentrok, sebut `kode_ref` pemiliknya).
    **Satuan, `kode_ref`, `qr_token` tidak bisa diubah.**
  - `SET_POLA` (`@PolaKemejaId`, `@PolaCelanaId`) — **ditolak bila
    `set_at` terisi**: "Set sudah jadi — ajukan pembatalan set dulu."
    Pola harus hidup & aktif.
  - `MARK_REVIEWED` (`@Catatan`) — `status_data = 'DIPERBAIKI'`, catatan
    ditambahkan ke `catatan_review`.
  - `DELETE` — soft delete, hanya bila `printed_at IS NULL` (kartu belum pernah
    dicetak). Alasan wajib, disimpan ke `catatan_review`.

## 2. API

- `TerakarsaApp.Shared/Tni/TniPersonelModels.cs`.
- `TniPersonelService` + `TniPersonelController` (`api/tni/personel`,
  `TNI_PDH`): GET `summary`, GET list (query param di atas), GET `{id}`,
  PUT `{id}`, PUT `{id}/pola`, POST `{id}/reviewed`, DELETE `{id}`.

## 3. Client

### `/tni` — Beranda (mockup layar 1)
- Header "PDH TNI AD 2026", subjudul instansi · jumlah personel (dari
  `TniOrderState`).
- 4 kotak angka: Kartu dicetak · Dapat set · Masuk box · Terkirim.
- Kartu progres masuk box (%), chip kuning "n set belum masuk box", chip abu
  "n kartu belum di-scan", chip merah "n perlu review" (tap → daftar personel
  terfilter review).
- Grid tile 3 kolom: Perintah Kerja (`/tni/perintah-kerja`), Scan
  (`/tni/scan`), Box (`/tni/box`), Stok (`/tni/stok`), Personel
  (`/tni/personel`), Pembatalan (`/tni/pembatalan`, badge jumlah menunggu),
  Dashboard (`/tni/dashboard`), Import (`/tni/import`), Master Pola
  (`/tni/pola`). Halaman yang dibuat di prompt berikutnya boleh belum ada.

### `/tni/personel` — daftar
- Kotak cari besar di atas (kode / NRP / nama, debounce ±300 ms).
- Filter dalam bottom sheet: area, satuan, status, "perlu review saja".
- Daftar kartu: **kode_ref** tebal · pangkat · nama; baris kedua pola kemeja &
  celana (monospace); `TniStatusChip`; chip merah kecil bila perlu review.
- Muat bertahap (tombol "Muat lagi" / scroll), 30 per halaman.

### `/tni/personel/{id}` — detail
- Kepala: kode_ref besar, nama, pangkat, satuan · rawatan, `TniStatusChip`.
- Kartu **Pola**: dua kotak besar KEMEJA & CELANA (seperti kartu cetak), tap →
  ukuran jadi pola.
- Kartu **Riwayat**: Dicetak (waktu, oleh, berapa kali) · Set jadi (waktu,
  oleh) · Masuk box (kode box, waktu, oleh) · Terkirim.
- Kartu **Identitas** (NRP, No HP, TB/BB, gender, kategori) dan **Ukuran badan**
  (8 + 7; untuk `TU_SIZING` tulis "Tidak hadir pengukuran — memakai pola
  standar").
- Kartu **Review** bila `status_data = 'PERLU_REVIEW'`: isi catatan + tombol
  **Tandai sudah diperbaiki**.
- Aksi: **Ubah data** (form identitas), **Ubah pola** (dua pilihan dengan
  `SearchableSelect`, nonaktif bila sudah set jadi dengan penjelasan),
  **Hapus** (hanya bila belum pernah dicetak). Tombol "Cetak ulang kartu" dan
  "Ajukan batal" ditambahkan di Prompt 65 dan 68 — sisakan tempatnya.

## Verifikasi

1. Cari `DTJ-0` → personel Ditajenad; cari sebagian NRP dan sebagian nama →
   ketemu.
2. Ubah NRP ke NRP milik orang lain → ditolak dengan pesan menyebut kode
   pemiliknya.
3. Ubah pola personel yang belum set → berhasil; angka di `/tni/pola` (jumlah
   pemakai) ikut berubah.
4. Filter "perlu review" menampilkan baris REVIEW dari import Prompt 62.
5. Beranda tampil benar di lebar 360px. `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan izinkan perubahan satuan, `kode_ref`, atau `qr_token` dari UI mana pun.
- Jangan menulis ulang logika status — pakai `tni.v_personel`.
- Jangan membuat cetak kartu atau pembatalan di prompt ini.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi, sebagai
markdown link.

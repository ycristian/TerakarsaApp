# Prompt 61 — PDH TNI AD: Master Pola, Seed Wilayah, & Fondasi UI Module

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 60. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup: `claude prompt/tni/mockup_tampilan.html`.

> **CATATAN REKONSTRUKSI (2026-10-02).** Isi asli prompt ini hilang: export prompt
> seri 60–69 bergeser satu file — teks Prompt 60 mendarat di nama file `prompt_61_*`,
> dan nama file `prompt_60_*` terisi mockup kartu 80mm. Prompt ini disusun ulang dari
> jejak yang masih ada:
> - dua script seed di `sql/tni/` yang sudah berjudul "(Prompt 61)" —
>   `seed_tni_master (2).sql` dan `seed_tni_pola.sql`;
> - Prompt 63 yang menyebut tile **Master Pola → `/tni/pola`**, `TniOrderState`,
>   dan verifikasi "angka di `/tni/pola` (jumlah pemakai) ikut berubah";
> - Prompt 62 & 64 yang butuh pencarian pola lewat `kode` (hidup & aktif) dan
>   dropdown pola aktif per jenis.
>
> Keputusan owner saat rekonstruksi: **cakupan hanya master pola**. Area rawatan &
> satuan cukup lewat seed, TANPA halaman CRUD — Prompt 63 memang hanya menyebut tile
> "Master Pola", dan mengubah `satuan_code` setelah personel di-import berbahaya
> (kode itu sudah melekat di `kode_ref` kartu dan kode box).

## Konteks

Pola = **ukuran jadi pakaian**, bukan ukuran badan personel. Acuan potong untuk
±1/3 personel yang tidak hadir pengukuran (`TU_SIZING`) murni dari pola, jadi
master ini harus benar sebelum apa pun di-import.

Sumbernya `Sampel data TNI AD 2026.xlsx` (sheet SizePack Kemeja & SizePack
Celana) — sudah digenerate jadi `sql/tni/seed_tni_pola.sql`: **98 pola kemeja**
dan **59 pola celana**. Master wilayah (1 order, 3 area rawatan, 38 satuan) ada
di `sql/tni/seed_tni_master (2).sql`, nama area & satuan diambil PERSIS dari data
mentah Google Form supaya pencocokan import tidak gagal.

Halaman `/tni/pola` dipakai untuk melihat & membetulkan pola, dan untuk
menonaktifkan pola yang tidak dipakai lagi. Prompt ini juga memasang fondasi UI
module yang dipakai prompt 62–69: `tni.css` dan `TniOrderState`.

## 1. Seed (jalankan apa adanya)

1. `sql/tni/seed_tni_master (2).sql` — order `PDH_OPMAT_2026` (aktif), 3 area
   (`BDG`, `CMH`, `BGR`), 38 satuan.
   `satuan_code` di seed = **usulan**; owner sudah menyetujui dipakai apa adanya
   (dikonfirmasi 2026-10-02). Setelah personel di-import, kode ini **tidak boleh
   diubah lagi**.
   Verifikasi keunikan `satuan_code` dalam satu order sebelum commit (Prompt 60
   menitipkan aturan ini ke SP/seed, bukan ke index).
2. `sql/tni/seed_tni_pola.sql` — 98 pola kemeja + 59 pola celana.

Keduanya idempotent. Catat jumlah akhir dan bandingkan dengan angka `PRINT`
di masing-masing script.

## 2. SQL — `sql/tni/sp_Pola.sql`

Satu set SP untuk kedua jenis pola, dibedakan `@JenisItem` (`KEMEJA`/`CELANA`) —
supaya UI, API, dan DTO tidak dobel.

- `tni.SIS_Pola_List` (`@JenisItem`, `@OrderId`, `@Search` null,
  `@HanyaAktif` bit = 0) — satu result set berisi kolom yang sama untuk kedua
  jenis (kolom yang tidak relevan dikembalikan NULL):
  `pola_id, jenis_item, kode, kode_alt, target_gender, size_angka,
  lingkar_dada_acuan, is_active`, seluruh ukuran jadi, dan
  **`jumlah_pemakai`** = COUNT personel hidup di order itu yang memakai pola ini
  (dari `tni.v_personel`). `@Search` dicocokkan ke `kode` atau `kode_alt` (LIKE).
  Urut: angka pada kode (`lingkar_dada_acuan` untuk kemeja, `size_angka` untuk
  celana), lalu `target_gender`.
- `tni.SIS_Pola_GetById` (`@JenisItem`, `@Id`) — satu baris, bentuk sama.
- `tni.SIS_Pola_Manage` — `@Action`:
  - `CREATE` / `UPDATE` — `kode` wajib & unik per jenis (pesan Indonesia bila
    bentrok); `target_gender` harus sesuai jenis (kemeja:
    `P`,`PG`,`W`,`W_PG`,`WH`,`WH_PG`; celana: `P`,`W`); kemeja wajib
    `lingkar_dada_acuan`, celana wajib `size_angka`. Ukuran jadi boleh NULL.
    `lingkar_manset` hanya untuk pola hijab (`WH`,`WH_PG`) — di luar itu
    dipaksa NULL.
  - `SET_AKTIF` (`@IsActive`) — menonaktifkan pola **tidak** mengubah personel
    yang sudah memakainya; pola nonaktif hanya hilang dari pilihan baru
    (setoran stok Prompt 64, ubah pola Prompt 63) dan ditolak saat import
    (Prompt 62).
  - `DELETE` — soft delete, **ditolak bila `jumlah_pemakai` > 0** atau pola
    sudah pernah dipakai di `tni.stok_mutasi`: "Pola dipakai n personel —
    nonaktifkan saja." Alasan tidak diminta (master, bukan transaksi).

## 3. SQL — `sql/tni/sp_Order.sql`

- `tni.SIS_Order_Aktif` — satu baris order `is_active = 1`:
  `order_id, order_code, order_name, instansi, tahun, target_qty`,
  `total_personel` (COUNT `tni.v_personel`), `jumlah_area`, `jumlah_satuan`.
  Dipakai `TniOrderState` dan subjudul beranda (Prompt 63).

## 4. API

- `TerakarsaApp.Shared/Tni/TniMasterModels.cs` — DTO order aktif + pola
  (satu bentuk untuk kemeja & celana).
- `TniOrderService` + `TniOrderController` (`api/tni/order`, `TNI_PDH`):
  GET `aktif`.
- `TniPolaService` + `TniPolaController` (`api/tni/pola`, `TNI_PDH`):
  GET list (`jenis`, `search`, `hanyaAktif`), GET `{jenis}/{id}`, POST, PUT
  `{jenis}/{id}`, PUT `{jenis}/{id}/aktif`, DELETE `{jenis}/{id}`.

## 5. Client — fondasi module

- `wwwroot/css/tni.css` — dipakai seluruh halaman `/tni/...`: palet dari mockup
  (navy `#042C53`, coral `#C8553D`, gold `#C99A2E`, hijau `#1E8E5A`), kartu,
  chip, bar aksi bawah yang menempel, angka besar, kode monospace.
  Daftarkan di `index.html`.
  **Jangan** memakai class Bootstrap `rounded` atau `border` (tema meng-override
  keduanya) — border & radius selalu inline / lewat class sendiri.
- `Services/TniOrderState.cs` — state order aktif (dimuat sekali, bisa
  di-refresh), dipakai header semua halaman `/tni/...`.
- `Services/TniOrderApiService.cs`, `Services/TniPolaApiService.cs`.
- Registrasi di `Program.cs` client.

## 6. Client — `/tni/pola`

Mobile-first (dipakai di HP), kartu bukan tabel lebar:
- Header: judul "Master Pola" + `CloseButton`.
- Segmented **Kemeja | Celana**, kotak cari kode (debounce ±300 ms), toggle
  "hanya aktif".
- Daftar kartu per pola: **kode besar monospace** + chip `target_gender`; chip
  abu "nonaktif" bila `is_active = 0`; baris kecil `kode_alt` bila ada; baris
  **"n pemakai"**. Tap kartu → sheet detail ukuran jadi (label–nilai, angka
  tanpa `.0`) + tombol **Ubah**, **Nonaktifkan/Aktifkan**, **Hapus** (hanya
  bila 0 pemakai).
- Bar bawah: **+ Pola baru**.
- Form (sheet): kode, kode alt, target gender, acuan/size angka, lalu ukuran
  jadi sesuai jenis. Field `lingkar_manset` hanya tampil untuk `WH`/`WH_PG`.

## Verifikasi

1. Jalankan kedua seed → `pola_kemeja` hidup **98**, `pola_celana` hidup **59**,
   area **3**, satuan **38**; `satuan_code` unik dalam order. Jalankan ulang →
   tidak ada baris dobel.
2. `/tni/pola` menampilkan 98 kemeja & 59 celana; cari `LD_102` → ketemu; cari
   `14,5-3` (kode_alt) → ketemu `LD_102_P`.
3. Tambah pola kemeja baru dengan kode yang sudah ada → ditolak SP dengan pesan
   Indonesia.
4. Pola hijab (`LD_96_WH`) menampilkan `lingkar_manset`; pola `LD_96_W` tidak.
5. Nonaktifkan satu pola → chip "nonaktif" muncul; `jumlah_pemakai` tetap.
6. Hapus pola yang `jumlah_pemakai` = 0 → berhasil; `LD_118_PG` tidak ada di
   master (memang begitu — dipakai 1 baris data mentah dan akan `TOLAK` di
   Prompt 62).
7. `SIS_Order_Aktif` mengembalikan `PDH_OPMAT_2026` dengan `total_personel` 0.
8. Tampilan 360px rapi. `dotnet build TerakarsaApp.slnx -v q` sukses.

## Yang TIDAK boleh dilakukan

- Jangan membuat halaman CRUD area rawatan / satuan (keputusan owner).
- Jangan mengubah `satuan_code` atau nama area/satuan hasil seed — nama dipakai
  mencocokkan import, kode melekat di `kode_ref` & kode box.
- Jangan menghapus pola yang masih dipakai personel atau punya mutasi stok —
  nonaktifkan.
- Jangan membuat SP personel, stok, box, scan, atau import di prompt ini.
- Jangan memakai class Bootstrap `rounded` / `border`.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi (dengan
hasilnya), masing-masing sebagai markdown link.

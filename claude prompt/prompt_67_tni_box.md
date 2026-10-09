# Prompt 67 — PDH TNI AD: Box, Scan "Masuk Box", & PDF Isi Box A4

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 66. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup layar 6–8: `claude prompt/tni/mockup_tampilan.html`.
> Desain PDF: `claude prompt/tni/mockup_isi_box_a4.html` (sudah disetujui owner).

## Konteks

Set yang sudah jadi dimasukkan ke kardus. Box **dimiliki satuan**; sisa yang
sedikit boleh digabung ke **box gabungan** lintas satuan dalam satu rawatan.
Isi 44–50 set (kapasitas default 50). Kode box tidak pernah diganti:
`BDG-DTJ-01` (rawatan-satuan-urut), gabungan `BDG-GAB-01`.

Staff memilih box dulu, lalu scan beruntun semua kartu yang masuk. Setelah
selesai, supervisor **menutup box** di module Box → **PDF A4 isi box** siap
**diunduh** dan dicetak di printer mana saja (tidak lewat print job). Lalu box
ditandai terkirim.

## 1. SQL — `sql/tni/sp_Box.sql`

### `tni.SIS_Box_Manage` — `@Action`
- `CREATE` (`@OrderId`, `@SatuanId` null, `@AreaId` null, `@UserId`):
  - Box satuan: `@SatuanId` wajib → area dari satuan; `urut` = MAX(urut) box
    satuan itu (termasuk yang terhapus) + 1; kode
    `area_code-satuan_code-RIGHT('0'+urut,2)` (≥100 → biarkan 3 digit).
  - Box gabungan: `@SatuanId` NULL, `@AreaId` wajib; urut per area untuk
    gabungan; kode `area_code-GAB-nn`.
  - Kunci dengan `sp_getapplock` supaya dua HP tidak dapat nomor sama.
  - Kembalikan `box_id`, `box_code`.
- `CLOSE` — tolak bila sudah ditutup / terkirim / isi 0. Set `packed_at`,
  `packed_by`.
- `SHIP` — tolak bila belum ditutup / sudah terkirim. Set `shipped_at`,
  `shipped_by`.
- `DELETE` — soft delete, hanya box kosong & belum ditutup; alasan ke
  `keterangan`. Nomornya tidak dipakai ulang.

### `tni.SIS_Scan_MasukBox` (`@Kode`, `@BoxId`, `@UserId`)
`@Kode` = token atau `kode_ref` (sama dengan Prompt 66). Satu result set:
`hasil`, `pesan`, data personel, `box_code`, `isi`, `kapasitas`.

| Kondisi (dicek berurutan) | `hasil` | Warna UI |
|---|---|---|
| personel tidak ditemukan | `TIDAK_DIKENAL` | merah |
| box tidak ada / terhapus | `DITOLAK` "box tidak ditemukan" | merah |
| box sudah ditutup atau terkirim | `DITOLAK` "box sudah ditutup" | merah |
| belum Set Jadi | `DITOLAK` "belum scan Set Jadi" | merah |
| sudah di box ini | `SUDAH` | kuning |
| sudah di box lain | `DITOLAK` "sudah di box {kode}" | merah |
| box satuan & satuan personel berbeda | `DITOLAK` "bukan satuan box ini ({satuan})" | merah |
| box gabungan & area personel berbeda | `DITOLAK` "bukan rawatan box ini" | merah |
| isi sudah = kapasitas | `DITOLAK` "box penuh" | merah |
| selain itu | `OK` | hijau |

`OK`: dalam transaksi, `UPDATE … SET box_id, urut_dalam_box = MAX+1,
boxed_at, boxed_by WHERE personel_id = @Id AND boxed_at IS NULL` — cek
`@@ROWCOUNT` (0 → hitung ulang hasil). Hitung `isi` sesudahnya.

### Baca
- `tni.SIS_Box_List` (`@OrderId`, `@AreaId` null, `@SatuanId` null,
  `@Status` null `TERBUKA/TERTUTUP/TERKIRIM`, `@Gabungan` bit null) —
  box_code, area, satuan (atau "Gabungan"), status turunan, isi, kapasitas,
  `packed_at`, `shipped_at`, jumlah satuan berbeda di dalamnya.
- `tni.SIS_Box_GetById` (`@BoxId`) — 3 result set: header (+ nama `packed_by`);
  isi urut `urut_dalam_box` (kode_ref, pangkat, nama, nrp, satuan_name, kode
  pola kemeja & celana); rekap jumlah per pola kemeja & per pola celana.

## 2. API

- `TerakarsaApp.Shared/Tni/TniBoxModels.cs`.
- `TniBoxService` + `TniBoxController` (`api/tni/box`, `TNI_PDH`): GET list,
  GET `{id}`, POST (create), POST `{id}/tutup`, POST `{id}/kirim`,
  DELETE `{id}`, GET `{id}/pdf`.
- `TniScanController`: tambah POST `masuk-box` (`kode`, `boxId`).

### PDF isi box — `TniBoxPdfService`
- Pakai **SkiaSharp** (`SKDocument.CreatePdf`) yang sudah terpasang di API —
  jangan menambah library PDF baru.
- Hanya untuk box **tertutup/terkirim**; box terbuka → 400 "Tutup box dulu".
- A4 portrait, margin ±10 mm, font Arial (fallback sans-serif). Susunan
  **persis** mockup `mockup_isi_box_a4.html`:
  1. Kiri: "DAFTAR ISI BOX" + judul order. Kanan: **kode box besar**. Garis tebal.
  2. Baris info 4 kolom: Rawatan · Satuan (atau "Gabungan") · Isi n set ·
     Ditutup (tanggal jam).
  3. Tabel bergaris: No · Kode · Pangkat · Nama · NRP · Kemeja · Celana ·
     **Diterima** (kolom kosong untuk dicentang). Untuk box gabungan sisipkan
     kolom Satuan setelah Kode. Kode pola tebal.
  4. Tiga kotak: rekap kemeja (kode × jumlah), rekap celana, tanda tangan
     "Dipacking oleh — Nama:" dan "Diterima oleh — Nama / tgl:".
  5. Kaki: "Ditutup oleh: {nama} · dicetak dari Terakarsa" | "{kode box} · hal x/y".
- 50 baris harus muat satu halaman; lebih dari itu lanjut halaman berikut
  dengan header tabel diulang.
- Nama file unduhan: `{box_code}.pdf`.

## 3. Client

### `/tni/box` — daftar (mockup layar 7)
- Pilih satuan (`SearchableSelect`, ingat pilihan terakhir di localStorage);
  filter status.
- Kartu per box: kode box (monospace tebal), chip Terbuka (kuning) / Tertutup
  (navy) / Terkirim (hijau), isi n / kapasitas + progress, tautan **⬇ PDF** bila
  sudah ditutup.
- Bagian **Box gabungan {rawatan}** di bawah.
- Bar bawah: **+ Box gabungan** dan **+ Buka box baru** (konfirmasi, tampilkan
  kode yang didapat besar-besar: "Tulis BDG-DTJ-02 di kardus").

### `/tni/box/{id}` — detail (mockup layar 8)
- Header kode box · satuan · status · isi.
- Kartu rekap pola, daftar isi bernomor.
- Bar bawah sesuai status: Terbuka → **Tutup box & buat PDF** (coral,
  konfirmasi "Tutup box berisi n set? Box tidak bisa menerima scan lagi.") →
  setelah sukses tampilkan **⬇ Unduh PDF** dan **Tandai terkirim**. Tertutup →
  **Unduh PDF** + **Tandai terkirim**. Terkirim → **Unduh PDF**.
- Unduh: ambil bytes dengan auth lalu simpan lewat helper unduh file yang sudah
  dipakai export Excel; kalau belum ada, buat fungsi JS `downloadFileFromBytes`.
- Box terbuka & kosong: tombol **Hapus box**.

### `/tni/scan` — aktifkan mode **Masuk Box** (mockup layar 6)
- Pilih box dulu: daftar box **terbuka** (filter satuan), ingat box terakhir di
  localStorage.
- Kartu box aktif di atas kamera: kode box, satuan, **isi / kapasitas** +
  progress, tautan "Ganti box". Saat penuh, tampilkan ajakan "Box penuh — tutup
  box di menu Box".
- Scan beruntun memakai `tniScanner.js` yang sama; banner & riwayat sesi
  seperti mode Set Jadi.

### `/t/{token}` (login)
Tambah tombol **Masukkan ke box** bila status `SET_JADI` → pilih box terbuka
satuan/rawatannya → panggil `masuk-box`.

## Verifikasi

1. Buka box Ditajenad dua kali → `BDG-DTJ-01`, `BDG-DTJ-02`; box gabungan
   Bandung → `BDG-GAB-01`.
2. Scan masuk: personel Ditajenad yang sudah set → hijau, isi bertambah;
   personel satuan lain → merah "bukan satuan box ini"; belum set → merah;
   scan ulang → kuning.
3. Box gabungan menerima personel satuan mana pun di Bandung, menolak Cimahi.
4. Tutup box → scan masuk ditolak "box sudah ditutup"; unduh PDF → satu halaman
   A4 sesuai mockup (uji 48 baris dan box gabungan dengan kolom Satuan).
5. Tandai terkirim → status personel di dalamnya `TERKIRIM`.
6. `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan mengirim PDF ke print job — PDF hanya diunduh.
- Jangan mengizinkan buka kembali box dari halaman ini (hanya lewat pembatalan
  di Prompt 68).
- Jangan menambah library PDF selain SkiaSharp yang sudah ada.
- Jangan menyimpan file PDF ke disk; dibuat saat diminta.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi + satu
contoh PDF hasil uji, sebagai markdown link.

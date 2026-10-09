# Prompt 66 — PDH TNI AD: Scan "Set Jadi" & Halaman QR `/t/{token}`

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 65. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup layar 5: `claude prompt/tni/mockup_tampilan.html`.

## Konteks

Staff packing mengambil kartu, mengambil kemeja & celana sesuai pola di kartu,
menyatukannya ke plastik, lalu **scan QR kartu** dengan HP → set tercatat jadi
dan stok kemeja & celana **berkurang otomatis**. Ratusan kartu per hari, jadi
kamera **tetap menyala** dan scan beruntun tanpa menekan tombol.

QR di kartu berisi `https://app.terakarsa.id/t/<qr_token>`. Kalau dibuka dengan
kamera biasa (bukan dari menu Scan), link itu membuka halaman `/t/{token}`:
publik tanpa login (status saja), atau lengkap dengan aksi bila sudah login.

HTTPS sudah berjalan (dipakai kamera di module station).

## 1. SQL — `sql/tni/sp_Scan.sql`

### `tni.SIS_Scan_SetJadi` (`@Kode`, `@UserId`)
`@Kode` boleh `qr_token` **atau** `kode_ref` (input manual bila QR rusak):
cari personel hidup di order aktif dengan `qr_token = @Kode`, bila tidak ada
coba `kode_ref = @Kode`.

Kembalikan **satu result set** (bukan RAISERROR untuk kasus yang dibedakan
warna di UI): `hasil` (`OK` / `SUDAH` / `TIDAK_DIKENAL`), `pesan`,
`personel_id, kode_ref, pangkat, nama, satuan_name, kode pola kemeja & celana`,
`set_at`, `set_by_nama`, `saldo_kemeja`, `saldo_celana` (setelah dikurangi).

- `TIDAK_DIKENAL` — tidak ditemukan.
- `SUDAH` — `set_at` sudah terisi: pesan "sudah tercatat {jam} oleh {nama}".
- `OK` — dalam transaksi:
  - `UPDATE tni.personel SET set_at = SYSDATETIME(), set_by = @UserId
    WHERE personel_id = @Id AND set_at IS NULL` — cek `@@ROWCOUNT`; 0 berarti
    HP lain lebih dulu → kembalikan `SUDAH` (aman dari scan bersamaan).
  - Insert dua baris `tni.stok_mutasi` `TERPAKAI` qty −1 (kemeja & celana,
    `personel_id` diisi, `tanggal` hari ini).
  - Stok **boleh minus** (setoran mungkin belum dicatat) — tidak diblok.
- Kartu yang belum pernah dicetak (`printed_at IS NULL`) tetap boleh di-scan.

### `tni.SIS_Public_ByToken` (`@Token`)
Untuk halaman publik — **hanya** `kode_ref`, pangkat, nama, `satuan_name`,
`status_progres`, `set_at`, `box_code`, `boxed_at`, `shipped_at`. Tanpa NRP,
No HP, ukuran badan.

### `tni.SIS_Personel_ByToken` (`@Token`)
Untuk user login — `personel_id` + data seperti `SIS_Personel_GetById`.

## 2. API

- `TerakarsaApp.Shared/Tni/TniScanModels.cs`.
- `TniScanController` (`api/tni/scan`, `TNI_PDH`): POST `set-jadi` (`kode`).
- Endpoint publik **GET saja** `api/public/tni/{token}` — tambahkan di
  `PublicController` yang ada (pola `bundles/{serial}`), tanpa autentikasi.
- GET `api/tni/personel/by-token/{token}` (`TNI_PDH`).

## 3. Client

### JS — `wwwroot/js/tniScanner.js`
Pakai library **html5-qrcode yang sudah ada di `wwwroot/lib`** (dipakai
`bundleScanner` di station) — jangan CDN, scan harus jalan tanpa internet.
Bedanya dengan `bundleScanner`: kamera **tidak berhenti** setelah satu hasil.
- `start(elementId, dotNetRef)`, `stop()`, kamera belakang.
- Abaikan teks yang sama yang terbaca lagi dalam **3 detik** (kartu masih di
  depan kamera).
- `feedback(jenis)` — bunyi pendek WebAudio (ok: nada tinggi; sudah: dua nada;
  gagal: nada rendah) + `navigator.vibrate` bila ada.
- Minta Wake Lock layar selama kamera aktif bila browser mendukung.

### `/tni/scan` (gaya mockup layar 5)
- Segmented **Set Jadi | Masuk Box** — tab Masuk Box ditambahkan di Prompt 67;
  sekarang tampilkan nonaktif dengan teks "segera".
- Area kamera di atas, teks "Arahkan ke QR di kartu".
- Ambil token dari teks hasil scan: bila mengandung `/t/` ambil segmen
  sesudahnya, selain itu pakai apa adanya.
- **Banner hasil** di bawah kamera: hijau `✓ DTJ-118 · Adi kurniawan` +
  "LD_96_P · 34_P — set tercatat"; kuning untuk `SUDAH`; merah untuk
  `TIDAK_DIKENAL`. Bila saldo pola jadi minus, tambahkan baris kecil merah
  "Stok LD_96_P minus — setoran belum dicatat?".
- **Riwayat sesi** (20 terakhir, di memori halaman): titik warna, kode + nama,
  jam. Header: nama user · "sesi ini n set".
- Input manual di bawah (ketik kode personel / token) untuk QR rusak.
- Saat permintaan ke API sedang berjalan, scan berikutnya diantrekan, jangan
  dibuang.

### `/t/{token}` — halaman publik
Rute publik tanpa layout sidebar, meniru pola halaman `/b/{serial}` yang ada.
- **Belum login**: kartu sederhana — kode personel, pangkat, nama, satuan, chip
  status, dan baris status (Set jadi: tanggal · Masuk box: kode box · Terkirim:
  tanggal). Teks kecil "Komplain ukuran akan tersedia di sini." (fitur menyusul).
- **Sudah login & punya module `TNI_PDH`**: tampilkan data lengkap seperti
  detail personel + tombol sesuai status: **Tandai set jadi** (bila belum),
  **Buka detail personel**. Tombol "Masuk box" & "Ajukan batal" ditambahkan di
  Prompt 67 & 68.

## Verifikasi

1. Scan kartu `DICETAK` → hijau; personel `SET_JADI`; dua mutasi `TERPAKAI`
   −1; stok bebas & saldo turun sesuai.
2. Scan kartu yang sama lagi (setelah 3 detik) → kuning, tidak ada mutasi baru.
3. Dua HP scan kartu yang sama bersamaan → tepat satu `OK`, satu `SUDAH`.
4. Ketik `kode_ref` manual → berfungsi seperti scan.
5. Buka `/t/{token}` di jendela incognito → hanya data minimal, tanpa NRP & HP.
6. Uji di HP sungguhan lewat HTTPS. `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan menolak scan karena stok kurang/minus.
- Jangan membuat endpoint tulis tanpa login.
- Jangan menampilkan NRP, No HP, atau ukuran badan di halaman publik.
- Jangan mengubah `bundleScanner` atau alur scan station.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi, sebagai
markdown link.

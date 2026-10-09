# Prompt 68 — PDH TNI AD: Pengajuan & Persetujuan Pembatalan Scan

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 67. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup layar 10: `claude prompt/tni/mockup_tampilan.html`.

## Konteks

Salah scan pasti terjadi: set salah ukuran yang terlanjur di-scan jadi, atau
masuk ke box yang salah. Scan **tidak bisa dihapus langsung** — staff
mengajukan pembatalan dengan alasan, lalu user yang punya module
`TNI_PDH_APPROVE` menyetujui atau menolak di **satu halaman**.

| Jenis | Efek bila disetujui |
|---|---|
| `BOX` — batal masuk box | Personel keluar dari box, kembali "Dapat set" dan bisa di-scan ulang ke box yang benar. Box yang sudah **ditutup** otomatis **terbuka lagi** — PDF lama tidak berlaku. |
| `SET` — batal set jadi | Personel kembali "Kartu tercetak"; kemeja & celana **kembali ke stok** (mutasi `BONGKAR` +1 masing-masing). |

## 1. SQL — `sql/tni/sp_Pembatalan.sql`

### `tni.SIS_Pembatalan_Manage` — `@Action`
- `AJUKAN` (`@PersonelId`, `@Jenis`, `@Alasan` wajib, `@UserId`):
  - `BOX`: personel harus `boxed_at` terisi; box belum terkirim — kalau sudah
    terkirim tolak "Box sudah terkirim, tidak bisa dibatalkan."
  - `SET`: personel harus `set_at` terisi **dan** `boxed_at` kosong — kalau masih
    di box tolak "Batalkan masuk box dulu."
  - Tolak bila sudah ada pengajuan `MENUNGGU` untuk personel & jenis yang sama.
  - Simpan `box_id_asal` untuk jenis `BOX`.
- `SETUJUI` (`@Id`, `@Catatan` null, `@UserId`) — satu transaksi, **periksa
  ulang** kondisi seperti `AJUKAN` (data bisa berubah sejak diajukan; bila tidak
  lagi valid → tolak dengan pesan jelas, status tetap MENUNGGU):
  - `BOX`: bila box `packed_at` terisi → kosongkan `packed_at`/`packed_by`
    (box terbuka lagi) dan catat di `keterangan` box "Dibuka ulang karena
    pembatalan #id". Kosongkan `box_id`, `urut_dalam_box`, `boxed_at`,
    `boxed_by` personel.
  - `SET`: kosongkan `set_at`, `set_by`; insert dua mutasi `BONGKAR` +1
    (kemeja & celana sesuai pola personel saat ini, `personel_id` diisi, alasan
    = "Pembatalan #id").
  - Status `DISETUJUI`, `diputus_oleh/at`, `catatan_keputusan`.
- `TOLAK` (`@Id`, `@Catatan` **wajib**, `@UserId`) — status `DITOLAK`.
- Hanya pengajuan `MENUNGGU` yang bisa diputus.

### Baca
- `tni.SIS_Pembatalan_List` (`@OrderId`, `@Status` null, paging) — jenis,
  status, kode_ref, nama, satuan, kode box asal & kode box sekarang, pola,
  alasan, pengaju + waktu, pemutus + waktu + catatan. `MENUNGGU` terlama dulu;
  riwayat terbaru dulu.
- `tni.SIS_Pembatalan_ByPersonel` (`@PersonelId`) — riwayat satu personel.

## 2. API

- `TerakarsaApp.Shared/Tni/TniPembatalanModels.cs`.
- `TniPembatalanController` (`api/tni/pembatalan`):
  - POST `ajukan` — `TNI_PDH`.
  - GET list, POST `{id}/setujui`, POST `{id}/tolak` — **`TNI_PDH_APPROVE`**.
  - GET `personel/{personelId}` — `TNI_PDH`.

## 3. Client

### Tombol **Ajukan batal**
Muncul di: detail personel (`/tni/personel/{id}`), halaman `/t/{token}` saat
login, dan pada item riwayat sesi di `/tni/scan` (tap item → sheet aksi).
- Jenis otomatis dari status: `MASUK_BOX` → "Batal masuk box {kode box}";
  `SET_JADI` → "Batal set jadi". Status lain → tombol tidak muncul.
- Form alasan wajib (contoh placeholder: "Salah ambil box", "Celana salah
  ukuran"). Bila sudah ada pengajuan menunggu, tampilkan chip "Menunggu
  persetujuan" sebagai pengganti tombol.
- Detail personel menampilkan riwayat pembatalan.

### `/tni/pembatalan` (module `TNI_PDH_APPROVE`, gaya mockup layar 10)
- Tab **Menunggu (n)** | **Riwayat**.
- Kartu per pengajuan: chip jenis (kuning "Batal masuk box" / merah "Batal set
  jadi"), jam, kode + nama, keterangan efek (mis. "di BDG-DTJ-02" atau "kemeja
  LD_104_P + celana 33_P kembali ke stok"), alasan + pengaju.
- Tombol **Tolak** (catatan wajib) dan **Setujui** (catatan opsional;
  peringatan bila box sudah tertutup: "Box BDG-DTJ-02 akan terbuka lagi dan PDF
  harus dicetak ulang.").
- Badge jumlah menunggu di tile Beranda sudah membaca angka dari
  `SIS_Beranda_Summary` (Prompt 63) — pastikan ter-refresh setelah memutus.

## Verifikasi

1. Batal masuk box pada box terbuka → setujui → personel keluar, isi box
   berkurang, bisa di-scan ke box lain.
2. Batal masuk box pada box **tertutup** → setujui → box terbuka lagi,
   `keterangan` terisi; tutup lagi → PDF baru tanpa personel tadi.
3. Ajukan batal set untuk personel yang masih di box → ditolak "Batalkan masuk
   box dulu".
4. Batal set → setujui → status `DICETAK`, saldo kedua pola +1 (mutasi
   `BONGKAR`), scan Set Jadi ulang berhasil.
5. Tolak tanpa catatan → ditolak. User tanpa `TNI_PDH_APPROVE` tidak bisa
   membuka halaman maupun memanggil endpoint putusan.
6. `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan menyediakan hapus/kosongkan scan langsung tanpa pengajuan.
- Jangan menghapus baris mutasi `TERPAKAI` — pengembalian stok selalu lewat
  `BONGKAR`.
- Jangan membatalkan box yang sudah terkirim.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi, sebagai
markdown link.

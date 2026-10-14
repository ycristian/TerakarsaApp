# Module Stok Benang + App Android — Keputusan Desain

Disepakati 14 Okt 2026. Dasar untuk Prompt 71–77.

---

## 1. Tujuan

Pencatatan stok benang di gudang: masuk, keluar ke line, kembali, pindah rak, dan stock
opname. Dipakai **admin gudang lewat HP** (login akun, bukan station). Material lain
(kain, asesoris mesin) nanti jadi module & tabel sendiri dengan pola yang sama — tidak
digabung.

## 2. Prinsip

| Prinsip | Artinya |
|---|---|
| Stok sistem ≠ stock opname | Stok sistem = hasil catatan movement. SO = fakta fisik. Disimpan terpisah, saling menguatkan. SO minus → ada yang hilang/keluar tak tercatat; SO plus → ada yang masuk/pindah tak tercatat. |
| Stok hanya berubah lewat movement | SO tidak menimpa stok. Menyamakan stok = movement ADJUST yang menunjuk baris opname-nya. |
| Alasan wajib | Setiap ADJUST punya kategori alasan + keterangan, supaya log bisa direview. Diposting langsung oleh admin gudang saat SO ditutup, tanpa approval. |
| Siapa yang input tercatat | `created_by` = user login. Itu alasan pakai login, bukan station. |

## 3. Model data (schema `inv`)

- **SKU** (`thread_items`): jenis benang (Poly/Cotton/…), merk, warna, kode warna, jenis kones (KECIL/BESAR), satu foto, `sku_code`.
- **Whole** dihitung **per SKU per lokasi** (`thread_stocks`), tidak per kones. Label kones whole = barcode **SKU** (sama untuk semua kones SKU itu). Scan SKU → isi qty.
- **Split** = kones bekas pakai yang kembali. Satu baris per kones (`thread_split_cones`): kode unik `SP-xxxxxx`, berat **netto gram** (tanpa tube), lokasi, status IN_STOCK / ISSUED / EMPTY. Dapat label sendiri saat kembali.
- **Semua yang kembali dianggap split.** Kones yang tidak kembali dianggap habis.
- **Lokasi** (`thread_locations`): rak A1, B5, X12… Satu SKU bisa di banyak rak, tiap rak tahu jumlahnya.
- **Movement** (`thread_movements`): RECEIVE, ISSUE, RETURN, MOVE, ADJUST (+ varian split). Untuk ISSUE wajib pilih project **atau** isi keterangan.
- Tidak ada lot/batch, tidak ada harga (menyusul setelah module purchase), tidak ada stok minimum.

## 4. Stock opname

- Satu **sesi** mencakup rak-rak yang dipilih. Per rak bisa disimpan draft.
- Saat sesi ditutup, rekonsiliasi per SKU: plus di satu rak + minus di rak lain dengan jumlah sama → diusulkan **MOVE** (stok total tidak berubah). Sisa selisih → **ADJUST** dengan alasan.
- Snapshot qty sistem disimpan di baris opname saat dihitung.
- **Stok awal** gudang (banyak stok tanpa purchase) dimasukkan lewat **opname pertama** dengan alasan `STOK_AWAL`.

Kategori alasan ADJUST: `HILANG`, `SALAH_INPUT`, `PINDAH_TAK_TERCATAT`, `MASUK_TAK_TERCATAT`, `RUSAK`, `STOK_AWAL`, `LAINNYA` (keterangan wajib untuk LAINNYA).

## 5. Label

- Ukuran **30×20 mm**, QR (bukan barcode batang), posisi di paper tube bawah kones.
- Isi QR: `TB:<sku_code>` untuk label SKU, `TS:<cone_code>` untuk label split.
- Dicetak lewat antrian print job yang sudah ada (job type `THREAD_SKU_LABEL`, `THREAD_SPLIT_LABEL`, render RAW_TSPL). Printer: TSC TTP-244 Pro (roll 30×20) di meja timbang, dan/atau Xprinter XP-P323B lewat app Android (Prompt 77).

## 6. Akses

- Module `INV_THREAD` (semua halaman gudang benang).
- Role baru **Admin Gudang** — hanya punya module ini, setelah login langsung ke landing `/gudang/benang` (pola seperti role satpam).
- Owner tetap bisa masuk untuk review log.

## 7. UI

- Halaman responsif: HP satu panel, tablet (≥900px) dua panel (daftar + detail). Mockup referensi: `claude prompt/benang/mockup/`.
- Landing module sendiri (bukan menu nyempil di admin).
- Alur: Scan → (SKU) Ambil / (split) Ambil split; Kembali = timbang → split baru → cetak label; Opname per rak.

## 8. App Android "Terakarsa" (.NET MAUI, APK sideload)

- Shell **WebView** untuk web yang sudah ada, bukan UI baru.
- Login native (API JWT yang sama) → token disuntik ke WebView.
- Pilih tujuan setelah login: Dashboard Utama / Admin Gudang / PO TNI — ikut module user.
- Setting → **Print Service**: pilih printer Bluetooth yang sudah di-pairing, daftarkan HP sebagai `print_device`, test print, aktif/nonaktif. Foreground service polling antrian print job, kirim TSPL via Bluetooth klasik (SPP) ke XP-P323B.
- Kamera diteruskan ke WebView supaya scan QR jalan.
- **Dua alamat server**: lokal (IP server pabrik) dan publik (`https://app.terakarsa.id`). App cek `api/health` lokal (timeout 1–2 s) saat dibuka dan saat jaringan berubah; ada → lokal, tidak → publik. Sertifikat self-signed lokal ditanam/dipercaya di app (opsi 1). Catatan infra (opsi 2, tidak dipakai): DNS override di router.

## 9. Prompt 71–77

| Prompt | Isi |
|---|---|
| 71 | Schema `inv`, tabel, SP master, module + role Admin Gudang, master SKU (+foto), master lokasi, landing responsif |
| 72 | Movement: Terima, Ambil (whole/split), Kembali & timbang, Pindah rak, Scan |
| 73 | Label 30×20: job type, TsplBuilder 30×20, cetak dari halaman |
| 74 | Stock opname: sesi, hitung per rak, rekonsiliasi, ADJUST dengan alasan |
| 75 | Riwayat & review log, dashboard landing (angka ringkas) |
| 76 | App Android: MAUI shell, login, pilih tujuan, WebView, kamera, APK |
| 77 | App Android: print service Bluetooth, registrasi device, routing |

Eksekusi DDL: Claude Code langsung ke database (seperti seri TNI), target DB dikonfirmasi di Prompt 71.

# Prompt 73 — Stok Benang: Label 30×20 mm (SKU & Split)

Dijalankan SETELAH Prompt 72.

## 1. Job type & routing — `sql/inv/seed_73_thread_label_jobs.sql` (idempotent)

- Dua job type: `THREAD_SKU_LABEL` (ref_id = thread_item_id, payload berisi `copies`) dan
  `THREAD_SPLIT_LABEL` (ref_id = thread_split_cone_id).
- Routing default ke device `LABEL` yang sudah ada (TSC TTP-244 Pro, render_mode RAW_TSPL)
  lewat `print_job_routes`. Owner akan mengganti roll ke 30×20 mm, atau memindah route ke
  device Android (Prompt 77) — keduanya cukup lewat SQL, tidak perlu kode.

## 2. SP — `sql/inv/sp_73_ThreadLabel.sql`

- `inv.SIS_ThreadLabel_Enqueue` @Kind ('SKU'|'SPLIT'), @RefId, @Copies (SKU saja, 1–50),
  @UserId → INSERT `print_jobs` (pakai SP insert print job yang sudah ada kalau ada; kalau
  INSERT langsung, ikuti kolom yang dipakai bundle). Payload JSON (FOR JSON PATH, snake_case):

```json
SKU:   {"kind":"SKU","qr":"TB:BN-POL-AST-2041-B","color_code":"2041","color_name":"Merah Cabe",
        "brand":"Astra","thread_type":"Poly","cone_size":"BESAR","copies":3}
SPLIT: {"kind":"SPLIT","qr":"TS:SP-000413","cone_code":"SP-000413","color_code":"2041",
        "color_name":"Merah Cabe","brand":"Astra","thread_type":"Poly","weight_gram":420}
```

- Setelah `RETURN` sukses (Prompt 72) **jangan** auto-enqueue — cetak lewat tombol, supaya
  admin bisa menempel label setelah yakin.

## 3. PrintService — `TsplBuilder`

Tambahkan `BuildThreadLabel(payload)` **tanpa mengubah** `BuildBundleLabel`:

- `SIZE 30 mm,20 mm`, `GAP 2 mm,0`, `DIRECTION 1`, `CLS`.
- QR di kiri: `QRCODE 16,16,M,4,A,0,"<qr>"` (cell 4 pada 203 dpi ≈ 12–13 mm untuk isi ≤ 25
  karakter; kalau isi lebih panjang turunkan ke 3). Sesuaikan supaya tinggi QR ≤ 14 mm.
- Teks di kanan (x ≈ 125 dot): baris 1 `color_code` font "3" (besar), baris 2 `color_name`
  font "2", baris 3 `brand · thread_type`, baris 4 untuk SPLIT: `cone_code`, baris 5
  `weight_gram g` tebal; untuk SKU baris 4: `KECIL`/`BESAR`.
- Potong teks yang melebihi lebar (maks ~14 karakter font 2).
- `PRINT 1,<copies>`.
- Worker: tambah kedua job type ke daftar LABEL hardcode di `Worker.cs` (sesuai catatan di
  `print_kupon_job_types` bahwa job LABEL tetap hardcode).
- DryRun menghasilkan `.tspl` seperti biasa.

## 4. API & Client

- `POST api/gudang/benang/labels/sku/{itemId}?copies=n`, `POST labels/split/{splitId}`.
- Detail SKU: tombol **Cetak label SKU** → modal jumlah copy (default 1).
- Halaman Kembali: setelah simpan, tombol **Cetak label** untuk cone yang baru dibuat;
  tampilkan **preview label** di layar (HTML, 240×160 px, QR dirender client-side dengan
  library QR yang sudah dipakai di project — kalau belum ada, pakai `qrcode` dari npm
  dibundel lokal, bukan CDN) seperti mockup `Kembali.dc.html`.
- Detail split cone (dari scan `TS:`): tombol **Cetak ulang label**.
- Status cetak: ikut status `print_jobs` (PENDING/DONE/ERROR) seperti label bundle.

## 5. Verifikasi

DryRun PrintService: enqueue satu SKU label dan satu split label → dua file `.tspl` di
`./dryrun/` dengan `SIZE 30 mm,20 mm`. Lampirkan isi salah satu file di ringkasan.

## Yang TIDAK boleh dilakukan

- Jangan ubah layout `BUNDLE_LABEL` dan job type lain.
- Jangan ubah `print_devices` yang sudah ada selain menambah route.

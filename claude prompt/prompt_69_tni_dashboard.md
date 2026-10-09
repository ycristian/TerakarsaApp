# Prompt 69 — PDH TNI AD: Dashboard Progres & Kebutuhan Size

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 68. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup layar 11: `claude prompt/tni/mockup_tampilan.html`.

## Konteks

Owner dan supervisor perlu dua jawaban cepat dari HP:
1. **Sisa pekerjaan per rawatan** (dan per satuan): berapa yang belum dicetak,
   belum dapat set, belum masuk box — beserta persentasenya.
2. **Kebutuhan size**: per pola, berapa yang masih dibutuhkan dibanding stok —
   dasar memprioritaskan pola mana di lantai produksi.

## 1. SQL — `sql/tni/sp_Dashboard.sql`

Semua status dari `tni.v_personel`, stok dari `tni.v_stok_pola`.

### `tni.SIS_Dashboard_Progres` (`@OrderId`)
2 result set:
1. Per **area**: `area_id, area_code, area_name, total, belum_cetak, dicetak`
   (kartu tercetak belum set), `set_jadi` (dapat set belum box), `masuk_box`
   (di box, belum terkirim), `terkirim`, `persen_box` = (masuk_box + terkirim)
   / total, `persen_kirim` = terkirim / total, `box_terbuka`, `box_tertutup`,
   `box_terkirim`.
2. Per **satuan**: kolom yang sama + `satuan_id, satuan_code, satuan_name`.

### `tni.SIS_Dashboard_KebutuhanSize` (`@OrderId`, `@AreaId` null, `@JenisItem`)
Per pola (`KEMEJA` atau `CELANA`):
- `butuh` = personel **belum dapat set** (`BELUM_CETAK` + `DICETAK`) dengan
  pola itu — dalam area bila `@AreaId` diisi;
- `saldo` dan `stok_bebas` — **stok global** (stok tidak dibagi per area;
  tulis keterangan ini di UI);
- `selisih` = `saldo − butuh` (negatif = harus diproduksi).
Hanya pola dengan `butuh > 0` atau `saldo <> 0`. Urut `selisih` naik (paling
kurang di atas).

## 2. API

- `TerakarsaApp.Shared/Tni/TniDashboardModels.cs`.
- `TniDashboardController` (`api/tni/dashboard`, `TNI_PDH`): GET `progres`,
  GET `kebutuhan-size?areaId=&jenis=`.
- GET `kebutuhan-size/excel` — export dengan ClosedXML (pola export yang sudah
  ada): kolom Pola · Butuh · Saldo · Stok bebas · Selisih, satu sheet per jenis,
  judul berisi area & tanggal. Untuk diteruskan ke lantai produksi.

## 3. Client — `/tni/dashboard` (gaya mockup layar 11)

Dua tab: **Progres** | **Kebutuhan size**.

**Progres**
- Kartu per rawatan: nama, persen masuk box besar, progress bar bertumpuk
  (terkirim · masuk box · dapat set · dicetak · belum cetak) dengan legenda
  kecil; baris angka: Belum dicetak · Belum dapat set · Belum masuk box ·
  Terkirim; ringkas box terbuka / tertutup / terkirim.
- Tap kartu → daftar satuan rawatan itu dengan angka yang sama, urut persen
  terendah dulu. Tap satuan → `/tni/personel` terfilter satuan itu.

**Kebutuhan size**
- Pilih rawatan (atau "Semua rawatan") dan segmented **Kemeja | Celana**.
- Daftar baris: kode pola (monospace) · "butuh n · stok n" · **selisih**
  (merah bila minus, hijau "cukup" bila ≥ 0).
- Ringkasan di atas: total kekurangan set untuk pilihan itu.
- Tombol **Unduh Excel** di bar bawah.

Muat ulang otomatis tiap 60 detik selama halaman terbuka + tombol refresh.

## Verifikasi

1. Jumlah kolom status per area = total personel area itu.
2. Angka per area cocok dengan penjumlahan satuan-satuannya.
3. Setelah satu scan Set Jadi: `belum dapat set` turun 1 dan `butuh` pola terkait
   turun 1 di kebutuhan size.
4. Excel terunduh dan angkanya sama dengan layar.
5. Tampilan 360px rapi. `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan menulis ulang logika status atau saldo — pakai kedua view.
- Jangan membagi stok per area.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi, sebagai
markdown link. Tutup seri dengan ringkasan: semua route `/tni/...` yang tersedia
dan semua SP di schema `tni`.

# Prompt 65 — PDH TNI AD: Perintah Kerja, Saran Prioritas, & Cetak Kartu 80mm

> Seri PDH TNI AD (60–69). Jalankan setelah Prompt 64. Aturan seri: CLAUDE.md
> bagian "Module PDH TNI AD". Mockup layar 2–4: `claude prompt/tni/mockup_tampilan.html`.
> Desain kartu: `claude prompt/tni/mockup_kartu_80mm.html`.

## Konteks

Supervisor packing memilih **satuan** yang mau dikerjakan. Sistem membantu
dengan **saran prioritas** untuk menyelesaikan satu rawatan: satuan yang
seluruh sisanya bisa dipenuhi dari stok ditandai **"Bisa tuntas"**. Kalau tidak
ada yang bisa tuntas, daftar cukup menjadi **preview** berapa set yang bisa
dibuat per satuan. Sifatnya saran — supervisor bebas memilih.

Lalu kartu personel dicetak lewat **antrian print job yang sudah ada**
(`dbo.print_jobs` + `TerakarsaApp.PrintService`) ke **printer thermal 80mm**,
langsung (bukan PDF) supaya cepat.

## Definisi

- **Kandidat** = personel order aktif berstatus `BELUM_CETAK`.
- **Stok bebas** per pola = `tni.v_stok_pola.stok_bebas` (Prompt 64).
- **Bisa dibuat** (algoritma greedy, dihitung di API, bukan SP — ini saran,
  bukan validasi): salin stok bebas kemeja & celana; telusuri kandidat urut
  `kode_ref`; seseorang terhitung bila stok bebas pola kemejanya **dan** pola
  celananya masing-masing > 0, lalu kurangi keduanya 1. Kalau salah satu kosong,
  orang itu masuk "belum bisa" dengan alasan pola yang kurang.
- Hitungan **per satuan** memakai salinan stok bebas yang **segar** untuk tiap
  satuan (angka antarsatuan bisa saling tumpang tindih — beri keterangan kecil
  di layar). Hitungan **per rawatan** = greedy atas seluruh kandidat rawatan itu,
  urut `satuan_code` lalu `kode_ref`.
- **Bisa tuntas** = sisa > 0 dan bisa dibuat = sisa.

## 1. SQL — `sql/tni/sp_PerintahKerja.sql`

- `tni.SIS_PerintahKerja_Data` (`@OrderId`, `@AreaId` null, `@SatuanId` null)
  — 3 result set: (1) kandidat (`personel_id, kode_ref, pangkat, nama,
  area_id, satuan_id, satuan_code, satuan_name, pola_kemeja_id, kode kemeja,
  pola_celana_id, kode celana`); (2) stok bebas kemeja per pola; (3) stok bebas
  celana per pola.
- `tni.SIS_PerintahKerja_Dijatah` (`@OrderId`, `@SatuanId`) — personel
  `DICETAK` (kartu tercetak, belum set) satuan itu + `printed_at`, nama
  `printed_by`.
- `tni.SIS_Personel_Cetak` (`@PersonelIds` JSON, `@QrBaseUrl`, `@UserId`) —
  satu transaksi, urut `kode_ref`. Untuk tiap personel hidup di order aktif
  (status apa pun — dipakai juga untuk cetak ulang):
  - insert `dbo.print_jobs` (`job_type = 'TNI_KARTU'`, `ref_id = personel_id`,
    `payload` = JSON bentuk `TniKartuPayload` dirakit dengan `FOR JSON PATH`,
    `created_by = @UserId`; status default PENDING);
  - set `printed_at = SYSDATETIME()`, `printed_by`, `print_count += 1`.
  - Kembalikan jumlah job dibuat.
- `tni.SIS_Personel_LepasCetak` (`@PersonelIds` JSON, `@UserId`) — untuk
  kartu yang batal dikerjakan: set `printed_at = NULL`, `printed_by = NULL`
  **hanya** bila `set_at IS NULL` (yang sudah set dilewati & dilaporkan).
  `print_count` tetap. Tujuannya mengembalikan stok bebas.

Isi payload (`qrContent` = `@QrBaseUrl + '/t/' + qr_token`):
`kodeRef, judulOrder` ("PDH OPMAT 2026 - KODAM III/SILIWANGI"),
`satuanName, areaName, pangkat, nama, nrp, noHp, tinggiBadan, beratBadan,
polaKemeja, polaCelana, kategori, ukuranKemeja` (8 pasang label–nilai, urutan
seperti kartu), `ukuranCelana` (7 pasang), `qrContent`.

## 2. Shared & API

- `TerakarsaApp.Shared/PrintJobs/TniKartuPayload.cs` — kelas payload (dipakai API
  dan PrintService).
- `TerakarsaApp.Shared/Tni/TniPerintahKerjaModels.cs` — ringkasan rawatan,
  daftar satuan (sisa, bisaDibuat, persen, bisaTuntas), detail satuan
  (bisaDibuat[], belumBisa[] + alasan, ringkasan kekurangan per pola).
- Konfigurasi API baru `Tni:QrBaseUrl` = `https://app.terakarsa.id` (appsettings
  + Development). **Jangan** memakai `App:PublicBaseUrl` — itu alamat lokal
  untuk label bundle.
- `TniPerintahKerjaService` + `TniPerintahKerjaController`
  (`api/tni/perintah-kerja`, `TNI_PDH`):
  - GET `rawatan` → per area: total kandidat, bisa dibuat, jumlah satuan bisa
    tuntas, total personel & persen selesai (masuk box / total).
  - GET `rawatan/{areaId}/satuan` → daftar satuan terurut sesuai aturan saran.
  - GET `satuan/{satuanId}` → detail bisa / belum bisa + kekurangan.
  - GET `satuan/{satuanId}/dijatah`.
  - POST `cetak` (`personelIds[]`) → `SIS_Personel_Cetak`.
  - POST `lepas` (`personelIds[]`) → `SIS_Personel_LepasCetak`.

### Aturan urutan daftar satuan
1. **Bisa tuntas** dulu, dari sisa paling sedikit.
2. Sisanya dari **bisa dibuat** terbanyak.
3. Satuan tanpa kandidat (sisa 0) di paling bawah, chip "Semua sudah dicetak".
Bila tidak ada satuan bisa tuntas, UI tidak menampilkan bagian "Saran".

## 3. PrintService — job type `TNI_KARTU`

Dukungan printer 80mm **sudah di-push** ke PrintService. **Baca kode PrintService
yang ada dulu** (Worker, konfigurasi, builder, helper raw print) dan ikuti pola
konfigurasi/routing printer yang sudah ada. Tambahkan:

- Routing: `TNI_KARTU` → printer 80mm; `BUNDLE_LABEL` tetap ke TSC. Kalau
  ternyata routing per job type belum ada, tambahkan konfigurasi peta
  job type → nama printer dengan default ke `PrinterName` lama.
- `TniKartuEscPosBuilder` — ESC/POS, Font A 48 kolom, teks ASCII (karakter di
  luar ASCII diganti padanan terdekat, `·` → `-`). Susunan mengikuti mockup:
  1. Tengah: judul order (normal). Kode personel **lebar+tinggi ganda, tebal**.
     Satuan - rawatan (potong 48 karakter).
  2. Garis `=`. Identitas rata kiri: `Pangkat : …`, `Nama    : …` (nama panjang
     dibungkus ke baris berikut dengan indentasi 10), `NRP     : …`,
     `No HP   : …`, `TB / BB : 166 cm / 60 kg`.
  3. Garis `=`. Baris label `KEMEJA` | `CELANA` (dua kolom 24), lalu kedua kode
     pola **lebar+tinggi ganda, tebal** dalam dua kolom — info utama untuk staff
     saat mengambil barang.
  4. Garis `-`. `UKURAN BADAN - KEMEJA` (tebal) + 8 baris label kiri, angka rata
     kanan kolom 48; `UKURAN BADAN - CELANA` + 7 baris. Angka tanpa `.0`.
     Untuk `kategori = TU_SIZING`: ganti seluruh blok dengan dua baris tengah
     **TIDAK HADIR PENGUKURAN** / `Memakai pola standar sesuai size di atas`.
  5. Garis `=`. **QR native** (`GS ( k`: model 2, module size 6, error level M,
     store, print) di tengah berisi `qrContent`. Di bawahnya alamat tanpa
     `https://`, lalu `Scan QR untuk cek status & komplain ukuran`.
  6. Feed 4 baris, partial cut (`GS V 66 0`).
- DryRun: tulis `./dryrun/{id}.escpos.bin` **dan** `./dryrun/{id}.txt`
  (pratinjau teks baris demi baris) supaya bisa dicek tanpa printer.
- **Percepatan**: bila klaim mengembalikan job sebanyak `BatchSize`, langsung
  klaim lagi tanpa menunggu `PollSeconds` (cetak ratusan kartu tidak tertahan
  jeda polling). Perilaku untuk antrian kosong tidak berubah.
- Perbarui README PrintService: job type baru, konfigurasi printer 80mm.

## 4. Client — `/tni/perintah-kerja`

Gaya mockup layar 2–4:

1. **Pilih rawatan** — kartu per rawatan: nama + kode, "Sisa n dari total",
   progress persen selesai, "Bisa dibuat dari stok: **n set**", chip hijau
   "n satuan bisa tuntas". Catatan kecil stok bebas kemeja & celana total.
2. **Daftar satuan** — bagian **SARAN — BISA TUNTAS** (kartu ber-border hijau,
   chip "Bisa tuntas") lalu **LAINNYA — PREVIEW** (persen + progress). Catatan
   kecil: "Angka tiap satuan dihitung sendiri-sendiri dari stok bebas yang sama."
3. **Detail satuan** — tab **Bisa dibuat (n)** | **Belum bisa (n)** |
   **Sudah dicetak (n)**:
   - Bisa dibuat: daftar tercentang (kode, pangkat, nama, dua kode pola),
     "Pilih semua". Bar bawah: "**n** dipilih" + **Cetak n kartu** (konfirmasi)
     → toast "n kartu masuk antrian cetak" → data dimuat ulang.
   - Belum bisa: ringkasan kekurangan per pola di atas ("kurang 20 kemeja
     `LD_108_P`"), lalu daftar orang + pola yang kurang (merah).
   - Sudah dicetak: kartu tercetak yang belum di-scan set. Centang + bar bawah
     **Lepas kartu** (konfirmasi: "Kartu fisik ini tidak akan dikerjakan
     sekarang? Stok bebas akan dikembalikan.").

### Cetak ulang dari detail personel (`/tni/personel/{id}`)
Tambahkan tombol **Cetak ulang kartu** (konfirmasi, tampilkan berapa kali sudah
dicetak) → endpoint `cetak` dengan satu id.

## Verifikasi

1. Dengan stok contoh Prompt 64, saran & angka "bisa dibuat" masuk akal;
   satuan yang dibuat bisa tuntas (isi stok persis kebutuhannya) muncul paling
   atas.
2. Cetak 5 kartu → 5 baris `print_jobs` `TNI_KARTU`; personel jadi `DICETAK`;
   stok bebas pola terkait turun; angka satuan lain menyesuaikan.
3. PrintService DryRun → 5 file `.txt` sesuai susunan mockup (cek satu
   `UKUR` dan satu `TU_SIZING`), QR berisi `https://app.terakarsa.id/t/<token>`.
4. Lepas 2 kartu → kembali `BELUM_CETAK`, stok bebas naik lagi.
5. Label bundle TSC tetap tercetak normal (regresi).
6. `dotnet build` sukses.

## Yang TIDAK boleh dilakukan

- Jangan mengunci stok saat cetak dan jangan membuat mutasi stok di prompt ini.
- Jangan membuat PDF untuk kartu personel.
- Jangan mengubah payload/format `BUNDLE_LABEL`.
- Jangan memakai `kode_ref` sebagai isi QR.

Setelah selesai: daftar file dibuat/diubah + script yang dieksekusi + contoh
isi satu file `.txt` DryRun, sebagai markdown link.

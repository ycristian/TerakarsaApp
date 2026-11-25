# Prompt 97 — CCTV: ganti kualitas rekaman per kamera (Sub ↔ Main)

Lanjutan module CCTV (Prompt 91–94). Baca dulu kode yang sudah ada sebelum menulis apa pun:
schema `cctv`, tabel `cctv.cameras` (kolom `name` = nama path MediaMTX), halaman Master Kamera
`/cctv/kamera`, halaman CCTV Live, dan `CctvMediaMtxClient`. Ikuti pola, penamaan, dan cara
otorisasi yang sudah dipakai di sana.

## Tujuan

Dari form Edit Kamera, user memilih kualitas rekaman kamera: **Sub** atau **Main**.
Terakarsa lalu mengubah sumber path kamera itu di MediaMTX lewat API, tanpa mengedit
`mediamtx.yml` dan tanpa restart MediaMTX. Tetap satu path dan satu catatan rekaman per kamera;
yang berganti hanya kualitasnya.

## Latar belakang teknis

- MediaMTX v1.21 jalan di mesin yang sama dengan API TMOS. API kontrolnya di `http://127.0.0.1:9997`.
- Sumber tiap path berbentuk `rtsp://USER:KODE@IP:554/Streaming/Channels/102/`.
  Dua digit terakhir menentukan aliran: `01` = main (1920×1080), `02` = sub (768×432).
  Digit di depannya adalah nomor channel dan tidak boleh diubah.
- `mediamtx.yml` berisi semua kamera dengan sumber sub. File ini adalah kondisi awal tiap kali
  MediaMTX menyala.
- Perubahan lewat API hanya berlaku di memori MediaMTX. Setelah MediaMTX restart, semua path
  kembali ke isi file. Karena itu **database Terakarsa adalah sumber kebenaran** dan Terakarsa
  wajib menyinkronkan ulang secara berkala.
- Sebelum memakai endpoint, pastikan bentuknya di MediaMTX yang sedang jalan:
  `GET /v3/config/paths/get/{name}` (mengembalikan konfigurasi path, termasuk `source`) dan
  `PATCH /v3/config/paths/patch/{name}` dengan body `{ "source": "..." }`.
  Kalau bentuknya berbeda di versi ini, sesuaikan dan catat di laporan.

## Yang dikerjakan

### 1. SQL (file manual-run di folder `sql/`, tidak dieksekusi otomatis)

Tambah ke `cctv.cameras`:

- `record_quality` — nilai `SUB` atau `MAIN`, NOT NULL, default `SUB`, dengan CHECK constraint.
- `record_quality_updated_at` — nullable.
- `record_quality_updated_by` — nullable, mengikuti cara kolom "diubah oleh" lain di schema ini.

Script harus aman dijalankan ulang (cek kolom sudah ada atau belum). Sesuaikan SP/endpoint baca
dan simpan kamera yang sudah ada supaya membawa kolom ini; jangan membuat jalur simpan baru
kalau jalur edit kamera yang ada bisa diperluas.

### 2. `CctvMediaMtxClient`

Tambah dua kemampuan:

- Membaca `source` sebuah path dari API konfigurasi.
- Mengubah `source` sebuah path (PATCH).

Tambah satu fungsi murni (mudah di-unit-test) untuk menukar kualitas pada URL sumber:

- Cocokkan akhiran `/Streaming/Channels/<channel><01|02>` dengan atau tanpa `/` di ujung.
- Ganti hanya dua digit terakhir sesuai kualitas yang diminta. Bagian lain URL (user, kode, IP,
  port, nomor channel, garis miring penutup) tidak boleh berubah.
- Kalau URL tidak cocok dengan pola itu, kembalikan hasil "tidak didukung" dan jangan PATCH.

### 3. Sinkronisasi

- **Saat simpan di Edit Kamera:** simpan pilihan ke database dulu, lalu langsung coba terapkan
  ke MediaMTX. Kalau MediaMTX tidak bisa dihubungi atau PATCH gagal, simpan **tetap berhasil**;
  status kamera menjadi "menunggu sinkron".
- **Background service (hosted service) tiap 30 detik:** untuk tiap kamera aktif di
  `cctv.cameras`, baca `source` path-nya di MediaMTX, bandingkan kualitasnya dengan
  `record_quality`, dan PATCH **hanya kalau berbeda**. Berlaku dua arah (database Main tapi
  MediaMTX sub, dan sebaliknya). Jangan PATCH kalau sudah sama, karena PATCH memutus sambungan
  kamera beberapa detik.
- Interval 30 detik dibuat bisa diatur lewat konfigurasi (`Cctv:...`), default 30.
- Status sinkron per kamera (sesuai / menunggu sinkron / tidak didukung / path tidak ada di
  MediaMTX) cukup disimpan di memori service dan disajikan lewat endpoint baca kamera. Tidak
  perlu kolom status di database.
- Kalau MediaMTX mati, service tidak boleh membanjiri log; cukup satu peringatan saat mulai gagal
  dan satu info saat tersambung kembali.

### 4. UI

- **Form Edit Kamera (`/cctv/kamera`):** tambah pilihan "Kualitas rekaman" dengan dua opsi:
  - `Sub — 768×432, ringan`
  - `Main — 1080p, data sekitar 4× lebih besar`

  Di bawahnya teks bantu singkat: "Main memakai WiFi dan harddisk sekitar 4× lebih banyak.
  Rekaman terputus beberapa detik saat diganti."
- **Hak akses:** sama persis dengan hak edit kamera yang sudah ada. Jangan menambah permission baru.
- **Badge:** tampilkan badge kecil `HD` pada kartu kamera di CCTV Live dan pada baris kamera di
  Master Kamera untuk kamera dengan `record_quality = MAIN`.
- **Status:** kalau kamera "menunggu sinkron", tampilkan penanda kecil di Master Kamera
  (misalnya teks abu "menunggu sinkron"). Untuk "tidak didukung" atau "path tidak ada",
  tampilkan teks peringatan singkat di form edit.
- Ikuti komponen dan gaya yang sudah dipakai di halaman CCTV; jangan menambah library UI.

## Batasan keras (tidak boleh dilanggar)

- **Jangan mengedit, menulis ulang, atau membaca-untuk-diubah `mediamtx.yml`.** Semua perubahan
  hanya lewat API MediaMTX.
- **User dan kode RTSP kamera tidak boleh disimpan** di database, kode, konfigurasi Terakarsa,
  maupun log. URL sumber hanya boleh ada di memori selama proses baca → tukar → PATCH.
  Kalau perlu menulis log, samarkan bagian `user:kode@`.
- URL sumber tidak boleh dikirim ke browser dalam bentuk apa pun.
- Jangan mengubah nama path, cara live view, token stream (`Cctv:StreamTokenSecret`), maupun
  halaman playback, selain menambah badge.
- Jangan menyentuh path MediaMTX yang tidak terdaftar di `cctv.cameras`
  (misalnya `cam8_75_main`, `tes_nvr4`, `cam8_85_h264`).
- Jangan mengubah schema selain `cctv`, dan jangan mengubah SP di luar module CCTV.
- API MediaMTX dipanggil lewat `127.0.0.1`, memakai konfigurasi alamat yang sudah dipakai
  `CctvMediaMtxClient`.

## Tidak termasuk prompt ini

- Path terpisah untuk main (`*_main`) dan penyambungan NVR ke MediaMTX.
- Pengaturan bitrate kamera.
- Penanganan khusus kamera H8c (`cam8_85`): main stream-nya bisa H.265 dan tidak tampil di
  browser. Jangan dibuatkan logika khusus; cukup catat di laporan kalau terlihat saat tes.
- Peta pabrik.

## Uji terima

Pakai `cam8_75` untuk semua uji.

1. Ubah ke Main di Edit Kamera. Dalam ±15 detik `GET /v3/paths/get/cam8_75` menunjukkan
   1920×1080, dan badge `HD` muncul di CCTV Live dan Master Kamera.
2. Buka `mediamtx.yml`: isinya tidak berubah.
3. Restart MediaMTX. Path kembali sub, lalu dalam ≤ 60 detik kembali 1920×1080 tanpa campur tangan.
4. Ubah ke Sub. Path kembali 768×432 dan badge hilang.
5. Matikan MediaMTX, ubah ke Main, simpan. Simpan berhasil dan status "menunggu sinkron".
   Nyalakan MediaMTX; dalam ≤ 60 detik path menjadi 1920×1080 dan status hilang.
6. Rekaman tetap berada di satu folder path (`cam8_75`) dan playback melewati titik pergantian
   kualitas tanpa error.
7. Periksa log aplikasi: tidak ada user atau kode RTSP yang tertulis.
8. Unit test fungsi penukar URL: `102/` → `101/`, `101` → `102`, channel dua digit
   (mis. `1002` → `1001`), dan URL yang tidak cocok → "tidak didukung".

## Urutan deploy

1. Jalankan script SQL di `sql/` secara manual.
2. Deploy API/aplikasi TMOS.
3. Jalankan uji terima 1–7 dengan `cam8_75`.
4. (Dikerjakan Ivander, bukan Claude Code) hapus path `cam8_75_main` dan `tes_nvr4` dari
   `mediamtx.yml` supaya kamera itu tidak terekam dua kali.

## Laporan

Setelah selesai, buat `claude prompt/report/97-cctv-kualitas-rekaman-report.md` berisi:

- Ringkasan yang dikerjakan dan file yang berubah (termasuk nama script SQL).
- Bentuk endpoint MediaMTX yang benar-benar dipakai, dan bedanya dari prompt ini kalau ada.
- Hasil tiap butir uji terima (lulus / gagal / belum diuji, dengan alasan).
- Hal yang menyimpang dari prompt dan alasannya.
- Temuan atau risiko yang perlu diputuskan Ivander.

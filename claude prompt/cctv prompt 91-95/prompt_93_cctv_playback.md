# Prompt 93 — CCTV: Playback Rekaman

Lanjutan Prompt 92. Mockup: `claude prompt/cctv/mockup/Playback.dc.html`.

## 0. Inspeksi dulu

Panggil server playback MediaMTX dan catat hasil nyatanya di laporan (jangan
mengandalkan ingatan soal parameter — cocokkan dengan dokumentasi MediaMTX v1.21):
- `{MtxPlaybackBaseUrl}/list?path=cam8_83` — bentuk JSON (awal + durasi tiap rentang),
  dan apakah mendukung filter `start`/`end`.
- `{MtxPlaybackBaseUrl}/get?path=cam8_83&start=<RFC3339>&duration=60` — content type,
  apakah bisa diputar `<video>` langsung, apakah mendukung `format=mp4`, dan apakah
  mendukung HTTP Range (seek).

## 1. API

Token stream yang sama dengan Prompt 92 (terikat ke path).

- `GET api/cctv/playback/{path}/list?date=yyyy-MM-dd&t=` → rentang rekaman pada
  tanggal itu (waktu lokal pabrik, WIB): daftar `{ start, end }` yang sudah dipotong ke
  batas hari dan digabung kalau bersambung (selisih ≤ 2 detik).
- `GET api/cctv/playback/{path}/get?start=<ISO8601 dengan offset>&duration=<detik>&t=`
  → streaming dari MediaMTX. `duration` 1–600 detik (lebih dari itu → 400). Teruskan
  header Range kalau MediaMTX mendukung.
- `GET api/cctv/playback/{path}/download?start=&duration=&t=` → sama, dengan
  `format=mp4` (kalau didukung) dan `Content-Disposition: attachment` bernama
  `<namaKamera>_<yyyyMMdd_HHmmss>.mp4`.
- Validasi `path` seperti Prompt 92. Semua waktu dikirim ke MediaMTX sebagai RFC3339
  dengan offset `+07:00`.
- MediaMTX menjawab "tidak ada rekaman" → 404 dengan pesan "Tidak ada rekaman pada
  jam itu".

## 2. Client — `/cctv/playback`

Query opsional: `cameraId`, `at` (ISO8601) — dipakai tombol dari Live dan Prompt 94.

- Panel kiri (di HP: di atas): Area, Kamera, Tanggal, Jam mulai (dengan detik),
  tombol **Putar**. Teks "Rekaman paling lama: <tanggal>" diambil dari rentang
  terlama yang tersedia (bukan dihitung dari 30 hari).
- Pemutar: `<video>` dengan stempel "nama kamera · tanggal jam" yang ikut berjalan
  (jam mulai + `currentTime`).
- Rekaman diputar per potongan 10 menit: saat potongan habis, otomatis lanjut ke
  potongan berikutnya.
- Kontrol: **− 10 dtk**, **Jeda/Putar**, **+ 10 dtk**, Kecepatan 1× / 2× / 4×
  (`playbackRate`), **Unduh klip (MP4)** → dialog kecil pilih durasi 1 / 5 / 10 menit
  mulai dari posisi putar.
- Garis waktu 24 jam: biru = ada rekaman, abu = kosong, garis oranye = posisi putar.
  Klik di garis waktu → lompat ke jam itu (ketelitian menit). Klik di bagian kosong →
  pesan "Tidak ada rekaman pada jam itu".
- Token diperbarui tiap ganti potongan.

## 3. Verifikasi

1. Build sukses.
2. Putar rekaman 1 jam lalu → gambar muncul, stempel waktu benar (WIB).
3. Garis waktu hari ini: bagian setelah jam sekarang abu.
4. `duration=601` → 400. Jam tanpa rekaman → pesan, bukan error mentah.
5. Unduh klip 1 menit → file MP4 bisa dibuka di pemutar biasa (kalau `format=mp4`
   tidak didukung, catat format yang didapat di laporan).

## Yang TIDAK boleh dilakukan

- Jangan membaca file di `D:\rekaman` langsung dari API — selalu lewat server playback
  MediaMTX.
- Jangan mengizinkan unduhan lebih dari 10 menit per permintaan.
- Jangan membuat fitur hapus rekaman.

Isi bagian "Prompt 93" di laporan, lalu commit.

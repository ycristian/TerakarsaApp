# Prompt 92 — CCTV: Proxy Stream + Grid Live

Lanjutan Prompt 91. Mockup: `claude prompt/cctv/mockup/Main.dc.html`.

## 0. Inspeksi dulu

- Coba `http://<MtxHlsBaseUrl>/cam8_83/index.m3u8`: catat bentuk playlist (master →
  playlist stream → segmen), nama file segmen, dan apakah memakai LL-HLS (part).
- Cek cara Client memuat file JS pihak ketiga yang sudah ada (mis. html5-qrcode) —
  hls.js mengikuti pola yang sama (file lokal di `wwwroot`, bukan CDN).
- Cek cara API saat ini men-streaming file besar (unduh PDF/Excel) dan apakah ada
  middleware yang mem-buffer response.

## 1. Token stream (API)

- `CctvStreamTokenService`: token = `base64url(path|expUnix|userId)` + `.` +
  `base64url(HMACSHA256(secret, payload))`. Validasi: tanda tangan cocok, belum
  kedaluwarsa, path sama dengan path di URL.
- `StreamTokenSecret` kosong → API menolak start dengan pesan jelas di log, **kecuali**
  environment Development (pakai secret sementara acak per proses).
- `GET api/cctv/cameras/{id}/stream-token` (`[RequireModule("CCTV")]`) →
  `{ path, token, expiresAt }`. Kamera harus hidup (tidak soft delete).

## 2. Proxy HLS (API)

`GET api/cctv/hls/{path}/{**file}?t=<token>` — **tanpa** JWT (dipanggil `<video>` /
hls.js), wajib token valid untuk `{path}`.

- Teruskan ke `{MtxHlsBaseUrl}/{path}/{file}` berikut query string asli (selain `t`).
- `{path}` dan `{file}` divalidasi: hanya huruf, angka, `_`, `-`, `.`; tolak `..`,
  `/` ganda, dan skema URL. Tujuan proxy selalu base URL dari konfigurasi — tidak
  pernah dari input user.
- Streaming langsung (tanpa buffer ke memori), teruskan `Content-Type`,
  `Cache-Control`; batalkan request ke MediaMTX kalau klien putus.
- Jangan menulis ulang isi playlist; URI di dalamnya relatif, dan token ditambahkan
  oleh klien (lihat bagian 3).
- Rate limit longgar per IP (segmen diminta terus-menerus) — jangan pakai limiter
  login.
- CORS: ikuti kebijakan API yang ada supaya Client (`app.terakarsa.id`,
  `terakarsa.lan`, IP lokal) bisa memanggil.

## 3. Client — `/cctv` (Live)

- Tambah hls.js (file lokal). `wwwroot/js/cctvPlayer.js`:
  - `cctvPlayer.start(videoEl, url, token)` — hls.js dengan `xhrSetup` yang menambahkan
    `t=<token>` ke **setiap** request (playlist dan segmen); Safari/iOS tanpa MSE →
    pakai `video.src` langsung dengan `?t=` (catat di laporan kalau playlist bertingkat
    membuat ini gagal).
  - `cctvPlayer.stop(videoEl)`, `cctvPlayer.stopAll()`.
  - Putus/galat → coba ulang tiap 5 detik, maksimal 5 kali, lalu tampil "Tidak ada
    sinyal".
- Halaman sesuai mockup:
  - Baris chip area (dari data kamera, dengan jumlah) + "Semua".
  - Pilihan tampilan **4 × 3 (12)**, **3 × 3 (9)**, **2 × 2 (4)** — tersimpan di
    localStorage.
  - Grid kartu: video 16:9, lencana LIVE, path kecil di pojok, nama + area di bawah,
    tombol ikon ke Playback kamera itu (`/cctv/playback?cameraId=`).
  - Kamera `OFFLINE` tidak diminta stream-nya; langsung tampil "Tidak ada sinyal".
  - Paging "1 / 3" + teks "Menampilkan 1–12 dari 27 kamera".
  - Klik video → layar penuh (Fullscreen API) untuk kamera itu.
- Hemat beban (WAJIB): hanya kamera di halaman aktif yang diputar; `stopAll()` saat
  ganti halaman/area, saat keluar dari `/cctv` (`IAsyncDisposable`), dan saat tab
  browser disembunyikan (`visibilitychange`), lalu mulai lagi saat terlihat.
- Token diminta per kamera saat mulai, dan diperbarui sebelum kedaluwarsa (stream live
  berjalan lebih lama dari umur token).
- Video `muted`, `playsinline`, `autoplay`.

## 4. Tahap tambahan — WebRTC di LAN (kerjakan setelah HLS terbukti jalan)

Tujuan: jeda <1 detik saat dibuka di jaringan pabrik.

- Proxy sinyal WHEP: `POST api/cctv/whep/{path}?t=` → `{MtxWebRtcBaseUrl}/{path}/whep`
  (body SDP diteruskan, header `Location` jawaban ditulis ulang ke rute proxy), plus
  `PATCH`/`DELETE` untuk sesi. Media tetap mengalir langsung browser ↔ server lewat
  UDP, jadi hanya berhasil di LAN.
- Klien: coba WHEP dulu; kalau dalam 3 detik belum ada gambar → pindah ke HLS tanpa
  pesan error. Ingat hasilnya di sessionStorage supaya dari luar tidak mencoba WHEP
  di setiap kamera.
- **Kalau tahap ini tidak stabil atau memakan waktu, batalkan**: kembalikan ke HLS
  saja, hapus kode setengah jadi, dan catat alasannya di laporan.

## 5. Verifikasi

1. Build sukses.
2. Tanpa token / token path lain / token kedaluwarsa → 401/403.
3. `path` berisi `..` atau karakter lain → 400.
4. Live 12 kamera tampil; pindah halaman → request segmen kamera lama berhenti
   (cek tab Network).
5. Kalau bisa: uji lewat `https://app.terakarsa.id`. Kalau tidak bisa dari mesin ini,
   tulis di laporan sebagai langkah uji owner.

## Yang TIDAK boleh dilakukan

- Jangan mengembalikan alamat `192.168.8.233:88xx` ke klien di response mana pun.
- Jangan memuat hls.js dari CDN.
- Jangan memutar lebih dari 12 stream sekaligus.
- Jangan menyalakan audio.

Isi bagian "Prompt 92" di laporan, lalu commit.

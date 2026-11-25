# Module CCTV — Keputusan Desain (16 Nov 2026)

## Tujuan

Melihat CCTV pabrik dari dalam Terakarsa: live, putar ulang rekaman, dan langsung
melompat ke rekaman saat sebuah transaksi (scan) terjadi.

## Kondisi yang sudah ada (di luar repo)

- MediaMTX v1.21 di server `192.168.8.233` (`D:\mediamtx`, Task Scheduler) menarik sub
  stream 27 kamera EZVIZ, nama path `cam8_xx` (mis. `cam8_83`).
- Rekaman `D:\rekaman\<path>\`, segmen 10 menit fMP4, simpan 30 hari.
- Port MediaMTX: HLS `8888`, WebRTC `8889`, RTSP `8554`, API `9997`
  (`/v3/paths/list`), playback `9996` (`/list?path=`, `/get?path=&start=&duration=`).
- `cam8_85` (H8c) memakai H265 → tidak tampil di browser sampai diubah ke H.264.
- NVR Hikvision tetap jalan sebagai cadangan; tidak dipakai module ini.

## Keputusan owner

| Hal | Keputusan |
|---|---|
| Isi versi pertama | Grid live + master kamera, playback, playback dari transaksi. Peta pabrik **tidak** masuk. |
| Akses | Dari pabrik (LAN) **dan** dari luar (`app.terakarsa.id`). |
| Hak akses | Owner saja. Satu module `CCTV`; yang punya module melihat semua kamera. |
| Urutan kerja | Mockup dulu (sudah), lalu prompt. |

## Keputusan teknis (diambil Claude, belum dikoreksi owner)

1. **Semua video lewat API Terakarsa.** Browser tidak pernah menghubungi MediaMTX
   langsung. API menjadi perantara (proxy) ke `127.0.0.1` port MediaMTX dan mengecek
   hak akses. Alasannya: MediaMTX tidak punya login, dan halaman https tidak bisa
   memuat video http. Dengan cara ini akses dari luar otomatis ikut Cloudflare Tunnel
   `api.terakarsa.id` yang sudah ada — tidak perlu tunnel baru.
2. **Live memakai HLS** (jeda ±5–10 detik) sebagai jalur utama, di LAN maupun dari
   luar. WebRTC (jeda <1 detik) dicoba sebagai tahap tambahan khusus LAN di Prompt 92;
   kalau tidak stabil, ditinggalkan.
3. **Token stream.** `<video>` dan hls.js tidak bisa membawa JWT dengan nyaman, jadi
   API menerbitkan token pendek (HMAC, berlaku 10 menit, terikat ke satu path kamera)
   yang dikirim sebagai query `?t=`. Token hanya bisa diminta user yang punya module
   `CCTV`.
4. **Live dibagi per halaman, 12 kamera** (pilihan 4 / 9 / 12). Stream berhenti saat
   pindah halaman atau tab browser disembunyikan. Alasan: beban browser dan internet
   pabrik 80 Mbps.
5. **Kaitan kamera ke produksi** lewat tabel tautan: kamera ↔ resource (line/station)
   dan/atau kamera ↔ divisi. Saat mencari kamera untuk sebuah transaksi: cari dari
   resource dulu, kalau tidak ada baru dari divisi.
6. **Tombol "Lihat CCTV" pertama dipasang di Laporan Bundle → tab Riwayat** (timeline
   bundle). Dibuat sebagai komponen yang bisa dipasang di halaman lain nanti (absensi
   RFID, benang, TNI).
7. **Rekaman transaksi diputar dari 30 detik sebelum sampai 60 detik sesudah** waktu
   kejadian.
8. **Module `CCTV` tidak otomatis diberikan ke semua Admin.** Owner mencentang sendiri
   untuk akunnya di halaman kelola user.
9. **Kredensial kamera tidak disimpan di Terakarsa.** Tabel kamera hanya menyimpan
   nama, area, path MediaMTX, dan data inventaris (IP, serial, channel NVR).

## Di luar versi pertama

Peta pabrik (denah + titik kamera), pembatasan kamera per user/area, notifikasi
kamera offline, tombol CCTV di halaman selain Laporan Bundle.

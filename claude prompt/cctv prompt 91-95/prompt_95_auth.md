# Prompt 95 — CCTV: Basic Auth untuk API MediaMTX (port 9997)

## Latar belakang
Di dev (API TMOS jalan di PC developer, bukan di server 192.168.8.233), halaman
`/cctv/kamera` menampilkan "Server rekaman tidak terjangkau". Penyebabnya:
`GET http://192.168.8.233:9997/v3/paths/list` dijawab
`{"status":"error","error":"authentication error"}` karena action `api` MediaMTX
secara default hanya boleh dari 127.0.0.1/::1.

Di server, `mediamtx.yml` SUDAH ditambah user `tmos` (action `api`, pakai password)
secara manual. Tugas prompt ini hanya sisi TMOS: mengirim Basic Auth saat memanggil
API MediaMTX.

Production tidak terpengaruh (API TMOS satu mesin dengan MediaMTX → 127.0.0.1),
jadi user/password boleh kosong di sana.

## Lingkup perubahan

### 1. `TerakarsaApp.API/Services/CctvMediaMtxClient.cs`
- Tambah dua properti di `CctvOptions`: `MtxApiUser` dan `MtxApiPassword`
  (string, default kosong).
- Di `GetPathsAsync`:
  - Buat request dengan `HttpRequestMessage`.
  - Jika `MtxApiUser` terisi, tambahkan header
    `Authorization: Basic base64(user:password)` (UTF-8) PADA REQUEST ITU SAJA.
  - Jika `MtxApiUser` kosong, kirim tanpa header (perilaku lama).
  - JANGAN pasang di `HttpClient.DefaultRequestHeaders` — HttpClient yang sama
    dipakai untuk playback `/list` (port 9996) yang tidak butuh auth.
- Jika MediaMTX menjawab 401 / "authentication error", tulis log Warning yang jelas
  (mis. "MediaMTX API menolak autentikasi — cek Cctv:MtxApiUser/MtxApiPassword").
  Password TIDAK BOLEH ikut tertulis di log.
- Perilaku ke UI tetap sama: gagal → status "Server rekaman tidak terjangkau".

### 2. Config
- `appsettings.json`: tambah key kosong di section `Cctv`:
  `"MtxApiUser": ""`, `"MtxApiPassword": ""`.
- JANGAN menulis nilai user/password di `appsettings.Development.json` atau file
  lain yang masuk repo.
- Pastikan project API punya `UserSecretsId` (tambahkan jika belum ada), supaya
  developer bisa mengisi lewat:
  ```
  dotnet user-secrets set "Cctv:MtxApiUser" "tmos"
  dotnet user-secrets set "Cctv:MtxApiPassword" "<password>"
  ```
  Jangan jalankan perintah ini; cukup tulis di laporan sebagai langkah manual.

## Yang TIDAK boleh diubah
- Proxy HLS (8888), WebRTC (8889), dan playback (9996).
- Stored procedure dan tabel schema `cctv`.
- Jangan simpan user/password kamera (RTSP) di DB atau kode.
- Password MediaMTX tidak boleh dikirim ke browser / client Blazor, tidak boleh
  masuk DTO, response API, atau log.
- Jangan ubah `mediamtx.yml` (di luar repo, sudah dikerjakan manual).
- Tidak ada perubahan SQL di prompt ini.

## Cara uji
1. Tanpa user-secrets → `/cctv/kamera` di dev tetap "Server rekaman tidak
   terjangkau" dan log berisi Warning autentikasi (tanpa password).
2. Setelah user-secrets diisi dan API di-restart → kolom Status menampilkan
   Online/Offline, tombol "Ambil kamera baru dari server" berfungsi.
3. Live view dan Playback tetap jalan seperti sebelumnya.
4. `dotnet build` tanpa error/warning baru.

## Urutan deploy
1. Server: `mediamtx.yml` dengan user `tmos` + restart MediaMTX (sudah, manual).
2. Deploy API TMOS. Production: `MtxApiUser`/`MtxApiPassword` dibiarkan kosong.

## Laporan
Tulis laporan ke `claude prompt/report/95-cctv-mtx-api-auth-report.md`, berisi:
- File yang diubah + ringkasan perubahan per file.
- Apakah `UserSecretsId` sudah ada atau baru ditambahkan.
- Hasil build dan hasil uji yang bisa dijalankan.
- Langkah manual yang masih harus dilakukan developer (perintah user-secrets).
- Hal yang menyimpang dari prompt ini atau temuan lain, jika ada.
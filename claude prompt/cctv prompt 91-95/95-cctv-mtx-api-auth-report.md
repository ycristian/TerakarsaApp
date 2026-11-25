# Laporan Prompt 95 — CCTV: Basic Auth untuk API MediaMTX (port 9997)

## File yang diubah

| File | Perubahan |
|---|---|
| `TerakarsaApp.API/Services/CctvMediaMtxClient.cs` | `CctvOptions` + `MtxApiUser`, `MtxApiPassword` (default kosong). `GetPathsAsync` sekarang memakai `HttpRequestMessage` + `SendAsync`; header `Authorization: Basic base64(user:password)` (UTF-8) dipasang **per request** hanya jika `MtxApiUser` terisi. Respons 401 → log Warning "MediaMTX API menolak autentikasi ({Url}) — cek Cctv:MtxApiUser/MtxApiPassword (user terisi: true/false)" lalu `Reachable = false` (UI tetap "Server rekaman tidak terjangkau"). Password tidak ditulis ke log. |
| `TerakarsaApp.API/appsettings.json` | Section `Cctv` + `"MtxApiUser": ""`, `"MtxApiPassword": ""`. |
| `TerakarsaApp.API/TerakarsaApp.API.csproj` | Tambah `<UserSecretsId>af10ff51-09f8-4e2a-b372-1c8a209ee2f9</UserSecretsId>`. |

Tidak diubah: `HttpClient.DefaultRequestHeaders`, `ListRecordingsAsync` (playback 9996), proxy HLS/WebRTC, SP/tabel schema `cctv`, `appsettings.Development.json`, `mediamtx.yml`. Tidak ada SQL.

## UserSecretsId
Belum ada sebelumnya → **baru ditambahkan**. `WebApplication.CreateBuilder` otomatis memuat user-secrets saat environment Development, jadi tidak perlu perubahan di `Program.cs`.

## Hasil build & uji
- `dotnet build TerakarsaApp.slnx` gagal **hanya** karena `TerakarsaApp.API.exe` sedang dikunci proses API yang berjalan (MSB3027, bukan error kompilasi).
- Build project API ke folder output terpisah: **0 error, 10 warning** — sama dengan baseline sebelum perubahan (10 warning), tidak ada warning baru.
- Uji 1 (sebagian): `GET http://192.168.8.233:9997/v3/paths/list` tanpa auth dari PC dev → **HTTP 401**, jadi cabang log Warning autentikasi akan terpicu.
- Uji 2–3 (Online/Offline, sync, Live, Playback) belum bisa dijalankan dari sini: butuh password `tmos` dan restart API oleh developer.

## Langkah manual developer
1. Hentikan API yang sedang jalan, lalu build ulang.
2. Isi user-secrets (dari folder `TerakarsaApp.API`):
   ```
   dotnet user-secrets set "Cctv:MtxApiUser" "tmos"
   dotnet user-secrets set "Cctv:MtxApiPassword" "<password>"
   ```
3. Jalankan API → buka `/cctv/kamera`: Status harus Online/Offline, tombol "Ambil kamera baru dari server" berfungsi. Cek Live & Playback tetap jalan.
4. Production: `MtxApiUser`/`MtxApiPassword` dibiarkan kosong.

## Perbaikan tambahan (di luar prompt, ditemukan saat uji Live)
Live view macet "Menyambung ulang…": MediaMTX versi server menjawab request HLS pertama
(`index.m3u8`) dengan `302 Location: /<path>/index.m3u8?cookieCheck=1` + Set-Cookie.
Proxy memakai `AllowAutoRedirect = false` dan tidak meneruskan `Location`, jadi browser
menerima 302 kosong.

- `TerakarsaApp.API/Services/CctvProxyService.cs`: `ForwardGetAsync` mengikuti redirect
  maks. 2 kali, **hanya** ke scheme+host+port yang sama dengan tujuan awal (host lain → tidak
  diikuti). Cookie tetap tidak dikirim → MediaMTX memakai mode tanpa cookie
  (`?session=...` di URI playlist), yang sudah diteruskan apa adanya oleh `cctvPlayer.js`.
- `TerakarsaApp.API/Program.cs`: komentar registrasi HttpClient `cctv-proxy` disesuaikan.
- Uji curl tanpa cookie: `index.m3u8?cookieCheck=1` → 200 berisi
  `video1_stream.m3u8?session=…`; `video1_stream.m3u8?session=…` → 200 tanpa redirect lagi.
- Build API: 0 error, 10 warning (sama dengan baseline).

## Temuan lain
- Saat 401, request langsung dihentikan dan `Reachable = false` dikembalikan tanpa melempar exception (sebelumnya lewat `EnsureSuccessStatusCode` → catch → log generik "tidak terjangkau"). Perilaku ke UI sama.
- cam8_85 (D12) sub stream H.265 → tidak bisa diputar di browser; ubah ke H.264 di setelan kamera/NVR (di luar prompt ini).

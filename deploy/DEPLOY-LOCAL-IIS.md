# Deploy ke IIS (server lokal AGS / 192.168.8.233) — testing sebelum Azure

Target: 3 aplikasi di server **AGS (192.168.8.233)**, SQL Server di mesin yang sama.

| Aplikasi | Cara hosting | Port |
|---|---|---|
| TerakarsaApp.API | IIS site | 5281 (HTTP) |
| TerakarsaApp.Client | IIS site (static, Blazor WASM) | 80 (HTTP) |
| TerakarsaApp.PrintService | **Windows Service** (bukan IIS — ini Worker Service) | - |

Port API 5281 dipilih supaya cocok dengan logic hardcode di
[Program.cs](../TerakarsaApp.Client/Program.cs) (`http` → port 5281, `https` → 7130) —
jadi Client otomatis manggil API yang benar tanpa ubah kode.

## 0. Prasyarat di server AGS (sekali saja, sebelum apa pun)

1. Install **.NET 10.0 Hosting Bundle (Windows)** — https://dotnet.microsoft.com/download/dotnet/10.0
2. Install **URL Rewrite Module 2.1** untuk IIS — https://www.iis.net/downloads/microsoft/url-rewrite
3. Pastikan SQL Server sudah terpasang & instance-nya diketahui namanya (cek `services.msc` →
   "SQL Server (NAMA_INSTANCE)"), dan database `TerakarsaDb` sudah dibuat lewat
   `sql/create_tables_tmos_final.sql` + SP terkait (dijalankan manual seperti biasa).
4. Restart server (atau `iisreset`) setelah install hosting bundle.

## 1. Setup IIS (di server AGS, PowerShell as Administrator)

Copy folder `deploy/` ini ke server, lalu jalankan:

```powershell
.\iis-setup.ps1
```

Ini bikin: App Pool + Site `TerakarsaAPI` (192.168.8.233:5281) dan `TerakarsaClient`
(192.168.8.233:80), folder `D:\TerakarsaFiles`, firewall rule. Cek dulu isi script kalau drive
`D:` tidak ada di server ini — ganti parameter `-FileStorageBasePath` ke drive yang ada.

## 2. Publish 3 aplikasi (di PC dev ini)

```powershell
dotnet publish TerakarsaApp.API\TerakarsaApp.API.csproj -c Release -o publish\api
dotnet publish TerakarsaApp.Client\TerakarsaApp.Client.csproj -c Release -o publish\client
dotnet publish TerakarsaApp.PrintService\TerakarsaApp.PrintService.csproj -c Release -o publish\printservice
```

Copy isi `publish\api` → `C:\inetpub\TerakarsaApp.API` di server.
Copy isi `publish\client\wwwroot` → `C:\inetpub\wwwroot\TerakarsaApp.Client` di server
(yang di-serve IIS adalah isi `wwwroot`-nya, bukan folder publish itu sendiri).
Copy `publish\printservice` → misal `C:\Services\TerakarsaApp.PrintService` di server.

## 3. Sesuaikan config di server (edit file yang sudah di-copy, JANGAN di repo dev)

`C:\inetpub\TerakarsaApp.API\appsettings.json`:
- `ConnectionStrings:DefaultConnection` → ganti `IVANDERPC\SQLEXPRESS` sesuai instance SQL
  Server yang sebenarnya di AGS (mis. `Server=AGS\SQLEXPRESS;...` atau `Server=localhost;...`).
- `App:PublicBaseUrl` → `http://192.168.8.233` (ini dipakai untuk link QR label bundle, harus
  sama dengan URL Client).
- `JwtSettings:Key` → ganti ke key produksi baru (jangan pakai key dev), minimal 32 karakter.
- `FileStorage:BasePath` → samakan dengan `-FileStorageBasePath` yang dipakai di `iis-setup.ps1`.

`C:\Services\TerakarsaApp.PrintService\appsettings.json` — sudah default `ApiBaseUrl:
http://localhost:5281`, cocok karena PrintService jalan di mesin yang sama dengan API. Tidak
perlu diubah kecuali nama printer beda dari `TSC TTP-244 Pro`.

## 4. Install PrintService sebagai Windows Service (di server, PowerShell as Administrator)

```powershell
sc.exe create TmosPrintService binPath= "C:\Services\TerakarsaApp.PrintService\TerakarsaApp.PrintService.exe" start= auto
sc.exe description TmosPrintService "TMOS Print Service - TSC TTP-244 Pro worker"
sc.exe start TmosPrintService
```

(Perhatikan spasi setelah `binPath=` dan `start=` — wajib ada, `sc.exe` sensitif ke ini.)

## 5. Test

- Buka `http://192.168.8.233/` dari PC lain di LAN → halaman login TMOS harus muncul.
- Login, cek satu halaman yang manggil API (mis. daftar project) → kalau CORS/koneksi
  gagal, cek IIS log API di `C:\inetpub\TerakarsaApp.API\logs` (kalau `stdoutLogEnabled`
  di web.config API di-set true) atau Event Viewer.
- Cetak label bundle dari station kiosk → cek service `TmosPrintService` jalan (`Get-Service
  TmosPrintService`) dan cek log file worker (lihat `DailyFileLogger` output folder-nya).

## Catatan untuk nanti pindah ke Azure

- `ConnectionStrings`, `JwtSettings:Key`, `App:PublicBaseUrl`, `PrintService:ApiKey` sebaiknya
  di-override lewat App Settings Azure (env var dengan format `Section__Key`), bukan disimpan
  di `appsettings.json` — appsettings.json sudah punya komentar soal ini untuk `JwtSettings:Key`.
- Logic hardcode port 5281/7130 di [Program.cs Client](../TerakarsaApp.Client/Program.cs) perlu
  diganti (mis. baca dari `wwwroot/appsettings.json`) karena Azure App Service tidak selalu
  kasih kontrol port publik seperti ini.

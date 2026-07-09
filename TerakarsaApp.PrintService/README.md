# TerakarsaApp.PrintService

Windows Worker Service yang berjalan di PC printer: polling `api/print/claim` di TerakarsaApp.API,
merakit TSPL dari payload job, dan mengirim ke printer TSC TTP-244 Pro lewat USB (raw printing
via winspool, tanpa driver/SDK khusus TSC). Hasilnya dilaporkan balik lewat `api/print/report`.

Saat ini hanya menangani `job_type = BUNDLE_LABEL`. Job type lain akan langsung dilaporkan gagal
dengan pesan "Job type belum didukung." (menyusul di fase berikutnya, mis. `MATERIAL_LABEL`).

## Konfigurasi (`appsettings.json`)

```json
{
  "PrintService": {
    "ApiBaseUrl": "http://localhost:5281",
    "ApiKey": "harus-sama-persis-dengan-PrintService:ApiKey-di-TerakarsaApp.API",
    "PrinterName": "TSC TTP-244 Pro",
    "PollSeconds": 5,
    "BatchSize": 5,
    "DryRun": true
  }
}
```

- `ApiBaseUrl` — alamat TerakarsaApp.API yang bisa dijangkau dari PC printer.
- `ApiKey` — **harus sama persis** dengan nilai `PrintService:ApiKey` di `appsettings.json`
  milik TerakarsaApp.API (dicocokkan lewat header `X-Print-Api-Key`). Beda satu karakter saja
  akan membuat semua request ditolak 401.
- `PrinterName` — nama printer persis seperti yang muncul di "Devices and Printers" Windows
  (Windows > Settings > Bluetooth & devices > Printers & scanners). Printer TSC harus sudah
  terpasang sebagai printer Windows biasa (driver apa saja, port USB) sebelum service dijalankan.
- `PollSeconds` — jeda antar siklus polling (detik).
- `BatchSize` — jumlah job maksimum yang diklaim per siklus.
- `DryRun` — jika `true`, TSPL tidak dikirim ke printer; ditulis ke file
  `./dryrun/{print_job_id}.tspl` (relatif terhadap folder exe) dan job langsung dilaporkan sukses.
  Berguna untuk mengembangkan/menguji tanpa printer fisik.

## Menjalankan sebagai console (development / DryRun)

```
cd TerakarsaApp.PrintService
dotnet run
```

Log tampil di console dan juga ditulis ke `./logs/print-{yyyyMMdd}.log` (relatif terhadap
folder exe, dibuat otomatis).

## Install sebagai Windows Service (produksi)

1. Publish dulu (self-contained atau framework-dependent, sesuaikan kebutuhan):
   ```
   dotnet publish -c Release -o C:\TerakarsaApp\PrintService
   ```
2. Pastikan `appsettings.json` di folder publish sudah diisi dengan `ApiBaseUrl`, `ApiKey`
   (harus cocok dengan API), `PrinterName` yang benar, dan `DryRun: false`.
3. Buat service-nya (jalankan Command Prompt sebagai Administrator):
   ```
   sc create TmosPrintService binPath= "C:\TerakarsaApp\PrintService\TerakarsaApp.PrintService.exe"
   sc start TmosPrintService
   ```
   Catatan: spasi setelah `binPath=` wajib ada (syntax `sc.exe`).
4. Untuk berhenti/hapus:
   ```
   sc stop TmosPrintService
   sc delete TmosPrintService
   ```
5. Ganti nama printer: edit `PrinterName` di `appsettings.json` lalu `sc stop` + `sc start`
   ulang (service membaca konfigurasi saat start).

## Verifikasi cepat (DryRun)

1. Set `DryRun: true` di `appsettings.json`, pastikan `ApiBaseUrl`/`ApiKey` mengarah ke API lokal
   yang sedang jalan.
2. `dotnet run` di folder ini (mode console).
3. Buat 1 bundle baru dari halaman "Kelola Bundle" di aplikasi utama (atau lewat `POST api/bundles`).
4. Dalam beberapa detik (sesuai `PollSeconds`), file `.tspl` akan muncul di `./dryrun/`, dan
   status label bundle tersebut di halaman "Kelola Bundle" berubah dari "Menunggu Cetak" menjadi
   "Dicetak" (job di `print_jobs` menjadi `DONE`).

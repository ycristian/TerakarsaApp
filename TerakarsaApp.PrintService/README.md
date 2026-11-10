# TerakarsaApp.PrintService

Windows Worker Service yang berjalan di PC printer: polling `api/print/claim` di TerakarsaApp.API,
merakit TSPL dari payload job, dan mengirim ke printer TSC TTP-244 Pro lewat USB (raw printing
via winspool, tanpa driver/SDK khusus TSC). Hasilnya dilaporkan balik lewat `api/print/report`.

Job type yang ditangani dikelompokkan jadi tiga jalur:

| Jalur | Dirakit oleh | job_type |
|---|---|---|
| `RAW_TSPL` | `TsplBuilder.cs` (C#) | `BUNDLE_LABEL`, `PACK_LABEL`, `REJECT_NOTE` |
| `TOKEN` | SP `SIS_Print_Dispatch` + `EscPosRenderer.cs` | job_type kupon/struk, didaftarkan di tabel `print_kupon_job_types` |
| ESC/POS di C# | `TniKartuEscPosBuilder.cs` | `TNI_KARTU` (Prompt 65) |

Job type di luar ketiganya dilaporkan gagal dengan pesan "Job type belum didukung."

**`TNI_KARTU` (kartu personel PDH TNI AD, Prompt 65)** — thermal 80mm, Font A 48 kolom.
Dirakit di C# dari payload (`TniKartuPayload`), BUKAN lewat token SP, jadi:

- ditangkap berdasarkan **job_type** di `ProcessJobAsync` SEBELUM switch `RenderMode`
  (lihat array `EscPosJobTypes` di `Worker.cs`);
- **tidak** didaftarkan di `print_kupon_job_types`;
- diklaim hanya saat `PrinterThermalOn: true` (printer fisiknya sama dengan struk);
- routing-nya tetap lewat `print_job_routes` (`job_type = 'TNI_KARTU'`), jadi bisa dipindah
  ke printer 80mm lain lewat SQL tanpa restart — lihat `sql/tni/seed_65_print_route_tni_kartu.sql`.
- **Struk REKAP SIZE** (2026-11-09): kalau satu kali cetak berisi > 1 kartu,
  `tni.SIS_Personel_Cetak` menambah satu job `TNI_KARTU` lagi (ref_id 0, payload
  `jenis = "REKAP"`, `TniKartuRekapPayload`) yang di-insert lebih dulu, jadi tercetak
  paling awal: total kartu + jumlah per size celana & kemeja. Worker membedakannya lewat
  `TniKartuEscPosBuilder.IsRekap`. PrintService versi lama akan mencetaknya sebagai kartu
  kosong — deploy PrintService SEBELUM menjalankan SP baru.

QR di kartu digenerate sendiri lewat **QRCoder** lalu dicetak sebagai **raster bit image**
(`GS v 0`), sama dengan `EscPosRenderer.EmitQr` — **bukan** command QR native (`GS ( k`),
karena printer thermal di sini salah merender QR native.

**Percepatan batch (Prompt 65)**: kalau satu klaim mengembalikan job sebanyak `BatchSize`,
worker langsung klaim lagi tanpa menunggu `PollSeconds` (maks 50 batch per siklus) — supaya
cetak ratusan kartu satuan tidak tertahan jeda polling. Perilaku saat antrian kosong atau
batch belum penuh tidak berubah.

## Konfigurasi (`appsettings.json`)

```json
{
  "PrintService": {
    "ApiBaseUrl": "http://localhost:5281",
    "ApiKey": "harus-sama-persis-dengan-PrintService:ApiKey-di-TerakarsaApp.API",
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
- `PollSeconds` — jeda antar siklus polling (detik).
- `BatchSize` — jumlah job maksimum yang diklaim per siklus. Kalau satu klaim penuh
  sebanyak nilai ini, worker langsung klaim lagi tanpa menunggu `PollSeconds`.
- `DryRun` — jika `true`, tidak ada yang dikirim ke printer fisik; untuk job TSPL ditulis ke
  `./dryrun/{print_job_id}.tspl`, untuk job TOKEN ditulis ke `./dryrun/{print_job_id}.escpos`
  (byte mentah) DAN `./dryrun/{print_job_id}.txt` (pratinjau teks polos, dipakai untuk
  memeriksa layout tanpa printer fisik), untuk `TNI_KARTU` ditulis ke
  `./dryrun/{print_job_id}.escpos.bin` DAN `./dryrun/{print_job_id}.txt` -- semua relatif
  terhadap folder exe, job langsung dilaporkan sukses. Berguna untuk mengembangkan/menguji
  tanpa printer fisik.

## Nama printer & routing (tabel `print_devices` / `print_job_routes`, Prompt 48)

Nama printer Windows dan lebar kertas **tidak lagi ada di `appsettings.json`** -- pindah ke
tabel `print_devices` (satu baris per printer fisik) dan `print_job_routes` (pemetaan
`job_type` -> printer). Service ini bisa jalan di satu PC yang terhubung ke SEMUA printer
sekaligus; worker mengambil `printer_name`/`chars_per_line`/`render_mode` dari hasil klaim job
(`SIS_PrintJob_Claim`), bukan dari config lokal.

- **Ganti nama printer** (mis. nama printer di Windows berubah): `UPDATE print_devices SET
  printer_name = '...' WHERE device_code = 'LABEL'` (atau `'THERMAL'`). Berlaku langsung untuk
  job berikutnya, tanpa restart service.
- **Pindah/ganti routing job_type** (mis. arahkan `KUPON_BORONGAN` ke printer lain): update
  `print_job_routes.print_device_id` untuk baris `job_type` terkait. Berlaku langsung untuk job
  yang masih PENDING (routing diresolusi saat job diklaim, bukan saat dibuat).
- **Matikan sementara satu jenis printer**: `UPDATE print_devices SET is_active = 0 WHERE
  device_code = '...'` -- job untuk `job_type` yang terhubung ke device itu tetap PENDING
  (tidak error) sampai device diaktifkan lagi.
- `render_mode` tiap device menentukan jalur worker: `RAW_TSPL` (label TSC, `TsplBuilder.cs`,
  tidak berubah) atau `TOKEN` (struk thermal, isi dirakit stored procedure lalu diterjemahkan
  `EscPosRenderer.cs` -- ubah layout struk cukup `CREATE OR ALTER PROCEDURE` di SQL, tanpa
  build/publish ulang service ini).

## Printer jaringan (TCP) & pilih printer saat cetak (Prompt 88)

Selain printer Windows (USB, nama printer di Windows), service ini bisa mengirim langsung ke
**printer jaringan** lewat socket TCP `host:port` (port RAW umumnya `9100`) -- printernya
**tidak perlu didaftarkan di Windows**. Satu worker di satu PC menangani semua printer PC
(USB Windows maupun TCP); jangan pasang service kedua.

- Jenis device = kolom `print_devices.transport`: `WINDOWS` (winspool, `printer_name`), `TCP`
  (`host` + `port`, dikirim `TcpRawPrinter.cs`), `ANDROID_BT` (HP, bukan urusan service ini).
  Service ini hanya mengklaim job yang device finalnya `WINDOWS`/`TCP`.
- Isi label/struk sama persis untuk kedua jalur (`TsplBuilder`/`EscPosRenderer` tidak tahu
  printernya lewat apa) -- `RAW_TSPL` maupun `TOKEN` bisa lewat TCP.
- Printer mati / IP salah -> job gagal dengan pesan jelas, mis.
  `TCP 192.168.8.51:9100: connection timeout (5 detik) -- printer mati atau IP salah.` atau
  `... connection refused ...`, lalu ikut retry 3x yang sudah ada sebelum jadi `ERROR`. Job
  ke printer lain tetap jalan.
- DryRun: job ke device TCP ditulis ke `./dryrun/{print_job_id}_{device_code}.tspl` (suffix
  kode device), device Windows tetap `./dryrun/{print_job_id}.tspl`.
- Saklar `PrinterLabelOn` berlaku untuk SEMUA printer label PC (TSC USB maupun printer
  jaringan) -- device mana yang dipakai ditentukan SP klaim, bukan config ini.
- `DeviceCodes` (appsettings, mis. `["LABEL_ATAS"]`): batasi worker ini hanya mengerjakan
  printer dengan kode tersebut (kode = kolom kode di `/admin/printer`). Kosong `[]` = semua
  printer PC. Job printer lain tidak disentuh -- tetap PENDING untuk worker lain. Berguna
  untuk testing dari PC developer tanpa berebut job dengan PrintService di NUC.

**Menambah printer jaringan baru** (tanpa deploy / restart service):

1. Pasang printer di jaringan dengan IP tetap (reservasi DHCP atau IP statis).
2. Buka `/admin/printer` -> **+ Tambah printer PC** -> tipe **PC Jaringan (TCP)**, isi nama
   (lokasi, mis. "Label Lantai Atas"), kode, host/IP, port 9100, render mode `RAW_TSPL`, grup
   `LABEL_BUNDLE`.
3. Klik **Test print** pada device itu -> harus keluar label kecil "TEST PRINT".
4. Di **Routing job cetak**, centang device itu pada job type yang diinginkan (mis.
   `BUNDLE_LABEL`, `CUTTING_BUNDLE_LABEL`).

**Satu job type, banyak printer**: kalau job type punya lebih dari satu device tujuan aktif,
user **wajib memilih printer saat mencetak** (dropdown + tombol "Jadikan default", disimpan per
perangkat di browser). Pilihan itu langsung ditulis ke `print_jobs.print_device_id` saat job
dibuat (`SIS_PrintJob_ResolveDevice`); tanpa pilihan, server menolak `Pilih printer tujuan.`
dan tidak ada job dibuat. Job type dengan satu device tetap otomatis seperti sebelumnya.
Job yang printernya dinonaktifkan tetap PENDING (tampil "tertahan" di halaman admin) dan
tercetak sendiri begitu device diaktifkan lagi.

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
   (harus cocok dengan API), dan `DryRun: false`. Nama printer diisi lewat SQL (`print_devices`,
   lihat bagian di atas), bukan di sini.
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
5. Ganti nama printer: `UPDATE print_devices SET printer_name = '...' WHERE device_code = '...'`
   lewat SQL -- berlaku langsung untuk job berikutnya, TIDAK perlu `sc stop`/`sc start`.

## Verifikasi cepat (DryRun)

1. Set `DryRun: true` di `appsettings.json`, pastikan `ApiBaseUrl`/`ApiKey` mengarah ke API lokal
   yang sedang jalan.
2. `dotnet run` di folder ini (mode console).
3. Buat 1 bundle baru dari halaman "Kelola Bundle" di aplikasi utama (atau lewat `POST api/bundles`).
4. Dalam beberapa detik (sesuai `PollSeconds`), file `.tspl` akan muncul di `./dryrun/`, dan
   status label bundle tersebut di halaman "Kelola Bundle" berubah dari "Menunggu Cetak" menjadi
   "Dicetak" (job di `print_jobs` menjadi `DONE`).

# Prompt 11 — Print Service: Cetak Label Bundle (TSC TTP-244 Pro)

## Konteks

`print_jobs` sudah terisi dari pembuatan bundle (Prompt 10). Prompt ini membuat: (a) endpoint API untuk klaim & lapor job, (b) project baru **Windows Worker Service** yang berjalan di PC printer — polling API via HTTPS, merakit TSPL, mengirim ke printer TSC TTP-244 Pro lewat USB (terpasang sebagai printer Windows), lapor status balik.

## 0. Patch kecil (SQL saja)

Di `sp_Bundle_Manage` action UPDATE dan DELETE: ubah syarat penolakan dari "bundle punya log hidup apa pun" menjadi "bundle punya log hidup ber-status **COMPLETED**" — supaya supervisor masih bisa ganti line/qty atau hapus bundle yang belum mulai dikerjakan. Sesuaikan pesan errornya.

## 1. Stored Procedures

- `sp_PrintJob_Claim` (@BatchSize int): dalam satu statement atomik (UPDATE TOP(@BatchSize) ... WITH (UPDLOCK, READPAST) ... OUTPUT), ambil job hidup status PENDING terlama, set status = PRINTING + updated_at. Kembalikan print_job_id, job_type, payload. Aman dipanggil bersamaan (tidak ada job terklaim ganda).
- `sp_PrintJob_Report` (@PrintJobId, @Success bit, @ErrorMessage): sukses → status DONE + printed_at. Gagal → retry_count + 1; jika retry_count < 3 → kembali PENDING (akan diklaim ulang), jika sudah 3 → status ERROR + error_message.
- `sp_PrintJob_RequeueStale`: job status PRINTING yang updated_at > 10 menit lalu (service mati di tengah jalan) → kembalikan ke PENDING. Dipanggil di awal sp_PrintJob_Claim.

## 2. API

Autentikasi khusus service: header `X-Print-Api-Key`, dicocokkan dengan `PrintService:ApiKey` di appsettings API (string acak panjang). Filter `[RequirePrintApiKey]`, terpisah dari JWT dan station token.

- POST `api/print/claim` — body: batchSize (default 5) → daftar job.
- POST `api/print/report` — body: printJobId, success, errorMessage.

## 3. Project baru: TerakarsaApp.PrintService

.NET Worker Service (template worker), ditambahkan ke solution, package `Microsoft.Extensions.Hosting.WindowsServices` (`UseWindowsService()` agar bisa jalan sebagai Windows Service maupun console biasa).

### Konfigurasi (appsettings.json service)
`ApiBaseUrl`, `ApiKey`, `PrinterName` (nama printer Windows, mis. "TSC TTP-244 Pro"), `PollSeconds` (default 5), `BatchSize` (default 5), `DryRun` (bool).

### Loop utama
Tiap PollSeconds: panggil claim → untuk tiap job: parse payload JSON → rakit TSPL → kirim ke printer → report per job (sukses/gagal, error message jelas: printer offline, payload rusak, dsb). Kegagalan satu job tidak menghentikan job lain maupun loop. API tidak terjangkau → log warning, coba lagi siklus berikutnya (jangan crash).

### TSPL label bundle (10 × 5 cm)
- `SIZE 100 mm, 50 mm`, `GAP 3 mm, 0`, `DIRECTION 1`, `CLS`.
- Kiri: QRCODE dari field `qr_content` payload (level koreksi M, ukuran cell secukupnya agar QR ± 35–40 mm).
- Kanan (TEXT, font terbesar yang muat): baris 1 `serial` (paling menonjol), baris 2 `article_name`, baris 3 `style` + `color`, baris 4 `size_name` + `qty` pcs, baris 5 `project_name` (kecil).
- `PRINT 1,1`.
- Kirim sebagai raw bytes ke printer Windows via winspool (P/Invoke RawPrinterHelper — pola standar OpenPrinter/StartDocPrinter/WritePrinter).

### DryRun
Jika `DryRun = true`: jangan kirim ke printer; tulis TSPL ke file `./dryrun/{print_job_id}.tspl` dan report sukses. Untuk pengembangan tanpa printer.

### Logging
ILogger ke console + file teks harian sederhana (`./logs/print-{yyyyMMdd}.log`): job diklaim, sukses, gagal + alasan.

## 4. Verifikasi

- `dotnet build` seluruh solution sukses (project baru ikut).
- Jalankan service mode console dengan DryRun = true terhadap API lokal: buat 1 bundle → file .tspl muncul → status job jadi DONE.
- Sertakan di README service: cara install sebagai Windows Service (`sc create TmosPrintService binPath= "...exe"`), cara ganti printer name, dan catatan bahwa ApiKey harus sama dengan di API.

## Yang TIDAK boleh dilakukan

- Jangan buat UI apa pun — service headless.
- Jangan tangani job_type selain BUNDLE_LABEL (MATERIAL_LABEL menyusul di Phase F; job_type lain → report error "job type belum didukung").
- Jangan ubah alur stasiun atau halaman client selain patch di poin 0.
- Jangan pakai driver/SDK khusus TSC — cukup raw printing winspool.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

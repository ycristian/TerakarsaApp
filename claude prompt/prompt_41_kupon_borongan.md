# Prompt 41 — Kupon Borongan & Rekap Penjahit (Printer Struk)

## Konteks

Dua fitur cetak struk thermal (printer struk biasa 58 mm, ESC/POS — BUKAN printer label TSC) untuk perlindungan penggajian borongan dan kontrol pembagian hanca:

1. **Kupon per bundle** — otomatis tercetak saat qty pekerjaan penjahit **dikonfirmasi diterima** step berikutnya (`received_at` terisi, termasuk via auto-receive Prompt 34). Kupon diserahkan ke penjahit sebagai bukti fisik; dicocokkan manual dengan Report Produksi saat gajian mingguan.
2. **Rekap Penjahit harian** — tombol di halaman station (hanya di station, tidak ada di admin): pilih penjahit → modal pilih tanggal (default hari ini) → tampil & cetak struk ringkasan per status (WIP / Dicek / Beres). Dipakai divisi Bundling untuk (a) menjawab penjahit yang tanya "sudah dapat berapa", (b) melihat WIP yang menyendat sebelum memberi hanca baru.

Semantik tanggal: **Beres** = qty yang `received_at`-nya jatuh pada tanggal terpilih; **WIP** dan **Dicek** = kondisi *saat ini* (status, bukan kejadian harian) — di layar dan struk diberi label jelas ("Beres tgl X" vs "WIP saat ini").

Prinsip: **database tetap acuan bayar** — kupon/rekap hanya alat cross-check. Tidak ada fitur scan-klaim (QR tetap dicetak di kupon untuk kemungkinan fitur itu nanti).

Mengikuti pola Prompt 34: flag + mekanisme dibangun di sini, aktivasi via seed/UI terpisah. Flag `print_kupon` bisa dipasang di step mana pun lewat setting workflow (nanti bisa QC, DTF, dll.), **tapi v1 hanya valid untuk step bertipe bundle** — step non-bundle ditolak (log-nya bukan per bundle, format kupon tidak berlaku). Dukungan step non-bundle = scope masa depan.

## 1. Skema SQL

Buat `sql/prompt_41_kupon_borongan.sql` (idempotent):

- Tambah kolom `print_kupon bit not null default 0` di `workflow_template_steps` dan `article_workflows`.
- Update juga definisi tabel di `sql/create_tables_tmos_final.sql`.

Buat `sql/seed_41_kupon_sew_qc.sql` (opsional, dijalankan manual saat siap aktivasi):
- Set `print_kupon = 1` pada baris hidup `workflow_template_steps` dan `article_workflows` yang `step_name` cocok Sew+QC via case-insensitive LIKE (pola sama seperti `seed_34_auto_receive_buang_benang.sql`, tanpa hardcode ID).

## 2. Stored Procedures

### a. SIS_WorkflowLog_Manage — sisipan di jalur RECEIVE

Saat `received_at` terisi (aksi RECEIVE manual **maupun** jalur auto-receive dari Prompt 34), dalam transaksi yang sama: jika **step asal** baris log (article_workflows pembuat baris) punya `print_kupon = 1` → INSERT `print_jobs`:

- `job_type = 'KUPON_BORONGAN'`, `ref_id` = workflow_log_id baris tersebut.
- `payload` JSON: `workflow_log_id`, `serial`, `letter_code` + `bundle_no`, `project_name`, `article_name`, `style`, `color`, `size_name`, `qty_ok`, `qty_reject_print`, `qty_reject_fabric`, `qty_reject_sewing`, `qty_reject_rework`, `qty_lost`, `tailor_name`, `step_name`, `received_at`.
- `tailor_name` prioritas Prompt 32: EmployeeName bundle → ResourcePersonName → nama resource baris log → `-`.
- QR dirakit worker dari `workflow_log_id` (format `KUPON-{id}`) — tidak ada perubahan layer API untuk payload.
- UNRECEIVE tidak memicu apa pun terhadap kupon yang sudah tercetak (kupon dianggap hangus, DB acuan).

### b. Validasi flag di SP Manage workflow

Di SP yang mengelola workflow template step & article workflow: tolak `print_kupon = 1` pada step non-bundle (pesan error Indonesia yang jelas). Konsisten dengan aturan existing urutan step non-bundle → bundle.

### c. SIS_Report_RekapPenjahit (read, SP terpisah)

`@EmployeeId, @Date` (date, default hari ini):

- Result set 1 (header): nama penjahit, line, tanggal terpilih, total per status.
- Result set 2 (detail): per bundle — serial + letter, artikel, size, qty, status.
- Definisi status mengikuti tiga kolom Prompt 30 (WIP, Menunggu QC → "Dicek", Qty Done → "Beres"), dengan filter: **Beres** hanya yang `received_at` jatuh pada `@Date` (00:00–24:00 waktu server); **WIP** dan **Dicek** = snapshot kondisi saat ini tanpa filter tanggal.

## 3. UI

### a. Checkbox "Cetak Kupon"
Di tempat yang sama dengan checkbox auto-terima (Prompt 34): editor step workflow template dan workflow artikel. Ikut tersalin saat APPLY. **Hanya aktif untuk step bertipe bundle** — di step non-bundle checkbox disabled dengan tooltip "Kupon hanya untuk step bundle". Tooltip normal: "Cetak kupon borongan otomatis saat hasil step ini dikonfirmasi diterima."

### b. Rekap Penjahit di /station
Tombol/tab **"Rekap Penjahit"** hanya di halaman station (tampil di semua station — divisi Bundling yang paling memakai, tapi tidak di-hardcode per divisi):

1. Dropdown cascading line → penjahit (pola Prompt 32).
2. Tekan **"Print Rekap"** → modal pilih tanggal, **default hari ini** (date picker sederhana, tidak boleh tanggal masa depan) → tampilkan ringkasan di layar: total Beres tanggal terpilih + WIP/Dicek saat ini + daftar bundle per status. WIP menonjol (badge kuning) — clue hanca menyendat.
3. Tombol **"Cetak Struk"** di modal → POST endpoint station → insert `print_jobs` `job_type = 'REKAP_PENJAHIT'`, payload = snapshot hasil SP saat itu (header + daftar bundle + tanggal). Toast konfirmasi "Rekap masuk antrian cetak."

### c. API station (station token auth, pola existing)
- GET `api/station/rekap-penjahit/{employeeId}?date=yyyy-MM-dd` → hasil SIS_Report_RekapPenjahit.
- POST `api/station/rekap-penjahit/{employeeId}/print` (body: date) → rakit payload + insert print_jobs, kembalikan print_job_id.

## 4. Worker Service — printer kedua (routing minimal)

`appsettings.json` service tambah:
- `KuponPrinterName` (nama printer struk di Windows; kosong → job kupon/rekap report error "Printer kupon belum dikonfigurasi").
- `KuponPaperWidthChars` (default 32, kertas 58 mm).
- `KuponQrEnabled` (default true; set false bila firmware printer tidak mendukung perintah QR `GS ( k` — kupon tetap tercetak lengkap tanpa QR, cukup tulis `KUPON-{log_id}` sebagai teks).

Worker:
- `BUNDLE_LABEL` → jalur TSPL existing → `PrinterName` (tidak berubah).
- `KUPON_BORONGAN` dan `REKAP_PENJAHIT` → `EscPosBuilder` baru → `KuponPrinterName` via `RawPrinterHelper` yang sama (raw bytes).
- DryRun: tulis bytes ke `./dryrun/{print_job_id}.escpos`.

### EscPosBuilder — kupon per bundle

```
        KUPON BORONGAN
        [step_name]
--------------------------------
Serial : B26-000153 (A-12)
Proyek : {project_name}
Artikel: {article_name}
         {style} {color}
Size   : {size_name}
--------------------------------
QTY OK :          {qty_ok} pcs    <- font double height/width
Reject : print {n} kain {n}
         jahit {n} rework {n}
Hilang : {qty_lost}
--------------------------------
Penjahit: {tailor_name}
{received_at dd/MM/yyyy HH:mm}
        [QR: KUPON-{log_id}]
```

### EscPosBuilder — rekap penjahit

```
        REKAP PENJAHIT
{tailor_name} - {line}
Tanggal: {dd/MM/yyyy}
--------------------------------
BERES {dd/MM}: {n} bdl / {qty} pcs   <- double
DICEK skrg  : {n} bdl / {qty} pcs
WIP skrg    : {n} bdl / {qty} pcs
--------------------------------
[BERES]
 A-12 M  24pcs   {dd/MM}
 ...
[DICEK]
 ...
[WIP]
 ...
--------------------------------
Dicetak {dd/MM/yyyy HH:mm}
```

- ESC/POS standar: `ESC @`, `ESC a`, `GS !` ukuran font, `GS ( k` QR (hanya kupon), `GS V` partial cut (printer tanpa cutter mengabaikan — aman).
- Baris qty nol boleh disembunyikan kecuali QTY OK / total status.
- Sanitasi teks seperti TsplBuilder.

## 5. Verifikasi

- `dotnet build` seluruh solution sukses.
- DryRun kupon: aktifkan `print_kupon` di step uji → HANDOVER lalu RECEIVE (atau auto-receive) → file `.escpos` muncul, job DONE. RECEIVE step tanpa flag → tidak ada job.
- DryRun rekap: dari station pilih penjahit → modal tanggal default hari ini → data Beres cocok dengan Report Produksi hari tersebut → Cetak → file `.escpos` muncul. Ganti ke tanggal kemarin → Beres berubah, WIP/Dicek tetap.
- Set `print_kupon = 1` pada step non-bundle via SP → ditolak dengan pesan error.
- Bundle label TSC tetap tercetak normal (regresi).

## Urutan deploy

1. `prompt_41_kupon_borongan.sql` (alter kolom)
2. SP: `SIS_WorkflowLog_Manage` versi baru + `SIS_Report_RekapPenjahit`
3. Deploy API + Client
4. Update worker service: binary baru + `KuponPrinterName`, restart
5. Pasang printer struk di PC printer (USB), tes cetak Windows
6. `seed_41_kupon_sew_qc.sql` (aktivasi) — atau centang via UI

## Yang TIDAK boleh dilakukan

- Jangan buat fitur scan/klaim kupon — cross-check manual saja.
- Jangan buat cetak ulang kupon per bundle — kertas rusak → andalkan Report Produksi. (Rekap boleh dicetak berulang, memang on-demand.)
- UNRECEIVE / CANCEL_HANDOVER / REVISE_HANDOVER tidak memicu cetak ulang maupun kupon void.
- Jangan ubah format/alur label bundle TSC maupun alur scan station selain penambahan yang disebut.
- Jangan aktifkan flag `print_kupon` otomatis di migration — hanya via seed/UI.
- Rekap Penjahit hanya per satu tanggal — jangan buat agregat mingguan/rentang tanggal di station (itu tetap domain Report Produksi admin).
- Jangan tampilkan Rekap Penjahit di halaman admin — station saja.
- Jangan implementasi kupon untuk step non-bundle — tolak di SP, disable di UI.
- Jangan pakai driver/SDK printer khusus — raw winspool seperti existing.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

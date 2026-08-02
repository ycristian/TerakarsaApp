# Prompt 42 — Rekap Produksi Struk Mingguan (Divisi / Resource / Penjahit)

## Konteks

Prompt 41 sudah live: kupon borongan per bundle + rekap penjahit harian di station. Prompt ini **mengganti rekap harian** dengan **Rekap Produksi mingguan** mengikuti periode gajian (Sabtu 10:00 → Sabtu 10:00, logika identik Report Produksi Prompt 30), dan menambah dua level agregasi baru: per **resource** dan per **divisi**, di samping per penjahit.

**Kupon per bundle TIDAK disentuh** — layout kupon sudah diperbarui langsung di sistem dan menjadi acuan regresi (lihat bagian Referensi Kupon di bawah).

Prinsip tetap: database acuan bayar, struk hanya cross-check.

## 1. Skema SQL

Tidak ada perubahan tabel. Hanya SP.

## 2. Stored Procedures

### a. SIS_Report_RekapStruk (read, SP baru — menggantikan SIS_Report_RekapPenjahit)

`@Level` (`DIVISION` | `RESOURCE` | `EMPLOYEE`), `@DivisionId`, `@ResourceId` (null kecuali level resource/employee), `@EmployeeId` (null kecuali level employee), `@Date` (date, default hari ini) → SP menghitung awal–akhir **periode gajian yang memuat `@Date`** (Sabtu 10:00; logika HARUS identik `SIS_Report_ProduksiAgg`).

- Result set 1 (header): nama divisi, nama resource/penjahit sesuai level (nama penjahit prioritas Prompt 32), awal–akhir periode.
- Result set 2 (detail harian): baris ber-`received_at` dalam periode — level employee: per bundle (serial letter+no, artikel, size, qty_ok, rp/rf/rs/rw/ls); level resource: agregat per penjahit per hari; level divisi: agregat per resource per hari. Selalu sertakan tanggal & nama artikel (grouping employee-level).
- Result set 3 (WIP snapshot saat ini): granularitas sama seperti result set 2.
- Definisi Qty Done & WIP mengikuti persis Prompt 30. Status "Dicek/Menunggu QC" TIDAK ada di rekap ini.

Notasi reject/lost (hanya bila > 0): `rp` = qty_reject_print, `rf` = qty_reject_fabric, `rs` = qty_reject_sewing, `rw` = qty_reject_rework, `ls` = qty_lost.

### b. Pembersihan

- Drop `SIS_Report_RekapPenjahit` (sertakan di script SQL manual).
- Job `print_jobs` lama ber-type `REKAP_PENJAHIT` yang masih PENDING (kalau ada) dibiarkan — worker baru menandainya ERROR "job type usang"; tidak perlu migrasi.

## 3. UI — /station

Tab "Rekap Penjahit" diubah menjadi **"Rekap Produksi"**:

1. Dropdown bertingkat: **Divisi** (wajib) → **Resource** (opsional) → **Penjahit** (opsional, cascading pola Prompt 32). Level rekap = pilihan terdalam yang diisi.
2. Tekan **"Print Rekap"** → modal pilih tanggal, **default hari ini** (tidak boleh masa depan), modal menampilkan rentang periode gajian hasil hitungan (mis. "Sab 01/08 10:00 – Sab 08/08 10:00") + total pcs periode, supaya operator yakin minggu yang dicetak.
3. Tombol **"Cetak Struk"** → POST endpoint → insert `print_jobs` `job_type = 'REKAP_PRODUKSI'`, payload = snapshot hasil SP (header + detail harian + WIP + level). Toast "Rekap masuk antrian cetak."

### API station (station token auth, pola existing)
- GET `api/station/rekap-struk?level=&divisionId=&resourceId=&employeeId=&date=yyyy-MM-dd` → hasil SIS_Report_RekapStruk (isi modal).
- POST `api/station/rekap-struk/print` (body: parameter sama) → rakit payload + insert print_jobs, kembalikan print_job_id.
- Endpoint rekap-penjahit lama dihapus.

## 4. Worker Service

- Handler `REKAP_PENJAHIT` diganti `REKAP_PRODUKSI` dengan layout baru di `EscPosBuilder`. Jalur `KUPON_BORONGAN` dan `BUNDLE_LABEL` TIDAK diubah.

### Layout rekap produksi (contoh level employee, 32 char, mengikuti mockup)

```
Rekap {Nama Divisi}              <- BOLD
{Nama Penjahit} - {Resource}     <- BOLD
--------------------------------
Sabtu, 01/08                     <- bold
{Nama Artikel}
  F-329  M    50
  F-392  L    60 rp:2 rw:25
{Nama Artikel}
  B-329  M    50
                 280 pcs         <- bold, rata kanan
                 rp:2/rw:25      <- bold, rata kanan
Minggu, 02/08                    <- bold
  ...
--------------------------------
        TOTAL  840 pcs           <- BOLD double
               rp:8/rw:75        <- BOLD
--------------------------------
> WORK IN PROGRESS (WIP) <
{Nama Artikel}
  F-329  M    50 pcs
  F-392  L    60 pcs
--------------------------------
                 WIP  160 pcs    <- BOLD

Dicetak {dd/MM/yyyy HH:mm}
```

- Level **resource**: baris bundle diganti baris per penjahit (`{nama}  {pcs} {kode reject}`); level **divisi**: baris per resource. Struktur hari, subtotal harian, TOTAL, dan WIP sama.
- Kode reject/lost hanya bila > 0; bila baris melebihi lebar kertas, kode turun ke baris berikutnya ber-indentasi.
- Hari tanpa aktivitas dilewati. Format hari Indonesia: `Sabtu, 01/08`.

## Referensi Kupon (JANGAN DIUBAH — regresi)

Layout kupon yang sudah live di sistem:

```
Coupon {workflow_log_id} - {Nama Divisi}   <- BOLD
--------------------------------
{serial} ({letter}-{no})                   <- BOLD
{customer/PT}
{nama artikel}
{warna}
Size : {size}
--------------------------------
{Resource} ({resource person}) - {employee} <- BOLD
Qty OK       : {n} pcs                     <- bold
Reject ...   : {n} pcs   (baris qty hanya bila > 0)
Rework       : {n} pcs
Lost         : {n} pcs
--------------------------------
{tanggal waktu created_at/updated_at}
```

Verifikasi regresi: setelah deploy Prompt 42, kupon tercetak persis seperti ini.

## 5. Verifikasi

- `dotnet build` seluruh solution sukses.
- DryRun rekap: pilih divisi → resource → penjahit, modal tanggal default hari ini menampilkan rentang periode gajian benar → total pcs cocok dengan Qty Done Report Produksi periode & operator sama → Cetak → file `.escpos` sesuai layout (grouping hari/artikel). Uji juga level resource dan level divisi.
- Tanggal Sabtu sebelum vs sesudah jam 10:00 masuk ke periode yang berbeda (uji batas cutoff).
- Kupon per bundle tetap tercetak persis layout referensi (regresi). Bundle label TSC normal.

## Urutan deploy

1. SP: `SIS_Report_RekapStruk` + drop `SIS_Report_RekapPenjahit` (script SQL manual)
2. Deploy API + Client
3. Update worker service, restart

## Yang TIDAK boleh dilakukan

- Jangan sentuh layout/jalur kupon `KUPON_BORONGAN` dan label `BUNDLE_LABEL`.
- Rekap hanya per satu periode gajian (dihitung dari tanggal terpilih) — jangan buat rentang tanggal bebas.
- Jangan tampilkan Rekap Produksi di halaman admin — station saja.
- Jangan tampilkan status "Dicek/Menunggu QC" di rekap struk.
- Jangan ubah SP Report Produksi (Prompt 30) — hanya samakan logika periodenya.
- Jangan pakai driver/SDK printer khusus — raw winspool existing.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

# Prompt 26 — Surat Jalan: Kumpulan Karung, PDF Cetak, Info Pengiriman di Scan

## Prasyarat

Dijalankan SETELAH Prompt 25 (memakai packs/pack_items dan menyentuh SIS_Pack_Manage + SIS_Pack_ScanInfo — jangan paralel).

## Konteks & keputusan desain (sudah disepakati)

Karung yang sudah dikonfirmasi dikelompokkan ke **surat jalan (SJ)** untuk pengiriman ke konsumen. Dibuat dari stasiun packing yang sama (station token, `enable_packing`).

- **1 SJ = 1 project.** Karung tidak boleh campur project, dan satu karung maksimal ada di SATU SJ hidup.
- Hanya karung TERKONFIRMASI (semua baris qty_actual NOT NULL) yang boleh masuk SJ.
- Nomor SJ auto: `SJ{yy}-{nomor urut global 4 digit}` (mis. `SJ26-0007`), applock `shipment_no_seq`, pola generator serial bundle/pack.
- Field (bisa berkembang nanti): tanggal kirim, nama konsumen/tujuan, alamat, nama driver, no kendaraan, catatan.
- Output: **PDF** (dirakit di API dengan **QuestPDF**, license Community) — diunduh/dibuka dari stasiun, dicetak ke printer dokumen biasa. Printer TSC tidak dipakai untuk SJ.
- Scan karung (`/pack/{serial}`) menampilkan info pengirimannya bila karungnya sudah masuk SJ hidup.

## 1. Skema SQL

Tambahkan ke `sql/create_tables_tmos_final.sql` (section PACKING) + buat `sql/alter_26_shipments.sql` (idempotent):

```sql
CREATE TABLE shipments(
 shipment_id int primary key identity(1,1),
 shipment_no varchar(20) not null,          -- SJ{yy}-{4 digit global}
 project_id int not null
   constraint FK_shipments_projects foreign key references projects(project_id),
 ship_date date not null,
 customer_name varchar(150) not null,
 destination_address varchar(500) null,
 driver_name varchar(150) null,
 vehicle_no varchar(30) null,
 remark varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 delete_reason varchar(255) null
);

CREATE TABLE shipment_packs(
 shipment_pack_id int primary key identity(1,1),
 shipment_id int not null
   constraint FK_shipment_packs_shipments foreign key references shipments(shipment_id),
 pack_id int not null
   constraint FK_shipment_packs_packs foreign key references packs(pack_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 deleted_at datetime2 null,
 deleted_by int null
);
```

Index: filtered unique `UX_shipments_no ON shipments(shipment_no) WHERE deleted_at IS NULL`; filtered unique `UX_shipment_packs_pack ON shipment_packs(pack_id) WHERE deleted_at IS NULL` (menegakkan 1 karung 1 SJ hidup di level DB); index `IX_shipment_packs_shipment`.

## 2. Stored Procedures

### `sql/sp_Shipment_Manage.sql` — SIS_Shipment_Manage (@Action)

Daftar karung dikirim sebagai `@PackIdsJson` (array int, OPENJSON).

- **CREATE** (@ProjectId, @ShipDate, @CustomerName, @DestinationAddress, @DriverName, @VehicleNo, @Remark, @PackIdsJson, @UserId):
  - Validasi tiap pack: hidup, milik @ProjectId, terkonfirmasi penuh, belum ada di SJ hidup lain. Gagal → RAISERROR menyebut nomor karungnya.
  - Minimal 1 karung. shipment_no digenerate dalam applock `shipment_no_seq` (global, termasuk soft-deleted).
  - Insert shipments + shipment_packs. Kembalikan shipment_id + shipment_no.
- **UPDATE** (@Id, field header + @PackIdsJson): ubah header dan komposisi karung (soft delete link yang hilang, insert yang baru, validasi sama; karung yang dilepas otomatis bebas dipakai SJ lain). project_id TIDAK boleh berubah.
- **DELETE** (@Id, @DeleteReason wajib, @UserId): soft delete shipments + shipment_packs. Karung kembali bebas.

### `sql/sp_Shipment_Select.sql`

- **SIS_Shipment_ListByProject** (@ProjectId): SJ hidup: header + jumlah karung + total pcs (Σ qty_actual). Result set kedua: karung per SJ (pack_no, serial, total pcs).
- **SIS_Shipment_GetById** (@Id): tiga result set untuk form edit dan data PDF — header (JOIN project_name), daftar karung (pack_no, serial, total pcs aktual), detail isi per karung (article_name, style, color, size_name, qty_actual).
- **SIS_Shipment_EligiblePacks** (@ProjectId, @ShipmentId INT = NULL): karung hidup terkonfirmasi yang belum terikat SJ hidup — atau terikat @ShipmentId sendiri (untuk mode edit).

### Revisi SP Prompt 25 (wajib)

- **SIS_Pack_ScanInfo**: tambah result set ke-3 — info SJ hidup karung ini (shipment_no, ship_date, customer_name, destination_address, driver_name, vehicle_no) atau kosong.
- **SIS_Pack_Manage**:
  - DELETE: tolak bila karung ada di SJ hidup — 'Karung ada di Surat Jalan %s — lepaskan dulu dari SJ.'
  - CONFIRM: tetap boleh saat karung sudah di SJ (fakta terakhir di lapangan), tapi qty_actual tidak boleh di-NULL-kan kembali.
- **SIS_Pack_ListByProject**: tambah kolom shipment_no (SJ hidup) per karung — dipakai badge di kartu.

## 3. API

Semua di bawah [RequireStationToken] + `enable_packing` (filter Prompt 25):

- GET `api/station/shipping/shipments/{projectId}` → SIS_Shipment_ListByProject.
- GET `api/station/shipping/shipment/{id}` → SIS_Shipment_GetById.
- GET `api/station/shipping/eligible-packs/{projectId}?shipmentId=` → SIS_Shipment_EligiblePacks.
- POST `api/station/shipping/shipments` / PUT `.../{id}` / DELETE `.../{id}` (reason wajib).
- GET `api/station/shipping/shipments/{id}/pdf` → `application/pdf`, nama file `SuratJalan-{shipment_no}.pdf`. PDF dirakit ON DEMAND dari data terkini (tidak disimpan ke disk/DB).

## 4. PDF — QuestPDF

Package `QuestPDF` di project API; set `QuestPDF.Settings.License = LicenseType.Community;` sekali di Program.cs. Class `ShipmentPdfBuilder` (folder Services), A4 potret:

- Kop: "SURAT JALAN" besar + "Terakarsa" ; kanan: No SJ + tanggal kirim.
- Blok tujuan: konsumen, alamat. Blok transport: driver, no kendaraan. Project name.
- Tabel: No | Karung No. | Serial | Isi (baris per item: "Artikel — Size — qty pcs", qty AKTUAL) | Total pcs per karung.
- Footer tabel: total karung + total pcs.
- Catatan (bila ada), lalu tiga kolom tanda tangan: Pengirim / Driver / Penerima (kotak kosong + garis nama).
- Teks label dalam Bahasa Indonesia.

## 5. Blazor Client

### `/station` — modul Packing, sub-tab baru "Surat Jalan"
1. List SJ project terpilih: kartu shipment_no, tanggal, konsumen, jumlah karung, total pcs. Tombol: **PDF** (buka tab baru / unduh), **Edit**, **Hapus** (alasan wajib).
2. **Buat SJ**: form field header + daftar karung eligible (checkbox multi-pilih, tampil pack_no + serial + total pcs). Edit memakai form yang sama (karung milik SJ ini ikut tampil tercentang).
3. Kartu karung (tab Karung, Prompt 25): tambah badge nomor SJ bila sudah terikat.

Catatan unduh PDF: dari halaman station, panggil endpoint dengan header X-Station-Token via JS interop / fetch blob (link `<a href>` biasa tidak membawa header) lalu trigger download/open.

### Halaman publik `/pack/{serial}`
Section baru "Info Pengiriman" tampil hanya bila result set SJ terisi: no SJ, tanggal kirim, konsumen, tujuan, driver + kendaraan.

## 6. Verifikasi

- Karung belum konfirmasi → tidak muncul di eligible dan tertolak di SP.
- Buat SJ 2 karung → shipment_no SJ26-0001; karung tidak bisa dimasukkan SJ kedua (unique index + validasi); badge SJ muncul di kartu karung.
- PDF: tabel isi sesuai qty aktual, total benar, terbuka di viewer PDF standar.
- Edit qty aktual karung setelah masuk SJ → unduh ulang PDF menampilkan qty baru.
- Hapus karung yang ada di SJ → tertolak. Hapus SJ → karung bebas lagi.
- `/pack/{serial}` karung ber-SJ menampilkan Info Pengiriman; tanpa SJ tidak menampilkan section.

## Yang TIDAK boleh dilakukan

- Jangan sentuh alur bundle/workflow log, layout label TSPL, atau print_jobs (SJ tidak lewat printer TSC).
- Jangan simpan file PDF ke disk/DB — selalu dirakit on demand.
- Jangan izinkan karung lintas project dalam satu SJ.

Setelah selesai: daftar file yang diubah/dibuat.

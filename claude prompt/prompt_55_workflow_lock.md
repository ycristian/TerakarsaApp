# Prompt 55 — Lock Workflow Log per Baris + Periode Gajian (Fondasi Data)

## Konteks

Disiplin input di lapangan sulit dicocokkan dengan sistem: aturan revisi berbasis waktu
(jendela 1 jam, H+1, "terkunci begitu diterima") terlalu kaku untuk koreksi yang wajar,
tapi di sisi lain tidak ada titik di mana data dinyatakan final. Prompt ini mengganti
semua aturan itu dengan satu konsep: **lock**.

Aturan baru, berlaku untuk SEMUA divisi (bundle maupun non-bundle):

1. Baris `article_workflow_logs` yang **belum di-lock** boleh diubah/dihapus kapan pun,
   termasuk setelah diterima divisi berikutnya — asal **saldo tidak jadi minus**
   (lihat Bagian 4).
2. Baris yang **sudah di-lock** tidak bisa diubah/dihapus lewat jalur apa pun (stasiun,
   halaman admin, maupun Super Admin). Satu-satunya jalan: **request unlock** yang
   disetujui admin.
3. Lock dilakukan PIC di stasiun, per baris (dipilih lewat checklist — UI di Prompt 56).
   Saat lock, PIC menentukan baris tersebut masuk **periode gajian** mana.
4. Lock hanya menyangkut sisi pengirim (baris OUT milik divisi pembuat). Sisi penerima
   (RECEIVE/UNRECEIVE, kolom `received_*`) TIDAK dikunci.

Prompt ini murni **SQL**: tabel, seed periode, guard di SP, SP lock & request unlock,
script go-live. API + UI stasiun di Prompt 56, halaman approval admin di Prompt 57.
Jangan kerjakan API/UI di sini.

## 1. Skema

Semua tabel baru mengikuti kolom audit standar CLAUDE.md. Perbarui
`sql/create_tables_tmos_final.sql` dan buat `sql/alter_55_workflow_lock.sql` (idempotent).
Tidak ada kolom status di tabel mana pun — keadaan diturunkan dari timestamp.

### a. `payroll_periods`

Periode gajian yang selama ini hanya rumus (Sabtu 10:00, Prompt 30) sekarang jadi baris.

| Kolom | Tipe | Catatan |
|---|---|---|
| payroll_period_id | int identity PK | |
| period_year | smallint not null | |
| period_no | tinyint not null | 1..52/53 |
| period_code | varchar(10) not null | format `2026-P40` (sengaja bukan `W` supaya tidak tertukar dengan ISO week) |
| period_start | datetime2 not null | inklusif |
| period_end | datetime2 not null | eksklusif |
| finalized_at | datetime2 null | disiapkan, belum ada UI finalisasi |
| finalized_by | int null | |
| + audit standar | | |

Filtered unique index: `(period_year, period_no)` dan `period_code`, `WHERE deleted_at IS NULL`.

**Aturan penomoran** (wajib persis):
- Periode ke-N tahun Y **berakhir** di Sabtu ke-N tahun Y, jam 10:00.
  `period_end` = Sabtu ke-N jam 10:00, `period_start` = `period_end` − 7 hari.
- Jumlah periode dalam setahun = jumlah hari Sabtu di tahun itu (52 atau 53).
- Contoh 2026 (Sabtu pertama = 3 Jan): P01 = 27 Des 2025 10:00 → 3 Jan 2026 10:00;
  P40 = 26 Sep 2026 10:00 → 3 Okt 2026 10:00; P52 = 19 Des → 26 Des 2026 10:00.
  Log 26 Des 2026 jam 11:00 masuk **2027-P01**.
- Periode antar tahun harus bersambung tanpa celah/tumpang tindih — verifikasi di akhir
  seed: `period_start` tiap periode = `period_end` periode sebelumnya.
- Rentang ini identik dengan rumus Prompt 30 (`BuildPeriods()` di ReportProduksi.razor,
  `SIS_Report_LineTrendWeekly`) — hanya diberi nomor. Jangan buat definisi periode baru.
- Hitung hari dalam minggu independen dari `@@DATEFIRST` (pola `@Dow` yang sudah ada di
  `SIS_Report_LineTrendWeekly`).

Fungsi bantu `dbo.SIS_fn_PayrollPeriodIdAt(@At datetime2)` → `payroll_period_id` yang
memuat waktu itu (`period_start <= @At < period_end`), NULL kalau belum di-generate.

### b. `workflow_locks` — header satu kali tekan Lock

| Kolom | Tipe | Catatan |
|---|---|---|
| lock_id | int identity PK | |
| division_id | int not null FK divisions | divisi pemilik baris |
| station_id | int null FK stations | NULL untuk lock sistem (go-live) |
| payroll_period_id | int not null FK payroll_periods | dipilih PIC saat lock |
| locked_by_resource_id | int null FK resources | operator sesi stasiun |
| locked_by_name | varchar(150) null | diisi hanya untuk lock sistem (`'SYSTEM - GO LIVE'`); nanti dipakai identitas kartu NFC |
| locked_at | datetime2 not null default sysdatetime() | |
| + audit standar | | |

### c. `workflow_lock_items` — isi lock + riwayat

| Kolom | Tipe | Catatan |
|---|---|---|
| lock_item_id | int identity PK | |
| lock_id | int not null FK workflow_locks | |
| workflow_log_id | int not null FK article_workflow_logs | |
| snap_qty_ok, snap_qty_reject_print, snap_qty_reject_fabric, snap_qty_reject_sewing, snap_qty_reject_rework, snap_qty_lost | int not null | snapshot saat lock |
| snap_article_size_id | int null | |
| snap_resource_id | int null | |
| snap_target_division_id | int null | |
| released_at | datetime2 null | terisi saat lock ini dilepas oleh request unlock yang disetujui |
| released_by_request_id | int null FK unlock_requests | |
| + audit standar | | |

Filtered unique index: `workflow_log_id WHERE released_at IS NULL AND deleted_at IS NULL`
(satu baris log maksimal punya satu lock aktif).

### d. `article_workflow_logs` — tambah kolom

- `lock_id int null` + FK ke `workflow_locks` — menunjuk lock yang sedang berlaku.
  NULL = bebas diedit. Index `IX_awl_lock_id`.
- Periode gajian sebuah log = `lock_id → workflow_locks.payroll_period_id`. Jangan
  menambah kolom periode di log.

### e. `unlock_requests`

| Kolom | Tipe | Catatan |
|---|---|---|
| request_id | int identity PK | |
| division_id | int not null FK | |
| station_id | int null FK | |
| reason | varchar(500) not null | wajib |
| requested_by_resource_id | int null FK resources | operator sesi |
| approved_at, approved_by | datetime2 null, int null | |
| rejected_at, rejected_by | datetime2 null, int null | |
| admin_note | varchar(500) null | wajib saat REJECT |
| + audit standar | | pembatalan oleh pengaju = soft delete |

Keadaan: menunggu = `approved_at IS NULL AND rejected_at IS NULL AND deleted_at IS NULL`.

### f. `unlock_request_items`

| Kolom | Tipe | Catatan |
|---|---|---|
| request_item_id | int identity PK | |
| request_id | int not null FK | |
| workflow_log_id | int not null FK | |
| lock_item_id | int not null FK workflow_lock_items | lock aktif yang diminta dilepas |
| + created_at, created_by | | |

## 2. Seed periode

`sql/seed_55_payroll_periods.sql` (idempotent): panggil
`SIS_PayrollPeriod_Manage @Action = 'GENERATE_YEAR'` untuk 2026 dan 2027.

`SIS_PayrollPeriod_Manage`:
- `GENERATE_YEAR` (@Year, @UserId): insert periode tahun itu yang belum ada (cek per
  `period_year + period_no`), aturan Bagian 1a. Aman dipanggil berulang.
- `FINALIZE` / `UNFINALIZE`: **jangan dibuat** di prompt ini (UI finalisasi menyusul).

## 3. Guard lock

Pesan seragam, prefix tetap supaya UI bisa mengenali:
`'LOCKED|Data sudah di-lock. Ajukan unlock untuk mengubah.'`

Terapkan pengecekan `lock_id IS NOT NULL` → tolak, pada aksi berikut:

**`SIS_WorkflowLog_Manage`**: `UPDATE`, `REVISE_HANDOVER`, `CANCEL_HANDOVER`, `DELETE`.
Tidak dikunci: `CREATE`, `ADJUST` (keduanya membuat baris baru), `RECEIVE`, `UNRECEIVE`.

**`SIS_Bundle_Manage`**: `UPDATE`, `DELETE` — cek `lock_id` baris log Bundling
(`is_bundling = 1`) milik bundle itu.

**`SIS_SuperAdmin_Manage`**: `LOG_UPDATE`, `LOG_DELETE`, `EDIT_LOG` (cek baris log),
`BUNDLE_UPDATE`, `EDIT_BUNDLE` (cek baris log Bundling bundle itu). Super Admin tidak
punya jalan pintas — lock berlaku untuk semua.

## 4. Ganti aturan revisi lama dengan guard saldo

### a. Aturan lama yang DIHAPUS

Di `SIS_WorkflowLog_Manage`:
- `UPDATE`: guard `received_at IS NULL` dan jendela H+1 step terakhir (Prompt 23).
- `REVISE_HANDOVER`: guard `received_at IS NULL` untuk perubahan qty/remark/resource.
  **Perubahan `target_division_id` tetap hanya boleh selama `received_at IS NULL`**
  (penerimaan melekat pada divisi tujuan lama).
- `CANCEL_HANDOVER`: guard `received_at IS NULL` dan jendela H+1.
- `DELETE`: guard "sudah dipakai sebagai dasar step berikutnya".

Di `SIS_Bundle_Manage`:
- `UPDATE` & `DELETE`: jendela 1 jam sejak `bundles.created_at` dan guard
  "Bundle sudah diproses" / "sudah diterima divisi berikutnya".

Rapikan juga komentar header SP yang menjelaskan aturan lama supaya tidak menyesatkan
(cukup tandai "diganti Prompt 55: lock + saldo").

### b. Guard saldo (pengganti)

Satu prinsip: **perubahan ditolak hanya kalau membuat saldo negatif DAN memperburuk
saldo** dibanding sebelum perubahan. Perubahan yang menaikkan qty selalu lolos. Ini
penting karena data lama bisa sudah minus — jangan sampai baris seperti itu tidak bisa
dikoreksi sama sekali.

Buat fungsi bersama supaya semua SP memakai rumus yang sama:

**Step ber-bundle** — `dbo.SIS_fn_BundleNextStepTotal(@ArticleWorkflowId, @BundleId)`:
total `qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing +
qty_reject_rework + qty_lost` baris hidup bundle itu di step ber-bundle berikutnya
(sort_order terdekat di atas). Rumus ini SAMA dengan validasi arah bawah yang sudah ada di
`SIS_SuperAdmin_Manage` `EDIT_LOG`/`EDIT_BUNDLE` — salin logikanya, jangan buat definisi
lain. Saldo = `SUM(qty_ok)` baris hidup (step, bundle) − next total.
- Log `UPDATE`/`REVISE_HANDOVER`: hitung saldo dengan nilai baru.
- Log `DELETE`/`CANCEL_HANDOVER`: hitung saldo tanpa baris itu.
- Bundle `UPDATE`: `@Qty` baru ≥ next total (step setelah Bundling). Kalau sudah ada
  baris hidup di step berikutnya, **perubahan ukuran dan line/penjahit ditolak**
  ('Bundle sudah diproses step berikutnya, hanya qty yang bisa diubah.') — qty tetap boleh.
- Bundle `DELETE`: sama dengan qty = 0.

**Step non-bundle** — `dbo.SIS_fn_NonBundleSaldo(@ArticleWorkflowId, @ArticleSizeId)`:
`SUM(qty_ok)` baris hidup step itu untuk size itu, dikurangi pemakaian hilir:
- kalau step berikutnya juga non-bundle: total keenam qty step itu untuk size sama;
- kalau step berikutnya ber-bundle (biasanya Bundling): `SUM(bundles.qty)` bundle hidup
  artikel + size itu.
Terapkan di `UPDATE`, `REVISE_HANDOVER`, `DELETE`, `CANCEL_HANDOVER` baris non-bundle.
Perubahan size (`article_size_id`) dihitung sebagai pengurangan di size lama + penambahan
di size baru — cek saldo size lama.

Pesan: `'Perubahan membuat saldo minus (sisa %d, dipakai step berikutnya %d). Ubah step berikutnya terlebih dahulu.'`

Validasi lain yang sudah ada (kuota `QTY_EXCEED|`/`QTY_SHORT|`, qty negatif, project
terkunci Prompt 18, divisi pembuat, resource milik divisi) **tetap berlaku**, jangan diubah.

## 5. SP lock — `SIS_WorkflowLock_Manage`

Parameter: `@Action`, `@WorkflowLogIds varchar(max)` (CSV, pola `STRING_SPLIT` seperti
SP lain), `@DivisionId`, `@StationId`, `@ResourceId`, `@PayrollPeriodId`, `@UserId`.

### `@Action = 'LOCK'`

Validasi (semua baris sekaligus, tolak seluruhnya kalau satu gagal — sebut ID yang gagal):
1. Minimal satu ID.
2. Setiap baris hidup, `division_id = @DivisionId` (hanya baris OUT milik divisi ini),
   `lock_id IS NULL` ('Sebagian baris sudah di-lock, muat ulang data.').
3. `@ResourceId` wajib, resource hidup milik `@DivisionId` ('Operator wajib dipilih.').
4. Periode hidup dan `finalized_at IS NULL` ('Periode gajian sudah final.').
5. Periode tidak lebih jauh dari **satu periode setelah periode berjalan**
   (`period_start <= period_end periode berjalan`) — mencegah salah pilih ke masa depan.
   Periode lampau yang belum final boleh.

Eksekusi dalam satu transaksi: insert `workflow_locks` → insert `workflow_lock_items`
dengan snapshot kolom qty/size/resource/target dari baris saat ini → `UPDATE
article_workflow_logs SET lock_id = <baru>`. Kembalikan `lock_id` + jumlah baris.

Tidak ada `UNLOCK` langsung di SP ini — pelepasan hanya lewat request (Bagian 6).

## 6. SP request unlock — `SIS_UnlockRequest_Manage`

### `CREATE` (dari stasiun)
Parameter: `@WorkflowLogIds` (CSV), `@Reason`, `@DivisionId`, `@StationId`,
`@ResourceId`, `@UserId`.
1. Alasan wajib, minimal 5 karakter.
2. Setiap baris hidup, `division_id = @DivisionId`, `lock_id IS NOT NULL`.
3. Tidak ada baris yang sedang ada di request lain yang masih menunggu
   ('Sebagian baris sudah diajukan dan menunggu approval.').
4. Periode lock tiap baris belum final.
5. `@ResourceId` wajib dan milik divisi.
Insert header + item (`lock_item_id` = item aktif baris itu). Kembalikan `request_id`.

### `CANCEL` (dari stasiun, oleh divisi pengaju)
Hanya request yang masih menunggu, `division_id` sama. Soft delete.

### `APPROVE` (dari admin, Prompt 57)
`@Id`, `@UserId`, `@AdminNote` opsional.
1. Request masih menunggu.
2. Periode setiap lock item belum final (cek ulang, bisa berubah sejak diajukan).
3. Setiap item: `lock_item_id` masih aktif (`released_at IS NULL`) dan
   `article_workflow_logs.lock_id` masih menunjuk lock item itu.
Eksekusi satu transaksi: set `approved_at/by`, `admin_note` → item lock:
`released_at = SYSDATETIME(), released_by_request_id = @Id` → log: `lock_id = NULL`.
Header `workflow_locks` lama TIDAK dihapus (riwayat).

### `REJECT` (dari admin)
`@Id`, `@UserId`, `@AdminNote` wajib. Hanya request menunggu. Set `rejected_at/by`.

## 7. Script go-live

`sql/golive_55_lock_existing.sql`, dijalankan manual SEKALI oleh developer saat fitur
dinyalakan. Variabel di baris paling atas yang WAJIB diisi developer:
`DECLARE @GoLiveAt datetime2 = NULL; -- isi, mis. '2026-10-03 10:00'` — script berhenti
dengan pesan jelas kalau masih NULL.

- Semua baris log hidup dengan `created_at < @GoLiveAt` dan `lock_id IS NULL` di-lock.
- Kelompokkan per (`division_id`, periode dari `created_at` via
  `SIS_fn_PayrollPeriodIdAt`) → satu header `workflow_locks` per kelompok,
  `station_id = NULL`, `locked_by_resource_id = NULL`,
  `locked_by_name = 'SYSTEM - GO LIVE'`, `created_by` = user sistem station
  (cari berdasarkan nama/username, jangan hardcode ID).
- Kalau ada baris yang periodenya tidak ditemukan (belum di-generate), berhenti dan
  laporkan tanggal-tanggalnya — jangan lock sebagian.
- Idempotent: dijalankan ulang tidak membuat lock ganda.
- Cetak ringkasan: jumlah header dan baris per divisi.

## 8. CLAUDE.md

Tambahkan di "Aturan aplikasi", setelah butir log workflow model 1 baris:

> - Lock log workflow (Prompt 55): baris dengan `lock_id` terisi tidak boleh diubah/dihapus
>   lewat SP mana pun (termasuk Super Admin) — pesan `LOCKED|`. Baris belum lock boleh
>   diubah kapan pun selama saldo tidak jadi minus. Periode gajian log = periode di
>   `workflow_locks`, bukan dari `created_at`. Pelepasan lock hanya lewat
>   `SIS_UnlockRequest_Manage` APPROVE.

## Yang TIDAK boleh dilakukan

- Jangan buat/ubah endpoint API atau halaman Blazor (Prompt 56 & 57).
- Jangan ubah SP laporan (Report Produksi, Line Detail, kupon borongan, rekap) — mereka
  tetap memakai `created_at` sampai ada prompt terpisah.
- Jangan ubah SP read stasiun (`SIS_Station_*`, `SIS_Bundle_ScanInfo`) — penyesuaian
  tampilan di Prompt 56.
- Jangan kunci `RECEIVE`/`UNRECEIVE`/`CREATE`/`ADJUST`.
- Jangan tambah kolom status di tabel mana pun.
- Jangan hardcode ID divisi/resource/user di script seed atau go-live.
- Jangan refactor bagian SP di luar guard yang disebut di prompt ini.

## Verifikasi (tulis sebagai script `sql/test_55_workflow_lock.sql`, dijalankan manual, dalam transaksi yang di-ROLLBACK di akhir)

1. Periode 2026: 52 baris; P01 mulai 2025-12-27 10:00; P40 = 2026-09-26 10:00 → 2026-10-03 10:00;
   `SIS_fn_PayrollPeriodIdAt('2026-12-26 11:00')` = 2027-P01; tidak ada celah antar periode.
2. LOCK 2 baris → keduanya `lock_id` terisi, 2 item dengan snapshot benar.
3. UPDATE / DELETE / CANCEL_HANDOVER baris terkunci → error `LOCKED|`.
4. RECEIVE / UNRECEIVE baris terkunci → tetap berhasil.
5. UPDATE baris belum lock yang sudah diterima → berhasil (dulu ditolak).
6. Turunkan qty_ok baris ber-bundle di bawah total step berikutnya → error saldo;
   naikkan → berhasil.
7. CREATE request → APPROVE → `lock_id` NULL, item lama `released_at` terisi,
   baris bisa diedit lagi; LOCK ulang → item baru, item lama tetap tersimpan.
8. CREATE request untuk baris yang sudah punya request menunggu → ditolak.

Setelah selesai: daftar file dibuat/diubah + urutan script SQL yang harus dijalankan
manual, masing-masing sebagai markdown link.

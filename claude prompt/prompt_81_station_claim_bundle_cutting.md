# Prompt 81 — Station Bundling: Claim bundle cutting ke Line + cetak label penyerahan

Lanjutan Prompt 80. Hanya **menambah sistem claim** di jalur "Scan Stok Bundle".
Semua alur yang sudah berjalan (bundle manual, hamparan/cutting, tab IN/OUT/WIP,
SP workflow log, builder stiker cutting) **TIDAK boleh diubah**.

## 0. Masalah

Bundle hasil cutting (mis. `R1` / `B26-005676`) sudah terbit dan stikernya sudah
menempel, tapi belum ada Line/penjahit yang memilikinya. Saat ini
`SIS_CuttingBundle_Take` hanya menandai `stock_status = TAKEN` dan menulis log
Bundling **PENDING** (`received_at` NULL) — Line baru ditentukan belakangan di tab
Masuk divisi tujuan. Akibatnya selama pending: `bundles.resource_id` NULL sehingga
semua Line di divisi tujuan melihat kolam yang sama
(`sql/sp_Station_Operations.sql`, filter Line di `SIS_Station_PendingReceives`), dan
qty-nya masuk penampung "Belum ditentukan line" di laporan line detail.

Yang diminta: di station Bundling, satu sesi scan bisa langsung **claim** bundle ke
Line jahit (+ penjahit opsional), lalu **cetak label bundle** yang memuat nama Line
dan penjahit — sama seperti label bundle manual.

## 1. Serial tidak berubah

Claim **tidak** membuat bundle/serial baru. `bundles.serial` unik global dan QR
`/b/<serial>` sudah tercetak di stiker cutting serta dikenali scanner station. Label
hasil claim = cetak ulang bundle yang sama dalam layout `BUNDLE_LABEL` (job type yang
sudah ada, bukan `CUTTING_BUNDLE_LABEL`). Kolom `needs_reprint` milik stiker cutting
tidak disentuh.

## 2. SP — `SIS_CuttingBundle_Take` (`sql/cutting/sp_80_CuttingTake.sql`)

Tambah parameter, **semuanya opsional** supaya perilaku Prompt 80 tetap utuh:

- `@TargetResourceId INT = NULL` — Line/penjahit tujuan.
- `@EmployeeId INT = NULL` — penjahit dari master, opsional (mengikuti bundle manual:
  resource wajib, employee boleh kosong).

Aturan:

- `@TargetResourceId IS NULL` → **perilaku lama persis**: log Bundling PENDING,
  `bundles.resource_id` tidak diisi. Tidak ada cabang lain yang berubah.
- `@TargetResourceId` terisi → claim:
  - Validasi resource hidup, `is_active = 1`, dan `division_id = @BundlingTargetDivisionId`
    (divisi step sesudah Bundling — divisi yang jadi `target_division_id` log). Pesan:
    `Line tujuan tidak valid untuk artikel ini.`
  - Validasi `@EmployeeId` (bila diisi) hidup dan `resource_id = @TargetResourceId`.
    Pesan sama dengan bundle manual: `Penjahit bukan anggota line ini.`
  - `UPDATE bundles SET resource_id = @TargetResourceId, employee_id = @EmployeeId`
    bersama `stock_status`/`taken_at`/`taken_by_resource_id` yang sudah ada.
  - Log Bundling di-INSERT langsung diterima: `received_at = SYSDATETIME()`,
    `received_by_resource_id = @TargetResourceId`,
    `received_remark = 'Otomatis: bundle cutting diklaim Line'`. Ini mengikuti aturan
    #10 `sql/sp_Bundle_Manage.sql` (Prompt 25) — `received_by_resource_id` **harus**
    resource divisi tujuan, bukan resource Bundling, kalau tidak Prompt 40 SS7 membuat
    bundle buntu.
- Auto-receive log step non-bundle terakhir (Cutting) tetap seperti sekarang.
- Satu sesi scan = satu Line (semua bundle di batch). Validasi "satu artikel per batch"
  yang sudah ada tetap.

Tidak ada SP baru dan tidak ada perubahan skema (`bundles.resource_id` / `employee_id`
sudah ada).

## 3. Label — pakai SP yang sudah ada

`SIS_Bundle_ReprintLabel` (`sql/sp_Bundle_Manage.sql`) merakit payload dari data
**terkini**, jadi begitu `resource_id`/`employee_id` terisi, `resource_name` +
`employee_name` otomatis ikut. Dipanggil **dari API setelah Take sukses**, satu kali per
bundle (bukan di dalam SP Take, supaya result set tidak campur). SP itu tidak diubah.

Kalau enqueue label gagal, claim **tidak** di-rollback — kembalikan 200 dengan pesan
peringatan; operator bisa cetak ulang dari jalur reprint yang sudah ada.

## 4. Pilihan Line & penjahit — pakai endpoint yang sudah ada

- Line: `GET api/station/receiver-options?articleWorkflowId=<step Bundling artikel ini>`
  (`SIS_Station_ReceiverOptions` → resource divisi sesudah Bundling).
  Supaya client tahu step-nya, `SIS_CuttingBundle_Lookup` menambah dua kolom di hasil:
  `ArticleId` dan `BundlingWorkflowId` (nullable).
- Penjahit: `GET api/station/employees/{resourceId}` (`SIS_Employee_GetActiveByResource`),
  cascading setelah Line dipilih — pola sama dengan modal "Buat Bundle".

## 5. API

- `CuttingBundleTakeRequest` + `TargetResourceId`, `EmployeeId`, `PrintCopies` (default 1;
  0 = tidak cetak).
- `POST api/station/cutting-stock/take` meneruskan parameter baru, lalu — hanya kalau
  `TargetResourceId > 0` dan `PrintCopies >= 1` — loop `BundleService.ReprintAsync` per
  bundle.
- Respons: DTO baru `CuttingBundleClaimResultDto` (`TakenCount`, `TotalPcs`,
  `LabelsQueued`, `LabelError`). `CuttingBundleTakeResultDto` yang dipetakan EF dari SP
  **tidak** ditambahi properti (EF menuntut setiap properti ada sebagai kolom).

## 6. UI — `TerakarsaApp.Client/Shared/StationCuttingStockTab.razor`

- Setelah bundle pertama discan, muncul blok **Claim ke Line**: tombol pilihan Line
  (pola "Penjahit (Tim)" di modal Buat Bundle), `SearchableSelect` Penjahit (opsional,
  disabled sebelum Line dipilih), dan input **Jumlah Label** (default 1).
- Tombol utama jadi `Claim N bundle & cetak label`, disabled kalau operator **atau** Line
  belum dipilih (judul tombol menjelaskan yang mana).
- Kalau artikel itu tidak punya opsi Line sama sekali (workflow tanpa step sesudah
  Bundling), claim tidak mungkin: tombol kembali jadi `Ambil N bundle (tanpa claim)` dan
  memakai jalur Prompt 80, supaya tidak ada bundle yang mentok tidak bisa diambil.
- Pesan sukses menyebut jumlah bundle, pcs, Line, dan jumlah label yang dikirim ke printer.
- Daftar scan di-reset setelah sukses; pilihan Line dipertahankan supaya bisa claim
  beruntun ke Line yang sama.
- Tab IN/OUT/WIP, halaman cutting, dan modal bundle manual tidak disentuh.

## 7. Yang TIDAK boleh dilakukan

- Mengubah `SIS_Bundle_Manage`, `SIS_Bundle_ReprintLabel`, `SIS_WorkflowLog_Manage`,
  `SIS_Station_*`, atau builder TSPL mana pun.
- Membuat serial/bundle baru saat claim, atau menyentuh `needs_reprint` /
  `CUTTING_BUNDLE_LABEL`.
- Mewajibkan `@TargetResourceId` di SP (harus tetap bisa dipanggil tanpa claim).
- Menyentuh bundle yang sudah TAKEN sebelum fitur ini ada (log pending-nya tetap
  diselesaikan lewat tab Masuk seperti sekarang).

## 8. Verifikasi

- `dotnet build TerakarsaApp.slnx -v q` lolos.
- Bandingkan kolom per kolom log Bundling hasil claim vs log bundle manual (Prompt 25):
  hanya `resource_id` (pelaksana Bundling) dan `received_remark` yang wajar berbeda.
- Script SQL dilaporkan sebagai langkah manual di akhir.

## 9. Revisi saat pengerjaan (keputusan Ivander, 16 Okt 2026)

Dua aturan di atas diganti setelah uji pertama:

- **Claim WAJIB.** `@TargetResourceId` tidak lagi opsional — kosong = `RAISERROR
  'Line tujuan wajib dipilih.'`. Jalur "ambil tanpa claim" (log Bundling pending)
  dihapus dari SP dan UI, termasuk cabang cadangan di §6 untuk artikel tanpa step
  sesudah Bundling: artikel seperti itu sekarang memang tidak bisa mengambil bundle
  sampai workflow-nya diperbaiki.
- **Satu bundle sekali proses.** Daftar scan (pooling) di tab Stok Cutting dihapus:
  scan → kartu bundle tunggal → pilih Line → Claim → siap scan berikutnya. Pilihan
  Line & penjahit dipertahankan antar bundle. Endpoint tetap menerima daftar karena
  transaksi/applock SP memang per batch.

Juga ditemukan saat uji: `GET api/station/receiver-options` melempar 500
(`SIS_Station_ReceiverOptions` mengembalikan kolom `ResourceId`, `ResourceLookupDto`
menuntut `Id`) dan client menelannya jadi list kosong. Karena itu pilihan Line diambil
dari `resources/{divisionId}`, dan `SIS_CuttingBundle_Lookup` mengembalikan
`BundlingTargetDivisionId` (bukan `BundlingWorkflowId`). Bug receiver-options itu
sendiri BELUM diperbaiki — juga memengaruhi pemilih penerima di `BundleScanCard`.

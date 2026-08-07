# Prompt 49 — Pilih Pelaksana saat Kirim Hasil (Station Allow Resource Change)

## Prasyarat

Setelah Prompt 16 (`stations.default_resource_id` + `allow_resource_change`), Prompt 12d
(trio `updated_*`), dan Prompt 12e (tab "Dikirim" + revisi). Menyentuh
`SIS_WorkflowLog_Manage` — jangan dijalankan bersamaan dengan prompt lain yang menyentuh
SP tersebut.

## Konteks

Sekarang pelaksana selalu = operator sesi (dipilih sekali saat halaman stasiun dibuka).
Kenyataan lapangan: satu perangkat dipakai bergantian dan hasil satu bundle bisa
dikerjakan penjahit/line lain dari operator yang sedang login. Karena itu pemilihan
pelaksana dipindah ke **momen pencatatan**, bukan hanya momen login sesi.

Keputusan yang sudah dikunci:

1. Daftar pilihan = **semua resource aktif divisi stasiun** (endpoint
   `api/station/resources` yang sudah ada).
2. Pilihan bersifat **sekali pakai** — berlaku hanya untuk baris log itu. Setelah submit,
   form kembali ke operator sesi. Operator sesi & localStorage TIDAK berubah.
3. `allow_resource_change = 0` → pemilih tidak tampil (satu resource saja: teks + ikon
   gembok). Pemaksaan server Prompt 16 tetap berlaku.
4. Resource yang dipilih **meng-override** aturan "Bundle ini ditugaskan ke line lain."
   Beda line boleh; beda divisi tetap tidak boleh.

## 1. Cakupan aksi

Kena perubahan:
- `POST api/station/complete` — kirim hasil dari form Selesaikan (BundleScanCard).
- `PUT api/station/logs/{id}` — revisi kirim hasil di tab "Dikirim".

TIDAK kena (tetap pakai operator sesi apa adanya): receive, unreceive, cancel-handover,
scan, dan halaman login `/workflow-input` (Hasil Cutting).

## 2. SQL — `sql/sp_WorkflowLog_Manage.sql`

Tanpa perubahan skema. Parameter baru:

- `@AllowResourceOverride BIT = 0` (dipakai action CREATE).
- `@ResourceId INT = NULL` pada action **UPDATE** (pelaksana baris log; sebelumnya UPDATE
  tidak menyentuh `resource_id`).

### CREATE
- Cabang step ber-bundle pertama (`is_bundling = 0`, MIN sort_order): bila
  `@AllowResourceOverride = 1`, **lewati** pemeriksaan `bundles.resource_id` vs
  `@ResourceId` ('Bundle ini ditugaskan ke line lain.'). Bila 0 → perilaku lama persis.
- Validasi yang tetap wajib: `@ResourceId` harus resource hidup (`is_active = 1`,
  `deleted_at IS NULL`) milik divisi step ini → 'Pelaksana bukan milik divisi ini.'
- Aturan lain tidak berubah: prasyarat step sebelumnya diterima divisi ini, kuota qty
  (`@ConfirmExceed` / `@ConfirmShort`), urutan step, tolak step `is_bundling = 1`.

### UPDATE
- Bila `@ResourceId` diisi: validasi sama (hidup + milik `division_id` baris log), lalu
  `SET resource_id = @ResourceId`. Bila NULL → `resource_id` dibiarkan apa adanya.
- `@UpdatedByResourceId` tetap bermakna Prompt 12d: **siapa yang merevisi** (operator sesi),
  bukan pelaksana. Dua kolom ini boleh berbeda dan memang seharusnya bisa berbeda.
- Guard lama tetap: ditolak bila `received_at` sudah terisi atau `@ActingDivisionId` ≠
  `division_id` baris.

Beri komentar header SP yang menjelaskan pemisahan makna: `resource_id` = pelaksana
pekerjaan, `updated_by_resource_id` = operator yang merevisi.

## 3. API — `StationDeviceController` + `WorkflowLogService`

- `Complete`: `EffectiveResourceId(request.ResourceId)` tetap dipakai (stasiun terkunci →
  dipaksa `default_resource_id`). Kirim `AllowResourceOverride = CurrentStation.AllowResourceChange`
  ke `@AllowResourceOverride`.
- `UpdateLog`: tambah field `PelaksanaResourceId` (nullable) di `StationLogUpdateRequest`.
  - `ResourceId` yang sudah ada tetap = operator sesi → `@UpdatedByResourceId` (tidak berubah).
  - `PelaksanaResourceId` → `@ResourceId`. Bila stasiun terkunci, abaikan nilai dari request
    dan paksa `default_resource_id` (lewat `EffectiveResourceId`).
- `WorkflowLogCreateInput` / `WorkflowLogUpdateInput`: tambah properti yang sesuai.
- Pesan error SP diteruskan apa adanya seperti pola yang sudah ada.

## 4. Client

### Komponen baru `TerakarsaApp.Client/Shared/ResourcePickerCards.razor`
Parameter: `Resources` (List<ResourceLookupDto>), `SelectedId` (int?), `SelectedIdChanged`,
`Disabled` (bool), `Label` (string, default "Pelaksana").
Render grid tombol besar mengikuti pola pemilih operator yang sudah ada di
`StationDevice.razor` (`col-6 col-md-4`, `btn-lg w-100 py-4`): yang terpilih `btn-primary`,
sisanya `btn-outline-primary`. Sentuh-friendly, tanpa dropdown.

### `BundleScanCard.razor` — form Selesaikan
- Parameter baru: `Resources` (dioper dari pemanggil, jangan fetch sendiri),
  `AllowResourceChange` (bool), `SessionResourceId`, `SessionResourceName`.
- Di atas input qty: section "Pelaksana".
  - `AllowResourceChange = true` → `ResourcePickerCards`, default terpilih = operator sesi.
  - `AllowResourceChange = false` → teks nama resource + ikon `fe fe-lock`, tanpa card.
- Bila pilihan ≠ operator sesi: badge kecil pengingat di dekat tombol simpan
  ("Pelaksana: {nama} — bukan operator sesi").
- `StationCompleteRequest.ResourceId` diisi pilihan card (bukan operator sesi).
- Setelah submit sukses → pilihan reset ke operator sesi.

### `StationDevice.razor` — modal Revisi (tab "Dikirim")
- Section "Pelaksana" yang sama. **Default terpilih = `resource_id` baris log** (pelaksana
  tercatat), bukan operator sesi.
- Kirim `PelaksanaResourceId` = pilihan card, `ResourceId` = operator sesi.
- `operators` yang sudah dimuat halaman dipakai ulang dan dioper ke `BundleScanCard` —
  jangan panggil `api/station/resources` per scan.
- Pada halaman publik `/b/{serial}` (ReadOnly), pemilih tidak tampil sama sekali.

## 5. Tampilan jejak

- Kartu tab "Dikirim" dan "Baru Diterima": tampilkan nama pelaksana (`ResourceName`).
  Cek `SIS_Station_PendingHandover` / `SIS_Station_RecentReceived` — bila kolom belum
  dikembalikan, tambahkan (LEFT JOIN `resources`).
- Riwayat/log viewer yang sudah ada tidak perlu diubah — `resource_id` tetap satu-satunya
  sumber pelaksana.

## Aturan tetap berlaku

Soft delete + `deleted_at IS NULL`, prefix SP `SIS_`, pola `@Action` untuk mutasi, UI
bahasa Indonesia, tanpa library baru.

## Urutan deploy

1. `sql/sp_WorkflowLog_Manage.sql`
2. `sql/sp_Station_Operations.sql` (hanya bila SP read ikut berubah di bagian 5)
3. Deploy API + Client

## Yang TIDAK boleh dilakukan

- Jangan menambah tabel atau kolom baru (termasuk whitelist resource per stasiun).
- Jangan mengubah operator sesi / localStorage saat memilih pelaksana di form.
- Jangan menampilkan resource divisi lain, atau resource nonaktif.
- Jangan memasang pemilih ini di Terima / Batal Terima / Batal Serah / Hasil Cutting.
- Jangan melonggarkan validasi divisi, prasyarat step sebelumnya, atau aturan kuota qty —
  yang di-override hanya penugasan line pada step ber-bundle pertama.

Setelah selesai: daftar file dibuat/diubah + script SQL yang harus dijalankan manual.

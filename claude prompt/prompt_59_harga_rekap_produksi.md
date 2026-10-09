# Prompt 59 — Harga Workflow Step, Rekap Produksi Station & Output Non-PO

## Konteks

Prompt 55–58 sudah jalan: lock per baris log (`article_workflow_logs.lock_id` → `workflow_locks` yang menyimpan periode), `payroll_periods` (kode `YYYY-Pnn`, cut-off Sabtu 10:00, kolom `finalized_at`), tab OUT station dengan lock, dan tab **Settlement** (print kartu kerja). Tab "Rekap Produksi" lama di station sudah diganti Settlement.

Prompt ini menambah tiga hal:

1. **Harga per workflow step**: diisi di step template, disalin ke artikel saat APPLY, dan bisa diubah per artikel.
2. **Tab baru "Rekap Produksi" di station**: matriks output resource per periode gajian, dengan dua mode (Output / Terima), checkbox Price, dan export Excel.
3. **Output non-PO**: pekerjaan di luar PO/bundle yang diinput PIC di station. Isinya qty, harga per pcs, dan keterangan. **Masuk upah resource.**

Mockup yang sudah disetujui: **`claude prompt/prompt_59_mockup.html`** (buka di browser). Isinya tab Rekap Produksi (toggle Output/Terima, checkbox Price), modal input non-PO (klik "+ Output Non-PO"), dan modal detail non-PO (klik baris "Di luar PO"). Ikuti layout, urutan kolom, label, dan perilaku di mockup. Implementasi tetap memakai Bootstrap + pola komponen `StationDevice.razor`, jangan menyalin CSS mockup apa adanya. Data di mockup hanya contoh.

### Aturan bisnis (sudah diputuskan, jangan diubah)

- Qty yang dihitung = `qty_ok + qty_reject_fabric` (reject bahan). Kategori reject lain tidak dihitung.
- Harga **selalu mengikuti `article_workflows.unit_price` saat ini**, tanpa snapshot ke log. Pencatatan nilai per periode menyusul lewat settlement payroll di prompt lain.
- Rekap dikelompokkan per **resource sesi station** (bukan per karyawan), dengan baris per **step artikel** (`article_workflow_id`). Saat ini satu artikel praktis hanya punya satu step per divisi, tapi grouping tetap per step.
- Non-PO: tanpa jenis, cukup tanggal + jam, qty, harga/pcs, dan keterangan. Periode ditentukan dari tanggal + jam (cut-off Sabtu 10:00) dan disimpan. Edit/hapus bebas tanpa lock.
- Tab Rekap Produksi hanya bisa dibuka kalau station punya resource sesi (operator terpilih). Kalau belum ada, tab tampil disabled dengan teks "Pilih operator dulu".

---

## 1. Skema SQL

File baru: `sql/prompt_59_harga_rekap_nonpo.sql` (idempotent). `sql/create_tables_tmos_final.sql` ikut diperbarui.

### a. Harga step

```sql
-- workflow_template_steps.unit_price  decimal(19,4) not null default 0
-- article_workflows.unit_price        decimal(19,4) not null default 0
```

Tambah dengan `IF NOT EXISTS (SELECT 1 FROM sys.columns ...)`, `ALTER TABLE ... ADD ... CONSTRAINT DF_... DEFAULT 0`. Data lama otomatis 0.

### b. Tabel `non_po_outputs`

| kolom | tipe | catatan |
|---|---|---|
| non_po_output_id | int identity PK | |
| resource_id | int not null FK resources | resource sesi station |
| division_id | int not null FK divisions | divisi resource |
| payroll_period_id | int not null FK payroll_periods | dihitung SP dari `output_at` |
| output_at | datetime2 not null | tanggal + jam pekerjaan |
| qty | int not null | > 0 |
| unit_price | decimal(19,4) not null | ≥ 0 |
| remark | nvarchar(500) not null | wajib diisi |
| created_at / created_by / updated_at / updated_by / deleted_at / deleted_by | standar | `created_by` = user `station_system` |

Index: `(resource_id, payroll_period_id) WHERE deleted_at IS NULL`.

---

## 2. Stored Procedures

### a. `SIS_WorkflowTemplate_Manage` (ubah)

Ikuti pola `print_kupon` (Prompt 41): JSON `@Steps` membawa `UnitPrice` (decimal). Simpan ke `workflow_template_steps.unit_price` di CREATE dan UPDATE. Tolak nilai negatif (RAISERROR, pesan Indonesia).

### b. `SIS_ArticleWorkflow_Manage` (ubah)

- **APPLY**: salin `unit_price` dari step template ke `article_workflows`. Step Bundling implisit = 0.
- **SAVE**: JSON step membawa `UnitPrice`, update `article_workflows.unit_price`. Tolak negatif. Perubahan harga **tidak** dibatasi oleh status log/lock.
- Perubahan harga di template **tidak** merambat ke artikel yang sudah ada (konsisten dengan aturan template yang sekarang).

### c. `SIS_ArticleWorkflow_Select` / `SIS_WorkflowTemplate_Select` (ubah)

Tambah kolom `unit_price` di result set.

### d. `SIS_NonPoOutput_Manage` (baru) — `@Action` CREATE / UPDATE / DELETE

Parameter: `@Action`, `@NonPoOutputId`, `@ResourceId`, `@OutputAt`, `@Qty`, `@UnitPrice`, `@Remark`, `@UserId`.

- `division_id` diambil dari resource.
- `payroll_period_id` dicari dari `@OutputAt` memakai rentang `payroll_periods`, aturan cut-off sama dengan lock. Dihitung ulang setiap UPDATE.
- Guard:
  - qty > 0
  - harga ≥ 0
  - keterangan wajib
  - `@OutputAt` tidak boleh di masa depan
  - periode tujuan (dan periode lama saat UPDATE/DELETE) belum `finalized_at`
  - UPDATE/DELETE hanya untuk baris milik `@ResourceId` yang sama
- DELETE = soft delete.

### e. `SIS_NonPoOutput_List` (baru)

Parameter: `@ResourceId`, `@PayrollPeriodId`. Mengembalikan baris non-PO, diurutkan `output_at`. Kolomnya: id, output_at, qty, unit_price, nilai (qty × unit_price), remark, created_at.

### f. `SIS_Station_RekapProduksi` (baru, read)

Parameter: `@ResourceId`, `@PayrollPeriodId`, `@Mode` (`'OUTPUT'` / `'TERIMA'`).

Result set 1 — baris PO, format panjang (pivot dilakukan di client):

`article_workflow_id, article_id, article_name, style, color, step_name, project_name, no_po, tanggal (date), qty, unit_price`

- **OUTPUT**:
  - Log dengan `resource_id = @ResourceId`, `lock_id IS NOT NULL`, dan periode di `workflow_locks` = `@PayrollPeriodId`.
  - `tanggal` = `CAST(created_at AS date)`. Tanggal bisa berada di luar rentang periode, karena PIC bebas memilih periode saat lock.
  - `qty` = SUM(`qty_ok + qty_reject_fabric`).
  - `unit_price` = `article_workflows.unit_price` saat ini.
- **TERIMA**:
  - Log dengan `received_by_resource_id = @ResourceId` dan `received_at` di dalam rentang waktu periode (start ≤ received_at < end). Tanpa syarat lock.
  - `tanggal` = `CAST(received_at AS date)`.
  - `unit_price` = harga step log tersebut, yaitu step pengirim.
- Hanya `deleted_at IS NULL` dan `log_type = 'NORMAL'`. Pertimbangkan juga ADJUSTMENT kalau ia mengubah total qty_ok/reject_fabric; ikuti cara laporan lain menghitung.

Result set 2 (hanya OUTPUT): `unlocked_count` = jumlah log resource ini yang `lock_id IS NULL`, untuk chip "n baris belum lock".

Result set 3 (hanya OUTPUT): agregat non-PO per tanggal (`CAST(output_at AS date)`, SUM qty, SUM qty × unit_price) untuk resource + periode.

Result set 4: info periode (kode, start, end) untuk header kolom tanggal.

---

## 3. API (station token, pola `StationDeviceController`)

Semua endpoint memakai `EffectiveResourceId(...)`. Tolak dengan 400 "Operator wajib dipilih." kalau resource tidak ada.

- `GET  station/rekap-produksi?resourceId&payrollPeriodId&mode` → result set di atas.
- `GET  station/rekap-produksi/export?resourceId&payrollPeriodId&mode` → file `.xlsx`.
- `GET  station/payroll-periods` → **pakai endpoint/SP periode yang sudah ada dari Prompt 56** (modal lock). Jangan buat duplikat.
- `GET  station/non-po?resourceId&payrollPeriodId`
- `POST station/non-po`, `PUT station/non-po/{id}`, `DELETE station/non-po/{id}`

DTO di `TerakarsaApp.Shared` (file baru `RekapProduksiDtos.cs`).

### Export Excel (ClosedXML)

Tambah NuGet `ClosedXML` ke `TerakarsaApp.API`.

- Satu sheet, isinya sama dengan matriks di layar. **Selalu** menyertakan kolom Harga dan Nilai, tidak tergantung checkbox.
- Urutan kolom: Artikel | Step | PO | kolom tanggal (sama dengan layar, termasuk kolom luar periode) | Total Qty | Harga | Nilai.
- Baris Total PO memakai formula SUM.
- Baris "Di luar PO" ada di paling bawah: qty per tanggal, Harga kosong, Nilai = SUM nilai catatan.
- Header di atas tabel: nama resource, divisi, kode periode + rentang, mode.
- Nama file: `RekapProduksi_{resource}_{kodePeriode}_{Output|Terima}.xlsx`.

---

## 4. UI

### a. Harga di Workflow Template (`WorkflowTemplate.razor`)

Kolom input **Harga (Rp)** per step, sejajar checkbox Cetak Kupon. Numerik, default 0.

### b. Harga di workflow artikel (`ArticleEdit.razor`)

Kolom input **Harga (Rp)** per step artikel, bisa diedit. Step Bundling implisit tidak menampilkan input harga.

### c. Tab "Rekap Produksi" di `StationDevice.razor`

Tab baru setelah Settlement: **IN · WIP · OUT · Settlement · Rekap Produksi**. Kalau tidak ada resource sesi, tab disabled dengan teks "Pilih operator dulu".

Toolbar:
- Pemilih periode dengan tombol ‹ ›. Label: kode periode + rentang ("Sab 26 Sep 10:00 – Sab 3 Okt 10:00"). Default = periode berjalan.
- Segmented toggle **Output | Terima** (default Output).
- Checkbox **Price**, hanya tampil di mode Output (default tidak dicentang).
- Tombol **+ Output Non-PO**, hanya di mode Output.
- Tombol **Export Excel**.

Teks info:
- Output: "Output yang sudah lock ke {periode}. Kolom = tanggal output. Angka = OK + reject bahan." Ditambah chip merah "n baris belum lock, tidak dihitung" kalau `unlocked_count > 0`.
- Terima: "Semua penerimaan {rentang}, tanpa syarat lock. Kolom = tanggal terima. Angka = OK + reject bahan."

Matriks (div grid, kolom pertama sticky, scroll horizontal):
- Kolom: Artikel (nama artikel, di bawahnya step · PO) | satu kolom per tanggal dalam rentang periode | **Total Qty**.
- Sabtu awal diberi label "mulai 10:00", Sabtu akhir "s/d 10:00".
- Tanggal di luar rentang (hanya terjadi di Output) ditambahkan sebagai kolom ekstra dengan warna kuning muda dan label "luar periode", diurutkan sesuai tanggal.
- Nilai 0 ditampilkan "–" abu-abu.
- Baris **Total PO** (keterangan kecil "dasar upah").
- Mode Output: pemisah "DI LUAR PO · masuk upah, harga diisi PIC", lalu satu baris **"Di luar PO"** (qty per tanggal). Klik baris → modal detail.
- Price dicentang: tambah kolom **Harga** dan **Nilai (Rp)** setelah Total Qty.
  - Baris artikel: Nilai = Total Qty × Harga.
  - Baris Total PO: hanya Nilai (SUM).
  - Baris Di luar PO: Harga "–", Nilai = SUM nilai catatan.

### d. Modal "Output Non-PO" (input & edit)

- Field: **Tanggal + Jam** (default sekarang), **Qty (pcs)**, **Harga / pcs (Rp)**, **Keterangan** (wajib).
- Di bawah tanggal tampil "Masuk periode {kode} ({rentang})", dihitung ulang saat tanggal/jam berubah.
- Kotak **Nilai upah** = qty × harga, live.
- Tombol Batal / Simpan. Error dari SP ditampilkan di modal.

### e. Modal detail "Di luar PO · {periode}"

- Header: jumlah catatan · total pcs · total Rp.
- Per baris: hari + tanggal, keterangan, "qty pcs × Rp harga · diinput {waktu}", nilai, tombol Edit (buka modal d) dan Hapus (konfirmasi).
- Catatan kaki: "Edit dan hapus bebas, tanpa lock. Ubah tanggal, periode ikut berubah."

---

## 5. Verifikasi

1. Template: isi harga step → APPLY ke artikel baru → harga tersalin. Ubah harga di artikel → template tidak berubah, dan sebaliknya.
2. Harga negatif ditolak SP (template & artikel).
3. Resource A, periode P40: log terkunci ke P40 muncul di mode Output. Log yang belum lock tidak muncul dan terhitung di chip.
4. Log tanggal Jum 25/9 yang di-lock ke P40 → muncul kolom ekstra "luar periode".
5. Log Sab 26/9 jam 09:00 dan jam 11:00 (keduanya lock sesuai periodenya) → masing-masing muncul di P39 dan P40.
6. Mode Terima: penerimaan dalam rentang periode muncul walau log belum lock.
7. Qty = qty_ok + qty_reject_fabric. Reject sablon/jahit/rework/hilang tidak ikut.
8. Non-PO: input Sabtu 09:59 → periode sebelumnya, Sabtu 10:00 → periode berikutnya. Edit tanggal → pindah periode. Hapus → hilang dari matriks.
9. Non-PO ke periode `finalized_at` ditolak.
10. Checkbox Price: kolom Harga/Nilai muncul dan hitungannya benar. Excel selalu memuat Harga & Nilai di kedua mode, Total PO pakai formula.
11. Station tanpa operator: tab disabled, endpoint menolak.

---

## Urutan deploy

1. Pastikan Prompt 55–58 sudah terpasang.
2. Jalankan `sql/prompt_59_harga_rekap_nonpo.sql` (kolom + tabel).
3. Jalankan SP yang diubah: `sp_WorkflowTemplate_Manage.sql`, `sp_WorkflowTemplate_Select.sql`, `sp_ArticleWorkflow_Manage.sql`, `sp_ArticleWorkflow_Select.sql`.
4. Jalankan SP baru: `sp_NonPoOutput_Manage.sql`, `sp_NonPoOutput_List.sql`, `sp_Station_RekapProduksi.sql`.
5. Deploy API + Client.

---

## Yang TIDAK boleh dilakukan

- Jangan menyalin harga ke `article_workflow_logs` atau `workflow_lock_items` (belum ada snapshot harga).
- Jangan mengubah logika lock/unlock, SP `SIS_WorkflowLog_Manage`, `SIS_Bundle_Manage`, atau tab IN/WIP/OUT/Settlement.
- Jangan mengubah Report Produksi admin, Line Detail, kupon borongan, atau rekap struk.
- Jangan membuat kolom "jenis" untuk non-PO.
- Jangan membuat lock/approval untuk non-PO.
- Jangan membuat SP/endpoint periode baru kalau yang dari Prompt 56 sudah ada.
- Jangan refactor SP/kode lama di luar cakupan.

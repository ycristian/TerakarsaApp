# Prompt 39 — Resource Buang Benang per Line + Mapping Pasangan (counterpart)

## Prasyarat

Dijalankan SETELAH Prompt 33 (pemisahan Buang Benang) dan Prompt 34 (auto-terima).
Menyentuh `SIS_Resource_Manage`, `SIS_WorkflowLog_Manage` (jalur auto-terima), dan
`SIS_Bundle_ScanInfo` — jangan dijalankan paralel dengan prompt lain yang menyentuh SP ini.

## Konteks

Divisi Buang Benang saat ini hanya punya 1 resource, sedangkan pekerjaannya sebenarnya
mengikuti line jahit 1:1 (Line A1 → Trim A1, dst.). Akibatnya laporan produksi dan WIP
divisi Buang Benang tidak bisa dipecah per line.

Ada dua masalah yang harus dibereskan bersamaan:

1. **Data lama**: seluruh log trim menumpuk di satu resource, harus dipecah ke resource
   trim baru berdasarkan line asal bundle (`bundles.resource_id`).
2. **Data baru**: auto-terima (Prompt 34) mengisi `received_by_resource_id` dengan resource
   **pengirim** (Line A1). Kalau tidak diubah, hasil migrasi jadi campur: baris lama berisi
   `Trim A1`, baris baru berisi `Line A1`.

Solusinya: kolom pemetaan permanen `resources.counterpart_resource_id` (resource pasangan
di divisi lanjutan), dipakai oleh auto-terima dan oleh saran pelaksana di station.

## Keputusan yang sudah diambil

| Hal | Keputusan |
|---|---|
| Sumber line asal bundle | `bundles.resource_id` |
| Kolom log yang dimigrasi | `resource_id`, `received_by_resource_id`, `updated_by_resource_id` |
| Resource trim lama | dinonaktifkan (`is_active = 0`), TIDAK dihapus |
| Auto-terima Buang Benang | isi `received_by_resource_id` dengan resource pasangan (Trim A1), fallback resource pengirim bila pasangan kosong |
| Penyimpanan mapping | kolom baru `resources.counterpart_resource_id` |
| Pelaksana baris trim di station | otomatis dari line bundle yang di-scan, masih bisa diubah operator |
| Penamaan resource trim | nama line dengan kata "Line" diganti "Trim" (`Line A1` → `Trim A1`) |

## 1. Skema — `resources.counterpart_resource_id`

### a. `sql/alter_39_resource_counterpart.sql` (idempotent, dijalankan manual)

```sql
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('resources') AND name = 'counterpart_resource_id')
BEGIN
    ALTER TABLE resources ADD counterpart_resource_id int null
        CONSTRAINT FK_resources_counterpart FOREIGN KEY REFERENCES resources(resource_id);
END
GO
```

### b. `sql/create_tables_tmos_final.sql`

Tambah kolom yang sama pada definisi `resources`, dengan komentar:
"resource pasangan di divisi lanjutan (mis. Line A1 di Sewing → Trim A1 di Buang Benang).
Dipakai auto-terima untuk mengisi received_by_resource_id dengan resource divisi penerima,
dan sebagai saran pelaksana di station. Satu arah, opsional."

### c. Validasi di `SIS_Resource_Manage` (CREATE & UPDATE)

Tambah parameter `@CounterpartResourceId INT = NULL`. Bila diisi:
- harus resource hidup (`deleted_at IS NULL`) → 'Resource pasangan tidak ditemukan.'
- tidak boleh sama dengan resource itu sendiri → 'Resource pasangan tidak boleh diri sendiri.'
- divisinya harus berbeda dengan `@DivisionId` → 'Resource pasangan harus dari divisi lain.'

Parameter bersifat opsional dan backward compatible (default NULL = tidak diubah pada UPDATE
hanya bila pemanggil memang tidak mengirimnya — cukup pakai pola `ISNULL(@CounterpartResourceId, counterpart_resource_id)`?
**Tidak** — pakai nilai apa adanya, karena user harus bisa mengosongkan pasangan lewat UI).

## 2. Select SP, API, dan halaman Master Resource

- `sp_Resource_Select.sql` (`SIS_Resource_GetAll`, `SIS_Resource_GetById`): kembalikan
  `counterpart_resource_id` + nama resource pasangan (LEFT JOIN ke `resources`, filter
  `deleted_at IS NULL` **di klausa ON**).
- `SIS_Resource_GetActiveByDivision` tidak berubah.
- Model Shared + service + controller resource: teruskan `CounterpartResourceId`.
- Halaman Master Resource:
  - Form: dropdown "Resource Pasangan (opsional)" berisi resource aktif **di luar divisi
    yang dipilih**, dengan pilihan kosong "- Tidak ada -". Kalau divisi diganti, pilihan
    di-reset bila jadi tidak valid.
  - List: kolom "Pasangan" (nama resource pasangan, "-" bila kosong).

## 3. Auto-terima memakai resource pasangan

Di jalur auto-terima yang dibuat Prompt 34 (`SIS_WorkflowLog_Manage`, saat baris baru
langsung ter-receive karena step tujuan `auto_receive = 1`):

- `received_by_resource_id` = `ISNULL(counterpart_resource_id milik resource pengirim, resource pengirim)`.
  Resource pengirim = `resource_id` baris yang dibuat.
- Fallback wajib ada: kalau resource pengirim NULL atau tidak punya pasangan, perilaku lama
  dipertahankan (isi resource pengirim / NULL) — auto-terima TIDAK boleh gagal karena mapping kosong.
- Tambahan penjaga: bila resource pasangan ternyata bukan milik `target_division_id`, abaikan
  pasangan dan pakai perilaku lama.
- Jangan mengubah aturan auto-terima lainnya (kapan aktif, timestamp, remark).

## 4. Station — saran pelaksana dari line bundle

- `sp_Bundle_ScanInfo.sql` (`SIS_Bundle_ScanInfo`): tambah kolom hasil
  `SuggestedResourceId` = `counterpart_resource_id` dari `bundles.resource_id`, **hanya bila**
  resource pasangan itu hidup, aktif, dan `division_id = @DivisionId` (divisi station).
  NULL bila tidak memenuhi.
- Client (`BundleScanCard` / panel scan di `/station`): bila `SuggestedResourceId` terisi dan
  station tidak terkunci (`allow_resource_change = 1`), form catat hasil memakai resource itu
  sebagai nilai awal — operator tetap bisa menggantinya. Bila NULL, pakai perilaku sekarang
  (resource sesi aktif).
- Station terkunci (`allow_resource_change = 0`) tetap dipaksa ke `default_resource_id` seperti
  Prompt 16 — saran diabaikan.
- Pemaksaan sisi server tidak berubah: nilai yang dipakai tetap yang dikirim client (kecuali
  mode terkunci). Saran murni bantuan UI.

## 5. Script seed & migrasi data — `sql/seed_39_trim_per_line.sql`

Dijalankan manual SETELAH `alter_39`. Idempotent, satu transaksi, dan mencetak laporan.
Tidak boleh ada ID yang di-hardcode.

Isi script, berurutan:

1. **Variabel konfigurasi** di atas: `@TrimDivisionName = 'Buang Benang'`, `@LinePrefix = 'Line '`,
   `@TrimPrefix = 'Trim '`, `@UserId = 1`. Ambil `@TrimDivisionId` dari `divisions`
   (`deleted_at IS NULL`); bila tidak ketemu → RAISERROR + rollback.

2. **Kumpulkan line sumber** ke table variable `@Lines`: resource hidup + aktif yang namanya
   `LIKE @LinePrefix + '%'` dan divisinya bukan divisi trim. Nama trim = `@TrimPrefix` +
   sisa nama setelah prefix (`Line A1` → `Trim A1`).

3. **Insert resource trim** yang belum ada: `division_id = @TrimDivisionId`,
   `resource_type_id` disalin dari line-nya, `is_active = 1`, `created_by = @UserId`.
   Guard `NOT EXISTS` berdasarkan (divisi trim, nama, `deleted_at IS NULL`).

4. **Isi counterpart**: `resources.counterpart_resource_id` pada baris line → resource trim
   pasangannya. Hanya update baris yang nilainya belum sesuai. Arah satu saja (line → trim).

5. **Identifikasi resource trim lama** ke `@OldTrimIds`: resource hidup di divisi trim yang
   namanya TIDAK ada di daftar nama trim baru. (Cara ini tahan bila ternyata ada lebih dari satu.)

6. **Migrasi log** — satu UPDATE atas `article_workflow_logs`, JOIN `bundles` →
   `resources ln ON ln.resource_id = b.resource_id`, syarat `ln.counterpart_resource_id IS NOT NULL`:
   ganti nilai pada `resource_id`, `received_by_resource_id`, `updated_by_resource_id`
   **hanya bila** nilainya ada di `@OldTrimIds`, jadi `ln.counterpart_resource_id`.
   Kolom lain tidak disentuh. Baris soft-deleted IKUT dimigrasi supaya riwayat konsisten.
   Karena filter update selalu `IN @OldTrimIds`, script aman dijalankan berulang.

7. **Laporan sisa tidak termapping**: SELECT jumlah + daftar baris yang masih memakai
   `@OldTrimIds` (bundle_id, bundle_no/serial, alasan: bundle NULL / bundle tanpa
   `resource_id` / line tanpa counterpart). Baris ini sengaja dibiarkan, tidak ditebak.

8. **Nonaktifkan resource trim lama**: `is_active = 0` untuk `@OldTrimIds` yang masih aktif
   (`deleted_at` tetap NULL — jangan dihapus, masih dirujuk log yang tidak termapping).

9. **Station divisi Buang Benang**: `default_resource_id = NULL` dan `allow_resource_change = 1`
   untuk semua station hidup di divisi trim (karena resource bawaannya kini nonaktif).

## Urutan deploy

1. `sql/alter_39_resource_counterpart.sql`
2. SP: `sp_Resource_Manage.sql`, `sp_Resource_Select.sql`, `sp_WorkflowLog_Manage.sql`, `sp_Bundle_ScanInfo.sql`
3. `sql/seed_39_trim_per_line.sql` + periksa laporan sisa tidak termapping
4. Deploy API + Client

## Yang TIDAK boleh dilakukan

- Jangan hardcode `resource_id`, `division_id`, atau `station_id` di script mana pun.
- Jangan menghapus (soft delete) resource trim lama.
- Jangan menebak line untuk bundle yang `resource_id`-nya kosong — biarkan di resource lama
  dan laporkan.
- Jangan mengubah aturan validasi "Bundle ini ditugaskan ke line lain" (itu milik step
  ber-bundle pertama, bukan step Buang Benang).
- Jangan membuat auto-terima gagal/error saat pasangan kosong — wajib fallback.
- Jangan mengubah nama/kode divisi, step workflow, atau `auto_receive` milik Prompt 33/34.
- Jangan membuat mapping dua arah otomatis (trim → line) di script ini.

## Verifikasi

1. `dotnet build` sukses.
2. Setelah script dijalankan:
   - Divisi Buang Benang punya 8 resource aktif (`Trim A1`…`Trim B3`) + 1 resource lama nonaktif.
   - `SELECT resource_name, counterpart_resource_id` pada line jahit → semuanya terisi, 1:1.
   - Laporan produksi & WIP divisi Buang Benang periode lama sudah terpecah per Trim, angka
     total sama dengan sebelum migrasi.
   - Jalankan ulang script → 0 baris berubah.
3. Skenario manual:
   - Master Resource: set/kosongkan resource pasangan, pilih pasangan sedivisi → ditolak.
   - Bundle line A2 diserahkan dari Sew+QC → auto-terima mengisi penerima `Trim A2`, bukan `Line A2`.
   - Scan bundle line B1 di station Buang Benang → pelaksana otomatis `Trim B1`, bisa diganti
     manual ke Trim lain dan tersimpan sesuai pilihan.
   - Line tanpa pasangan (mis. line baru) diserahkan → auto-terima tetap berhasil dengan
     perilaku lama.
4. Di akhir: daftar file dibuat/diubah + daftar script SQL yang harus dijalankan manual.

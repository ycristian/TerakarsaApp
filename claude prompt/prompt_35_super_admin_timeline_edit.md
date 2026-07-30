# Prompt 35 — Edit Timeline & Info Bundle oleh Super Admin (halaman /b/{serial})

## Konteks

Halaman detail bundle `/b/{serial}` menampilkan info bundle + timeline log per step. Super Admin perlu bisa mengoreksi data langsung dari halaman ini:

1. **Edit log per baris timeline**: qty (OK + semua kolom reject + lost sesuai skema terkini), pelaksana (resource), remark.
2. **Edit info bundle**: qty, line/penjahit (line → employee cascading, pola Prompt 32), size.

**Hanya user login web dengan modul `SUPER_ADMIN`** yang melihat & memakai tombol edit. Operator station TIDAK mendapat fitur ini — jangan sentuh alur station.

## Aturan validasi qty (inti fitur — hard block, berlaku untuk semua termasuk Super Admin)

Prinsip: qty step manapun tidak boleh lebih kecil dari total yang sudah tercatat di step setelahnya, supaya downstream tidak pernah melebihi upstream. Untuk menurunkan qty, user harus edit mundur mulai dari step paling akhir.

- **Edit log step N** (bundle X): total baru `SUM(qty_ok)` semua baris hidup step N bundle X (baris yang diedit dihitung pakai nilai baru) **harus ≥** `SUM(qty_ok + semua reject + lost)` semua baris hidup step ber-bundle berikutnya (sort_order terkecil > N, requires_bundle = 1) untuk bundle yang sama. Jika step N adalah step ber-bundle terakhir → tidak ada pembanding, lolos.
  - Ditolak → RAISERROR dengan pesan jelas yang menyebut angka dan menyuruh edit step berikutnya dulu, mis. `'Qty step ini (48) tidak boleh lebih kecil dari total step berikutnya (55). Edit step berikutnya terlebih dahulu.'`
- **Edit qty bundle**: qty bundle mengalir ke log step Bundling (qty_ok log Bundling = qty bundle, Prompt 17) — update qty bundle harus SEKALIGUS meng-update qty_ok baris log Bundling hidup bundle itu dalam satu transaksi, dan qty baru **harus ≥** total (`qty_ok + reject + lost`) step ber-bundle setelah Bundling untuk bundle itu. Pesan error pola sama.
- **Validasi arah atas** (total step N tidak melebihi qty masuk dari step N−1 / qty bundle): pakai logika kuota yang sudah ada (pola `QTY_EXCEED|` + konfirmasi `@ConfirmExceed`). Jangan ubah perilakunya — hanya arah bawah yang hard block tanpa override.

## 1. Stored Procedure — `sql/sp_SuperAdmin_Manage.sql`

Sesuai prinsip bypass isolation (Prompt 29): semua logika edit ini masuk `SIS_SuperAdmin_Manage`. **Jangan ubah guard produksi di `SIS_WorkflowLog_Manage` maupun `SIS_Bundle_Manage`.**

Periksa dulu action yang sudah ada di SP ini; kalau sudah ada action serupa (edit log / edit bundle), perluas dan tambahkan validasi di atas — jangan buat duplikat. Kalau belum ada, tambah:

- **`EDIT_LOG`** — param: `@Id` (workflow_log_id), qty fields, `@ResourceId`, `@Remark`, `@ConfirmExceed`, `@UserId`.
  - Baris hidup harus ada; bundle harus punya bundle_id (baris ber-bundle).
  - Validasi arah bawah (hard block) + arah atas (pola QTY_EXCEED) seperti di atas.
  - Update kolom qty/resource/remark + `updated_at`, `updated_by`. Field lain tidak disentuh (waktu, received_*, target_division tetap).
- **`EDIT_BUNDLE`** — param: `@Id` (bundle_id), `@Qty`, `@ResourceId` (line), `@EmployeeId`, `@ArticleSizeId`, `@ConfirmExceed`, `@UserId`.
  - Bundle hidup harus ada; `@ArticleSizeId` harus milik artikel bundle & hidup; validasi line–employee mengikuti pola Prompt 32.
  - Satu transaksi: update bundles (qty, resource_id, employee_id, article_size_id) + update qty_ok log Bundling hidup bundle ini.
  - Validasi qty bundle seperti di atas. **Tidak ada** blokir "sudah COMPLETED" — ini jalur super admin.
  - Serial & bundle_no tidak pernah berubah.

## 2. API

Controller super admin yang sudah ada (Prompt 29), `[Authorize] + RequireModule("SUPER_ADMIN")`:
- `PUT api/superadmin/logs/{id}` → EDIT_LOG
- `PUT api/superadmin/bundles/{id}` → EDIT_BUNDLE
- `@UserId` dari JWT. Error SP diteruskan sebagai pesan jelas (termasuk prefix `QTY_EXCEED|` untuk pola konfirmasi client).
- Endpoint GET pendukung untuk dropdown modal (resource per divisi, article_sizes artikel, line + employees) — pakai endpoint existing kalau sudah ada; jangan buat baru tanpa perlu.

## 3. Blazor — halaman `/b/{serial}`

- Deteksi: kalau user sedang login web (JWT) dan punya modul `SUPER_ADMIN`, tampilkan:
  - Tombol **Edit** kecil di setiap baris timeline.
  - Tombol **Edit Bundle** di area header bundle.
  - Tanpa login super admin, tampilan halaman TIDAK berubah sama sekali.
- **Modal Edit Log**: field qty (OK/reject/lost), dropdown Pelaksana (resource hidup divisi step tsb), Remark. Baris info: `Masuk: X • Batas bawah (total step berikutnya): Y`. Submit → pesan `QTY_EXCEED|` memicu dialog konfirmasi (pola existing); error hard block arah bawah tampil sebagai pesan biasa.
- **Modal Edit Bundle**: Qty, Size (dropdown article_sizes hidup artikel), Line (dropdown resource) → Penjahit (employee per line, cascading Prompt 32). Baris info batas bawah qty. Jika size atau qty berubah dan simpan sukses → tampilkan notifikasi bahwa label lama tidak lagi sesuai + tawarkan tombol **Cetak Ulang** (pakai endpoint reprint existing).
- Setelah simpan sukses: refresh data halaman (info bundle + timeline).

## 4. Blazor — halaman `/report-bundle` (tab Riwayat, Prompt 13)

Tampilkan tombol edit yang sama di timeline Riwayat bundle:
- Syarat tampil sama: user login punya modul `SUPER_ADMIN`. Punya modul `REPORT_BUNDLE` saja TIDAK cukup — tanpa `SUPER_ADMIN` tampilan laporan tidak berubah.
- Tombol **Edit** per baris timeline + tombol **Edit Bundle** di header hasil pencarian.
- Pakai ulang komponen modal yang sama dengan halaman `/b/{serial}` (ekstrak jadi shared component, jangan duplikasi kode) dan endpoint yang sama.
- Setelah simpan sukses: refresh hasil pencarian riwayat.

## Aturan tetap berlaku

Soft delete, filter `deleted_at IS NULL`, prefix `SIS_`, pola `@Action`, UserId dari JWT, UI bahasa Indonesia.

## Yang TIDAK boleh dilakukan

- Jangan ubah `SIS_WorkflowLog_Manage`, `SIS_Bundle_Manage`, `SIS_Bundle_ScanInfo` — logika edit hanya di SP super admin.
- Jangan beri akses edit ke station token / operator.
- Jangan buat modul baru — pakai `SUPER_ADMIN`.
- Jangan tambah kolom baru (audit cukup `updated_at`/`updated_by`).
- Jangan sentuh serial, bundle_no, waktu log, atau data terima (received_*).
- Jangan buat override/bypass untuk validasi arah bawah — hard block untuk semua.

## Verifikasi

1. `dotnet build` sukses.
2. Skenario manual:
   - Login non-super-admin / tanpa login → `/b/{serial}` tampil seperti sekarang, tanpa tombol edit.
   - Super admin edit qty step tengah jadi lebih kecil dari total step berikutnya → ditolak dengan pesan menyebut angka.
   - Edit step paling akhir turun → sukses; lalu step sebelumnya bisa diturunkan mengikuti.
   - Edit qty naik melebihi qty masuk → dialog konfirmasi `QTY_EXCEED` → konfirmasi → tersimpan.
   - Edit pelaksana & remark saja → tersimpan, timeline refresh.
   - Edit qty bundle → qty_ok log Bundling ikut berubah; turun di bawah total step setelah Bundling → ditolak.
   - Ganti size bundle → tersimpan, muncul tawaran Cetak Ulang, label baru berisi size baru.
   - `/report-bundle` tab Riwayat: super admin melihat tombol edit dan bisa edit dengan validasi sama; user REPORT_BUNDLE tanpa SUPER_ADMIN tidak melihat tombol edit.
3. Di akhir: daftar file dibuat/diubah + script SQL yang harus dijalankan manual (`sp_SuperAdmin_Manage.sql`).

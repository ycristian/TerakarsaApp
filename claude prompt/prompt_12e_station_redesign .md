# Prompt 12e — Redesign Station Kiosk: Masuk / Dikerjakan / Dikirim

## Konteks

Station kiosk (`StationDevice.razor`, route `/station`) saat ini punya 3 tab: Menunggu Diterima, Menunggu Diserahkan, Baru Diterima. Ada gap struktural: tidak ada antrian kerja untuk bundle berstatus DIKERJAKAN (tab "Baru Diterima" dibatasi TOP 20 sehingga bundle lama hilang dari layar padahal masih dikerjakan).

Prompt ini me-redesign station kiosk menjadi 3 status yang mengikuti alur kerja operator:

- **Masuk** (Inbound) — bundle diserahkan ke divisi ini, belum diterima (`received_at IS NULL`, `target_division_id` = divisi station).
- **Dikerjakan** (On Progress) — bundle sudah diterima di divisi ini, belum ada baris log step berikutnya. Definisi identik dengan status DIKERJAKAN di `sql/sp_Report_Bundle.sql` (baris ~74–93). TANPA batasan TOP 20.
- **Dikirim** (Outbound) — divisi ini sudah membuat baris serah ke divisi berikutnya, divisi tujuan belum menerima (`received_at IS NULL` pada baris yang dibuat divisi ini). Begitu divisi tujuan menerima, bundle hilang dari station ini (murni transit, tanpa riwayat).

Rename istilah user-facing: **"Diserahkan" → "Dikirim"** di seluruh halaman station.

## Transisi status & aksi

| Aksi | Efek | Konfirmasi |
|---|---|---|
| Terima | Masuk → Dikerjakan (isi `received_at`) | Tidak (aksi ringan) |
| Serahkan | Dikerjakan → Dikirim (insert baris step berikutnya via form qty + divisi tujuan) | Tidak, tapi lewat form |
| Batal Terima | Dikerjakan → Masuk. **UNRECEIVE**: set `received_at = NULL` pada baris yang sama. **BUKAN delete** — baris log tetap hidup, audit utuh. | **Ya, modal konfirmasi wajib** |
| Batal Serah | Dikirim → Dikerjakan. Soft delete baris serah yang salah (`deleted_at`). | **Ya, modal konfirmasi wajib** |
| Revisi (di tab Dikirim) | Edit qty / divisi tujuan / penjahit pada baris serah, selama divisi tujuan belum menerima | Form edit |

Guard di SP:
- UNRECEIVE hanya boleh jika **belum ada baris log step berikutnya** untuk bundle tsb (kalau sudah diserahkan, harus Batal Serah dulu).
- Batal Serah dan Revisi hanya boleh jika baris serah masih `received_at IS NULL`.
- Semua guard divalidasi di SP layer (`SIS_WorkflowLog_Manage`), bukan hanya di UI.

## Pekerjaan

### 1. SQL (manual script, JANGAN auto-execute)

Buat file script SQL manual di folder `sql/`:

- **`SIS_Station_InProgress`** (SP baru, Read): daftar bundle status Dikerjakan di divisi station. Definisi mengikuti `sp_Report_Bundle.sql` (baris log terakhir bundle: `received_at IS NOT NULL` dan `target_division_id` = divisi station, belum ada baris step berikutnya). Tanpa TOP. Kolom minimal: serial, bundle_no, artikel, project/PO, size, qty, penjahit (`resource_id`/`resource_person_name`), `received_at`.
- **`SIS_Station_Counts`** (SP baru, Read): 3 angka — jumlah Masuk, Dikerjakan, Dikirim untuk divisi station. Satu SP, satu result set.
- **`SIS_Station_Outbound`** (SP baru atau ubah SP existing untuk "menunggu diserahkan"): daftar baris serah dari divisi ini yang `received_at IS NULL`, termasuk divisi tujuan.
- Ubah **`SIS_WorkflowLog_Manage`**: tambah `@Action = 'UNRECEIVE'` (set `received_at = NULL`, guard di atas), `@Action = 'CANCEL_HANDOVER'` (soft delete baris serah, guard `received_at IS NULL`), `@Action = 'REVISE_HANDOVER'` (update qty / target_division / resource pada baris serah, guard `received_at IS NULL`; isi kolom audit `updated_at`, `updated_by`, `updated_by_resource_id` dari Prompt 12d).
- SP existing `SIS_Station_RecentReceived` (TOP 20) tidak dipakai lagi di UI — biarkan filenya, jangan hapus.

### 2. API (StationController atau controller terkait)

- Endpoint GET untuk counts, in-progress list, outbound list (token station di header, seperti endpoint station existing).
- Endpoint POST untuk UNRECEIVE, CANCEL_HANDOVER, REVISE_HANDOVER — semua memakai `SIS_WorkflowLog_Manage` dengan `@Action` masing-masing.
- `created_by` / `updated_by` = station system user (id 6) sesuai konvensi log station. `last_seen_at` tetap ter-update di setiap request tervalidasi.

### 3. Blazor (`StationDevice.razor` + komponen terkait)

Layout dari atas ke bawah:

1. **Header**: nama station, divisi, tombol Refresh.
2. **Strip 3 kartu angka besar** (fungsi papan status, kebaca dari jauh): Masuk / Dikerjakan / Dikirim. Kartu Dikerjakan diberi aksen visual paling menonjol (antrian utama). Angka dari `SIS_Station_Counts`, refresh setelah setiap aksi.
3. **Panel Scan/ketik serial** (existing, dipertahankan).
4. **3 tab**: Masuk (badge count) / Dikerjakan (badge count) / Dikirim (badge count). Default aktif: Dikerjakan.

Isi tab:
- **Masuk**: seperti tab "Menunggu Diterima" existing. Aksi Terima (boleh multi-select seperti sekarang bila sudah ada).
- **Dikerjakan**: kartu per bundle (serial, artikel, size, qty, penjahit, "diterima X menit lalu"). Aksi per kartu: **Serahkan** (tombol utama, menonjol) dan **Batal Terima** (tombol sekunder kecil, diletakkan terpisah dari Serahkan agar tidak salah pencet, dengan modal konfirmasi "Yakin batal terima bundle {serial}? Bundle akan kembali ke daftar Masuk.").
- **Dikirim**: kartu per baris serah (serial, qty, divisi tujuan, "menunggu diterima {divisi}"). Aksi: **Revisi** (form edit qty/divisi tujuan/penjahit) dan **Batal Serah** (tombol sekunder, modal konfirmasi "Yakin batal serah bundle {serial}? Baris serah akan dihapus dan bundle kembali ke Dikerjakan."). Teks bantuan kecil: "Bisa direvisi/dibatalkan selama divisi tujuan belum menekan Terima."

Bahasa UI: Indonesia. Ganti semua label "Diserahkan" → "Dikirim" di halaman station.

## Dilarang

- JANGAN mengeksekusi SQL ke database — hasilkan file script manual di `sql/` saja.
- JANGAN menghapus SP existing atau kolom existing.
- JANGAN memakai hard delete — semua pembatalan baris serah pakai soft delete (`deleted_at`).
- JANGAN mengubah alur supervisor login module (`/workflow-input`) — hanya halaman station.
- JANGAN menambahkan validasi qty (QTY_EXCEED / QTY_SHORT) atau partial handover di prompt ini — itu scope Prompt 14/14b.
- JANGAN mengubah `sp_Report_Bundle` — definisinya jadi acuan, bukan target perubahan.

## Dependensi

- Jalankan SETELAH Prompt 12d (kolom audit `updated_at`, `updated_by`, `updated_by_resource_id` sudah ada — dipakai oleh REVISE_HANDOVER).
- Prompt ini MENGGANTIKAN rencana Prompt 15 (UNRECEIVE) — aksi Batal Terima sudah tercakup di sini.

## Verifikasi

- `dotnet build` sukses.
- Uji manual: Terima memindahkan angka Masuk→Dikerjakan; Serahkan memindahkan Dikerjakan→Dikirim; setelah divisi tujuan menerima, bundle hilang dari Dikirim station asal.
- Batal Terima mengembalikan bundle ke Masuk (baris log tidak terhapus, `received_at` NULL).
- Batal Serah menghapus (soft delete) baris serah dan bundle kembali muncul di Dikerjakan.
- UNRECEIVE ditolak SP bila sudah ada baris step berikutnya.

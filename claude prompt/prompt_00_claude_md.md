# Prompt 00 — Buat CLAUDE.md (Konvensi Proyek)

Buat file `CLAUDE.md` di root repo dengan isi PERSIS seperti di bawah. Jangan
menjelajah kode untuk "melengkapi" — isi sudah final. Satu-satunya verifikasi:
jalankan perintah build di bagian Perintah dan perbaiki path bila salah.

---ISI CLAUDE.md MULAI---

# TMOS — Terakarsa Manufacturing Operations System

Sistem pencatatan produksi garmen. Bahasa UI: Indonesia. Solo developer,
perubahan dieksekusi lewat prompt file bernomor di folder `claude prompt/`.

## Struktur

- `TerakarsaApp.Client` — Blazor WebAssembly (.NET 10)
- `TerakarsaApp.API` — ASP.NET Core Web API, JWT (tanpa ASP.NET Identity)
- `TerakarsaApp.Shared` — DTO bersama, satu file per area
- `TerakarsaApp.PrintService` — Windows Worker Service, printer TSC TTP-244 Pro (TSPL)
- `sql/` — semua script SQL, dijalankan MANUAL oleh developer (bukan migration)

## Perintah

- Build: `dotnet build TerakarsaApp.slnx -v q`
- Jangan `dotnet run` / start server — developer menjalankan sendiri.

## Aturan database (WAJIB)

- Semua akses data lewat stored procedure, prefix `SIS_`.
- Create/Update/Delete: satu SP `SIS_X_Manage` dengan `@Action`.
  Read: SP terpisah bernama fungsional (mis. `SIS_Project_List`).
- Soft delete di semua tabel: `deleted_at`/`deleted_by`; query hanya baris
  `deleted_at IS NULL`. Unique constraint = filtered index `WHERE deleted_at IS NULL`.
- Kolom audit standar: `created_at`, `created_by` (FK users, NOT NULL),
  `updated_at`, `updated_by`, `deleted_at`, `deleted_by`.
- `created_by`/`updated_by` SELALU user id (tabel users). Pelaksana produksi =
  `resource_id` (tabel resources). Employee TIDAK pernah jadi aktor di log.
- Validasi bisnis ditegakkan di SP (RAISERROR pesan Indonesia), bukan hanya di API.
- Pesan error yang butuh konfirmasi UI memakai prefix tetap, mis. `QTY_EXCEED|`,
  `QTY_SHORT|`.
- Script alter/seed idempotent (`IF NOT EXISTS`), file baru di `sql/`,
  dan `sql/create_tables_tmos_final.sql` selalu ikut diperbarui.

## Aturan aplikasi

- Auth: JWT + refresh token; localStorage via JS Interop (BUKAN
  Blazored.LocalStorage — tidak kompatibel .NET 10).
- Perangkat stasiun: header `X-Station-Token`, tanpa login; `created_by` diisi
  user sistem `station_system` (id dari appsettings `Station:SystemUserId`);
  operator dipilih per sesi → `resource_id`.
- Log workflow model 1 baris: baris dibuat saat divisi selesai/serah;
  `received_at IS NULL` = menunggu diterima. Tidak ada kolom status.
- Upload gambar: ImageSharp, max 1920px, JPEG 80; nama file GUID di disk,
  nama asli di DB.
- Navigasi halaman anak: full page + `CloseButton.razor` (`history.back()` +
  fallback URL). Tanpa tombol "Kembali ke X" hardcode.
- Module/menu di-seed lewat script idempotent (pola `seed_*_module.sql`).
- UI: Bootstrap, komponen `SearchableSelect` untuk dropdown pencarian.

## Cara kerja yang diharapkan

- Kerjakan HANYA yang diminta prompt file; hormati bagian "Yang TIDAK boleh
  dilakukan".
- Jangan refactor SP/kode lama di luar cakupan prompt.
- Baca hanya file yang relevan dengan prompt — jangan memindai seluruh repo.
- Akhiri dengan: daftar file dibuat/diubah + script SQL yang harus dijalankan manual.

---ISI CLAUDE.md SELESAI---

Setelah file dibuat dan build terverifikasi, laporkan selesai. Jangan mengubah
file lain.


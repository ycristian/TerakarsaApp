# Prompt 29 — Module Super Admin (Koreksi Langsung Bundle & Workflow Log)

## Konteks

Jalankan SETELAH Prompt 28 (memakai kolom `qty_reject_rework`, `qty_lost`, `log_type`). Module baru untuk koreksi data langsung yang melewati guard normal — dipakai jarang, hanya oleh user terpilih. Semua koreksi tetap soft-delete-aware dan meninggalkan jejak audit.

Scope yang sudah final:
- **Edit bundle langsung**: size, qty, bundle_no, serial — walau bundle sudah punya log (bypass guard "sudah ada log COMPLETED" di SIS_Bundle_Manage).
- **Hapus bundle**: HANYA bila bundle tidak punya log hidup sama sekali. Kalau ada log hidup → tolak dengan pesan jelas.
- **Edit workflow log**: semua kolom qty (ok, reject print/bahan/sewing/rework, hilang) + remark — termasuk baris yang sudah diterima. TANPA validasi kuota.
- **Hapus baris log**: soft delete + alasan wajib, termasuk baris yang sudah diterima dan baris yang sudah dipakai step berikutnya (bypass guard DELETE normal).
- Fitur "batalkan status diterima" TIDAK dibuat (sudah ada Batal Terima di stasiun).

## 1. Module & SQL

`sql/seed_super_admin_module.sql` (idempotent, pola seed module yang ada):
- Code `SUPER_ADMIN`, Name "Super Admin", Route `super-admin`, icon mis. `fe fe-shield`, grup menu paling bawah.
- **JANGAN auto-assign ke role/user mana pun** — pemberian akses hanya lewat halaman manajemen user yang sudah ada. Beri komentar di script menjelaskan ini disengaja.

## 2. Stored Procedure baru: `sql/sp_SuperAdmin_Manage.sql`

`SIS_SuperAdmin_Manage` dengan `@Action`:

- **BUNDLE_UPDATE** (@BundleId, @ArticleSizeId, @Qty, @BundleNo, @Serial, @UserId):
  - Validasi: bundle hidup; article_size milik artikel bundle; qty > 0; serial unik di antara bundle hidup; bundle_no unik per project di antara bundle hidup (project via JOIN articles).
  - Update + isi updated_at/updated_by. TIDAK menyentuh log yang ada.
- **BUNDLE_DELETE** (@BundleId, @DeleteReason wajib, @UserId): tolak bila ada baris hidup di article_workflow_logs untuk bundle ini ('Bundle sudah punya log workflow — hapus lognya dulu atau batalkan.'). Soft delete.
- **LOG_UPDATE** (@WorkflowLogId, keenam qty, @Remark, @UserId): baris hidup apa pun (NORMAL/ADJUSTMENT, sudah diterima atau belum). Tanpa validasi kuota dan tanpa guard received. Validasi minimal: baris ADJUSTMENT → total keenam qty tetap harus 0 dan qty_ok >= 0; baris NORMAL → qty non-negatif. Isi updated_at/updated_by.
- **LOG_DELETE** (@WorkflowLogId, @DeleteReason wajib max 255, @UserId): soft delete tanpa guard received/step-berikutnya.

SP read: `SIS_SuperAdmin_BundleSearch` (@Search) — cari bundle hidup by serial / bundle_no / nama artikel / project, TOP 50, kolom: bundle_id, bundle_no, serial, project, artikel, style, color, size, qty, jumlah log hidup.

## 3. API

Controller/route baru dengan `RequireModule("SUPER_ADMIN")`:
- GET `api/super-admin/bundles?search=` → BundleSearch.
- GET `api/super-admin/bundles/{id}` → detail bundle + daftar size artikel (untuk dropdown) + semua log hidup bundle (pakai/extend SP list log yang ada, sertakan LogType, received info).
- PUT `api/super-admin/bundles/{id}` → BUNDLE_UPDATE.
- DELETE `api/super-admin/bundles/{id}` (+ reason di body) → BUNDLE_DELETE.
- PUT `api/super-admin/workflow-logs/{id}` → LOG_UPDATE.
- DELETE `api/super-admin/workflow-logs/{id}` (+ reason) → LOG_DELETE.

## 4. Blazor Client — halaman `/super-admin`

1. **Pencarian bundle** (input search + tabel hasil). Klik baris → panel detail.
2. **Panel Edit Bundle**: form size (dropdown size artikel), qty, bundle_no, serial. Peringatan permanen di form: "Mengubah serial membuat label QR yang sudah dicetak tidak berlaku." Setelah simpan sukses → tawarkan tombol **"Cetak Ulang Label"** (endpoint reprint yang sudah ada). Tombol **Hapus Bundle** (modal konfirmasi + alasan wajib) — tampilkan pesan tolakan SP apa adanya bila ada log.
3. **Tabel log bundle**: semua baris hidup (step, tipe NORMAL/ADJUSTMENT, keenam qty, tujuan, status diterima, remark, waktu). Per baris: tombol **Edit** (modal: keenam qty + remark, badge peringatan "Tanpa validasi kuota — angka disimpan apa adanya") dan **Hapus** (modal + alasan wajib, peringatan ekstra bila baris sudah diterima atau sudah dipakai step berikutnya).
4. Semua aksi selesai → refresh detail. UI bahasa Indonesia, pola komponen/tabel yang sudah ada.

## Yang TIDAK boleh dilakukan

- Jangan ubah SIS_Bundle_Manage / SIS_WorkflowLog_Manage — semua bypass lewat SP baru SIS_SuperAdmin_Manage.
- Jangan buat fitur batalkan received_at.
- Jangan buat hard delete.
- Jangan auto-assign module ke role Admin.
- Jangan mengeksekusi SQL ke database — script manual di `sql/` saja.

## Verifikasi

- `dotnet build` sukses.
- Uji: ubah qty & serial bundle yang sudah punya log → sukses; hapus bundle ber-log → ditolak; edit qty baris log yang sudah diterima → sukses + updated_by terisi; hapus baris log yang sudah dipakai step berikutnya → sukses (soft delete + alasan).
- User tanpa module SUPER_ADMIN tidak melihat menu dan endpoint menolak.

Setelah selesai: daftar file dibuat/diubah + daftar script SQL yang harus dijalankan manual.

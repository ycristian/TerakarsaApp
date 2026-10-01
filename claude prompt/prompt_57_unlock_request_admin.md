# Prompt 57 — Module Admin: Approval Request Unlock

## Prasyarat

Prompt 55 dan 56 selesai. Stasiun sudah bisa mengajukan unlock
(`SIS_UnlockRequest_Manage CREATE`).

## Konteks

Baris log yang sudah di-lock hanya bisa dibuka lewat pengajuan dari stasiun yang
disetujui admin. Prompt ini membuat module admin terpisah untuk memeriksa dan
memutuskan pengajuan itu. Aksi tulis (APPROVE/REJECT) sudah ada di
`SIS_UnlockRequest_Manage` (Prompt 55) — prompt ini hanya read SP, API, dan halaman.

## 1. Module

`sql/seed_57_unlock_request_module.sql` (idempotent, pola seed module yang ada):
- Code `UNLOCK_REQUEST`, Name "Request Unlock", Route `unlock-requests`, icon gembok
  terbuka, grup yang sama dengan module produksi/Super Admin (ikuti penempatan yang paling
  dekat).
- Tidak di-auto-assign ke semua admin — assign manual oleh developer.

## 2. SP read (`sql/sp_UnlockRequest_Select.sql`)

### `SIS_UnlockRequest_List`
Param: `@State varchar(10)` ('PENDING' default / 'APPROVED' / 'REJECTED' / 'ALL'),
`@DivisionId int = NULL`, `@DateFrom date = NULL`, `@DateTo date = NULL`.
Per request: RequestId, CreatedAt (waktu ajukan), DivisionName, StationName,
RequestedByResourceName, Reason, JumlahBaris, TotalQty, State (diturunkan dari
timestamp), DecidedAt, DecidedByName, AdminNote, **PeriodeFinal** (bit — ada lock item di
periode yang sudah final; request seperti ini pasti ditolak SP saat APPROVE).
Soft-deleted (dibatalkan pengaju) tidak ditampilkan.
Urut: PENDING terlama dulu; selain itu terbaru dulu.

### `SIS_UnlockRequest_Detail`
Param: `@RequestId`.
- Result 1 (header): seperti List.
- Result 2 (baris): per item — WorkflowLogId, ProjectName, ArticleName, StepName,
  BundleNo/Serial (NULL untuk non-bundle), SizeName, PenjahitName, PeriodeLock
  (period_code lock yang diminta dilepas), **Sebelum** = snapshot item lock yang diminta
  dilepas (6 kategori qty, size, resource), **Sekarang** = nilai terkini baris log
  (atau "dihapus" bila baris sudah soft delete), **LockUlang** = period_code + waktu lock
  aktif sekarang bila baris sudah di-lock ulang (NULL bila belum).
- Kolom **Berubah** (bit) per baris: nilai Sekarang ≠ Sebelum.

## 3. API (`UnlockRequestController`, `[RequireModule("UNLOCK_REQUEST")]`)

- GET `api/unlock-requests?state=&divisionId=&dateFrom=&dateTo=`
- GET `api/unlock-requests/{id}`
- POST `api/unlock-requests/{id}/approve` body `{ adminNote? }` → APPROVE, `@UserId` dari JWT.
- POST `api/unlock-requests/{id}/reject` body `{ adminNote }` → REJECT.
- Pesan error SP diteruskan apa adanya.

## 4. Halaman `/unlock-requests`

- Filter: tab **Menunggu / Disetujui / Ditolak / Semua** (badge jumlah di tab Menunggu),
  dropdown divisi, rentang tanggal.
- Tabel: waktu ajukan, divisi, stasiun, operator, jumlah baris, total qty, alasan
  (dipotong), status. Request dengan `PeriodeFinal = 1` diberi badge merah
  "Periode sudah final".
- Klik baris → halaman detail full page (pola `CloseButton.razor`):
  - Header: info request + alasan lengkap.
  - Tabel baris dengan kolom **Sebelum** vs **Sekarang**; sel yang berubah disorot.
    Untuk request yang masih menunggu, Sekarang = Sebelum (baris masih terkunci) —
    tampilkan satu kolom saja agar tidak membingungkan.
    Untuk request yang sudah disetujui, tampilkan kolom **Lock Ulang** — baris yang belum
    di-lock ulang diberi badge kuning "belum lock ulang".
  - Request menunggu: tombol **Setujui** (catatan opsional) dan **Tolak** (catatan wajib),
    masing-masing lewat dialog konfirmasi. Setelah berhasil kembali ke daftar.

## Yang TIDAK boleh dilakukan

- Jangan ubah `SIS_UnlockRequest_Manage` atau guard Prompt 55.
- Jangan buat aksi "unlock langsung" tanpa request.
- Jangan buat UI finalisasi periode gajian (menyusul).
- Jangan ubah halaman stasiun.

Setelah selesai: daftar file dibuat/diubah + script SQL yang harus dijalankan manual,
masing-masing sebagai markdown link.

# Prompt 15 — Pembatalan Penerimaan (Undo Receive) di Stasiun

## Prasyarat

Wajib setelah Prompt 12d (memakai kolom updated_at / updated_by /
updated_by_resource_id). Disarankan dieksekusi setelah Prompt 14 karena menyentuh
SP yang sama (SIS_WorkflowLog_Manage).

## Konteks

Salah tekan "Terima" di stasiun saat ini permanen. Tambahkan pembatalan penerimaan
dengan jendela sempit: hanya selama divisi penerima BELUM mencatat hasil di step
berikutnya. Tanpa kolom baru, tanpa module baru — jejak memakai trio 12d.

## 1. SIS_WorkflowLog_Manage — action UNRECEIVE

Parameter: @Id (wajib), @UserId (wajib), @UpdatedByResourceId (wajib —
'Operator wajib dipilih.').

Validasi berurutan:
1. Baris hidup dan received_at NOT NULL ('Baris ini belum diterima.').
2. @DivisionId (divisi stasiun) = target_division_id baris
   ('Hanya divisi penerima yang bisa membatalkan.').
3. @UpdatedByResourceId resource hidup milik divisi tsb
   ('Operator bukan milik divisi ini.').
4. Khusus baris ber-bundle: tidak boleh ada log hidup bundle yang sama pada step
   dengan sort_order lebih besar
   ('Sudah ada hasil tercatat di step berikutnya. Hapus dulu hasil tersebut.').
   Baris non-bundle: tanpa pemeriksaan lanjutan.

Eksekusi: SET received_at = NULL, received_by_resource_id = NULL,
received_remark = NULL, updated_at = SYSDATETIME(), updated_by = @UserId,
updated_by_resource_id = @UpdatedByResourceId.

Akibat wajar: baris kembali muncul di "Menunggu Diterima" divisi ini dan
"Menunggu Diserahkan" divisi asal.

## 2. SP read — SIS_Station_RecentReceived

Di sql/sp_Station_Operations.sql. Param: @DivisionId. Mengembalikan maksimal 20
baris terakhir yang diterima divisi ini (target_division_id = @DivisionId,
received_at NOT NULL, hidup), urut received_at DESC:
WorkflowLogId, BundleNo, Serial (NULL utk non-bundle), ArticleName, SizeName,
StepName, DivisionAsalName, QtyOk, ReceivedAt, ReceivedByResourceName,
CanUnreceive (BIT — hasil pemeriksaan poin 4 di atas, supaya tombol bisa
dinonaktifkan di UI).

## 3. API (StationDeviceController, X-Station-Token)

- GET `api/station/recent-received` → SIS_Station_RecentReceived.
- POST `api/station/logs/{id}/unreceive` body { resourceId } → action UNRECEIVE,
  @UserId = user sistem station. Teruskan pesan error SP apa adanya.

## 4. Client — StationDevice.razor

- Tab/bagian baru "Baru Diterima" di samping tab yang ada, badge jumlah tidak perlu.
- Kartu per baris: info bundle/step/qty + waktu terima + penerima; tombol
  "Batal Terima" (disabled bila CanUnreceive = 0, dengan tooltip alasannya).
- Klik tombol → dialog konfirmasi "Batalkan penerimaan {bundle/step}? Baris akan
  kembali ke Menunggu Diterima." → kirim dengan operator sesi aktif → refresh
  daftar + tab Menunggu Diterima.
- Bahasa Indonesia, pola komponen mengikuti tab yang sudah ada.

## Yang TIDAK boleh dilakukan

- Jangan buat module/menu baru — ini bagian halaman stasiun.
- Jangan izinkan UNRECEIVE dari halaman login (belum dibutuhkan).
- Jangan tambah kolom/tabel; jangan simpan alasan pembatalan.
- Jangan sentuh alur scan publik, bundle, print, laporan.

Setelah selesai: daftar file dibuat/diubah + script SQL manual.

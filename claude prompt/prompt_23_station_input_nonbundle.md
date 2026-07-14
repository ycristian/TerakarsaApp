# Prompt 23 — Input Non-Bundle Pindah ke Station (Model IN/WIP/OUT, Hapus /workflow-input)

## Konteks

Step pertama workflow tidak selalu Cutting — bisa ada rantai antar step non-bundle (mis. DTF Print → Cutting → [Bundling] → Sewing). Pencatatnya operator lantai, jadi input step non-bundle dipindah PENUH dari halaman `/workflow-input` (Prompt 12c) ke station kiosk (`StationDevice.razor`). Halaman dan module `WORKFLOW_INPUT` dihapus.

Station sudah redesign 3 status IN/WIP/OUT (Prompt 12e). Item non-bundle DIINTEGRASIKAN ke model yang sama — TIDAK ada tab baru:

- **IN**: kiriman baris level artikel dari step sebelumnya → SUDAH didukung (SIS_Station_PendingReceives berbasis baris log, mencakup non-bundle). Tidak ada perubahan.
- **WIP**: untuk divisi yang punya step non-bundle, tampil **kartu permanen per (artikel × step non-bundle)** pada project aktif — sejajar kartu bundle, dengan tombol **"Kirim Hasil"** → grid size. Kartu TIDAK hilang setelah kirim (input nyicil berulang sampai project ditutup). Tanpa langkah pilih project/artikel — kartu antrian sudah = daftar artikelnya.
- **OUT**: baris non-bundle SUDAH tampil (SIS_Station_PendingHandover berbasis baris log). Aksi **Revisi** (REVISE_HANDOVER) dan **Batal Serah** (CANCEL_HANDOVER) yang ada dari 12e berlaku juga untuk baris non-bundle — guard `received_at IS NULL` sudah sama. Pastikan modal Revisi berfungsi untuk baris tanpa bundle.

Keputusan desain lain yang sudah disepakati:
1. **Tanpa prasyarat receive**: step non-bundle lanjutan TIDAK wajib menerima kiriman step sebelumnya dulu. Aturan "bebas dicatat kapan pun" tetap berlaku.
2. **Auto-receive Prompt 17 dipersempit**: saat bundle dibuat, yang di-receive otomatis HANYA baris log dari step non-bundle TERAKHIR (sort_order non-bundle terbesar) yang `received_at IS NULL`. Baris step non-bundle sebelumnya diterima manual divisi berikutnya lewat tab IN.
3. **Hapus dengan alasan** tetap admin saja lewat riwayat log di Edit Article (sudah ada). Batal Serah operator (soft delete tanpa alasan, hanya sebelum diterima) tetap seperti 12e.
4. **Grid semua size** sekaligus (pola Prompt 19), bukan satu size per simpan.

Data DB masih data uji — tidak perlu backfill.

## 1. SQL

### a. `sql/sp_Bundle_Manage.sql` — persempit auto-receive (Prompt 17)
Pada CREATE: auto-receive hanya baris `article_workflow_logs` hidup milik artikel ini yang `received_at IS NULL` DAN berasal dari step non-bundle dengan `sort_order` TERBESAR di antara step `requires_bundle = 0` hidup artikel itu. Baris step non-bundle lain dibiarkan.

### b. `sql/sp_Station_Operations.sql`

**SIS_Station_ActiveWork** (hidupkan lagi, tak terpakai sejak 12c) — sumber kartu WIP non-bundle:
- Per (artikel × step non-bundle) milik @DivisionId pada project aktif (ikuti definisi status project Prompt 18): article_workflow_id, project_name, article_name, style, color, step_name, divisi tujuan step berikutnya (informasi, dikunci ulang server saat submit), daftar size (FOR JSON: article_size_id, size_name, qty_order, **total qty_ok tercatat step ini per size**) — untuk grid + kolom Order/Tercatat tanpa round-trip.

**SIS_Station_Counts** — hanya `DikerjakanCount` yang berubah: tambah jumlah kartu non-bundle (artikel × step dari definisi ActiveWork). `MasukCount` dan `DikirimCount` SUDAH benar (berbasis baris log) — jangan diubah.

**SIS_Station_PendingHandover** — cek saja: baris non-bundle harus membawa size_name + qty-qty (harusnya sudah sejak 12b); tambal bila kurang.

### c. `sql/remove_workflow_input_module.sql` (dijalankan manual, idempotent)
Soft delete module `WORKFLOW_INPUT` + baris assignment user-nya.

### Yang TIDAK diubah
`SIS_WorkflowLog_Manage` — validasi CREATE/UPDATE/RECEIVE/UNRECEIVE/REVISE_HANDOVER/CANCEL_HANDOVER/DELETE tetap. Tidak ada action atau prasyarat baru.

## 2. API

### Station ([RequireStationToken], divisi dari token)
- GET `api/station/active-work` — hidupkan lagi (SIS_Station_ActiveWork versi baru), dipanggil bersama in-progress untuk mengisi tab WIP.
- POST `api/station/nonbundle-logs/batch` — pindahan endpoint batch Prompt 19 (dari WorkflowInputController yang dihapus): list entri `{ArticleSizeId, QtyOk, RejectPrint, RejectBahan, RejectJahit}` + articleWorkflowId + resourceId (operator sesi, WAJIB) + remark opsional. Satu transaksi, loop `SIS_WorkflowLog_Manage @Action='CREATE'`, gagal satu rollback semua. Validasi API: step milik divisi token & `requires_bundle = 0`.
- Revisi & Batal Serah baris non-bundle: pakai endpoint REVISE_HANDOVER / CANCEL_HANDOVER yang SUDAH ada — tidak buat endpoint baru.

### Dihapus
- `WorkflowInputController` seluruhnya (picker artikel, nonbundle-steps, logs, logs/batch).
- `WorkflowLogController`: hapus `WORKFLOW_INPUT` dari RequireModule (sisakan ORDER_PROJECT). Endpoint riwayat + delete untuk Edit Article TETAP.
- Validasi 12c di POST `api/station/complete` (menolak step non-bundle) TETAP — jalur bundle dan non-bundle beda endpoint.

## 3. Blazor Client — `StationDevice.razor` (/station)

### Tab WIP
1. Kartu non-bundle tampil BERSAMA kartu bundle (pembeda visual ringan: badge nama step, tanpa No bundle/serial). Isi kartu: artikel, project, style/color, step, tujuan berikutnya, ringkas total tercatat (mis. "Tercatat 120 dari 300"). Tombol: **Kirim Hasil** saja (tanpa Batal Terima).
2. **Kirim Hasil** → panel/modal grid (pola Prompt 19): baris per size ber-qty order > 0: Ukuran | Qty Order | Tercatat | Qty OK | Reject Print | Reject Bahan | Reject Jahit. Di bawah grid: Catatan (opsional, satu untuk batch). Pelaksana = operator sesi (read-only). Divisi tujuan read-only.
3. Simpan: baris semua-nol dilewati, minimal satu baris > 0. Sukses → kembali ke WIP, angka Tercatat ter-refresh; kartu tetap ada.
4. **Pencarian teks WAJIB di tab WIP** (jumlah kartu bisa banyak: banyak project × artikel): satu input di atas daftar, filter client-side terhadap project_name, article_name, style, color, step_name, dan (untuk kartu bundle) bundle_no/serial — berlaku ke SEMUA kartu, bundle maupun non-bundle. Kartu dikelompokkan per project (header project) supaya daftar tetap terbaca.

### Tab OUT
Baris non-bundle: tampilkan size + qty + tujuan (tanpa serial). Modal **Revisi** existing harus jalan untuk baris non-bundle (sembunyikan field yang tidak relevan, mis. penjahit bila tidak dipakai). **Batal Serah** existing berlaku juga — teks konfirmasi disesuaikan ("Yakin batal kirim hasil {step} {size}? Baris input akan dihapus.").

### Tab IN
Tidak ada perubahan fungsi — pastikan baris non-bundle terbaca jelas (size, qty kirim, step asal).

### Dihapus
- Halaman `/workflow-input` + `WorkflowInputManager.razor` + service client terkait.
- `ArticlePicker.razor` TETAP (masih dipakai `/bundles`).
- Menu module WORKFLOW_INPUT hilang otomatis setelah script bagian 1c dijalankan.

## Yang TIDAK boleh dilakukan

- Jangan ubah `SIS_WorkflowLog_Manage` — perubahan auto-receive hanya di `SIS_Bundle_Manage`.
- Jangan tambah prasyarat RECEIVE untuk step non-bundle.
- Jangan ubah MasukCount/DikirimCount di SIS_Station_Counts.
- Jangan sentuh alur scan bundle, complete bundle, print, Batal Terima, atau kartu bundle yang sudah ada selain penambahan kartu/baris non-bundle.
- Jangan buat tab baru — semua lewat IN/WIP/OUT.
- Jangan hapus endpoint riwayat/delete log di WorkflowLogController (dipakai Edit Article).

Setelah selesai: daftar file dibuat/diubah/dihapus + script SQL yang harus dijalankan manual.

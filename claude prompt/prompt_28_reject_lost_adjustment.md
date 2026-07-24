# Prompt 28 — Qty Lost, Qty Reject Rework & Penyesuaian (ADJUSTMENT) di /b/

## Konteks

Dua kategori qty baru di log workflow: **hilang** (`qty_lost`) dan **reject rework** (`qty_reject_rework`). Selain itu, halaman `/b/{serial}` mendapat fitur **Penyesuaian**: qty yang sudah tercatat sebagai reject/hilang bisa dikurangi lalu dipindah ke kategori reject/hilang lain ATAU ke Qty OK (barang berhasil diperbaiki / ditemukan). Total mutasi wajib 0.

Contoh mutasi yang sah:
- Reject Bahan -1, Qty OK +1
- Hilang -2, Qty OK +2
- Reject Bahan -2, Qty OK +1, Reject Rework +1

Keputusan yang sudah final:
- Arah mutasi HANYA: dari kategori reject/hilang → kategori reject/hilang lain, atau → Qty OK. **Qty OK tidak pernah boleh dikurangi.**
- Penyesuaian dicatat sebagai **baris log baru** `log_type = 'ADJUSTMENT'` (riwayat terjaga, baris lama tidak diubah).
- Yang boleh melakukan penyesuaian: **divisi pemilik step tempat reject/hilang tercatat** (via station token di /b/).
- Baris log dengan `qty_ok = 0` (baik NORMAL maupun ADJUSTMENT) **tidak butuh penerimaan**: tidak memakai `received_at`, cukup tidak pernah muncul di "Menunggu Diterima" dan tidak menghalangi step berikutnya. Baris dengan `qty_ok > 0` mengikuti alur terima manual seperti biasa.
- Penyesuaian hanya untuk log ber-bundle (via /b/). Step non-bundle (Hasil Cutting) TIDAK dapat fitur ini.

## 1. Skema SQL

a. Di `sql/create_tables_tmos_final.sql`, tabel `article_workflow_logs`, tambah setelah `qty_reject_sewing`:

```sql
 qty_reject_rework int not null default 0,
 qty_lost int not null default 0,
 log_type varchar(15) not null default 'NORMAL',  -- NORMAL / ADJUSTMENT (mutasi antar kategori qty, total 0)
```

Tambahkan komentar di atas tabel: baris ADJUSTMENT boleh berisi nilai negatif pada kolom reject/lost (mutasi), `qty_ok` pada baris ADJUSTMENT selalu >= 0, dan jumlah keenam kolom qty baris ADJUSTMENT selalu 0.

b. Buat `sql/alter_28_reject_lost.sql` (idempotent): ADD ketiga kolom di atas dengan default constraint bernama. Tidak perlu backfill (default 0 / 'NORMAL' sudah benar untuk data lama).

## 2. Stored Procedures

### SIS_WorkflowLog_Manage

Parameter baru: `@QtyRejectRework INT = 0`, `@QtyLost INT = 0`.

1. **CREATE & UPDATE & REVISE_HANDOVER**: sertakan kedua kolom baru di INSERT/UPDATE. Validasi non-negatif berlaku juga untuk keduanya (khusus action non-ADJUST).
2. **Semua penjumlahan `@QtySudah`** (CREATE dan UPDATE) diubah menjadi `SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost)`. Karena baris ADJUSTMENT selalu bertotal 0, baris itu otomatis netral terhadap kuota step-nya sendiri — tidak perlu filter log_type.
3. `@QtyMasuk` step berikutnya tetap `SUM(qty_ok)` step sebelumnya — baris ADJUSTMENT dengan qty_ok > 0 SENGAJA ikut terhitung (barang hasil perbaikan mengalir ke step berikutnya).
4. **Action baru `ADJUST`** — parameter: @ArticleWorkflowId, @BundleId (wajib), @ResourceId (pelaksana, wajib, resource hidup divisi step), @QtyOk (>= 0), @QtyRejectPrint/@QtyRejectFabric/@QtyRejectSewing/@QtyRejectRework/@QtyLost (boleh negatif/positif), @TargetDivisionId, @Remark, @ActingDivisionId, @UserId. Validasi (pesan error jelas, bahasa Indonesia):
   - Step hidup, requires_bundle = 1, bundle milik artikel step.
   - @ActingDivisionId (dari station token) harus = division_id step. Jika tidak: 'Penyesuaian hanya boleh dilakukan divisi pemilik step ini.'
   - @QtyOk >= 0 ('Qty OK tidak boleh dikurangi lewat penyesuaian.').
   - Jumlah keenam nilai harus 0 ('Total penyesuaian harus 0.').
   - Minimal satu nilai <> 0.
   - Per kategori reject/lost: saldo setelah penyesuaian tidak boleh negatif. Saldo = SUM kolom tsb atas semua baris hidup (step, bundle) ini. Error contoh: 'Saldo Reject Bahan hanya 1, tidak bisa dikurangi 2.'
   - Jika @QtyOk > 0: @TargetDivisionId wajib KECUALI step ini adalah step ber-bundle terakhir; default yang dikirim client = divisi step ber-bundle berikutnya (dikunci, sama seperti alur COMPLETE). Jika @QtyOk = 0: target_division_id disimpan NULL.
   - INSERT baris log_type = 'ADJUSTMENT', received_at NULL, kolom lain mengikuti pola CREATE.
5. **DELETE**: guard yang ada tetap; baris ADJUSTMENT boleh dihapus dengan aturan sama (soft delete + alasan).

### Aturan "qty_ok = 0 tidak butuh diterima" (revisi SP terkait)

- `SIS_Station_PendingReceives`: tambah filter `qty_ok > 0`.
- `SIS_Bundle_ScanInfo`: penentuan allowed_action 'RECEIVE' hanya memandang baris `qty_ok > 0` yang belum diterima. Syarat COMPLETE step selanjutnya ("step sebelumnya sudah diterima") juga hanya memandang baris qty_ok > 0 — kalau seluruh baris step sebelumnya qty_ok = 0, tidak ada yang bisa/perlu dikerjakan (QtyMasuk = 0), biarkan kuota yang menolak.
- `SIS_Station_Counts` dan `SIS_Station_Outbound` (tab Dikirim): baris qty_ok = 0 tidak dihitung/ditampilkan sebagai "menunggu diterima".
- ScanInfo result set 3: tambah kolom `allowed_adjust BIT` = 1 bila @DivisionId adalah divisi salah satu step ber-bundle bundle ini yang punya saldo reject/lost > 0, plus result set/kolom saldo per kategori per step (untuk prefill form penyesuaian). Boleh sebagai result set ke-4 agar tidak merombak yang ada.

### SP penjumlah lain

Perbarui SEMUA SP yang menjumlahkan qty reject agar menyertakan `qty_reject_rework + qty_lost`, minimal: `SIS_WorkflowLog_QuotaInfo` (@QtySudah), `SIS_Report_BundleVariance` (QtyKeluar), `SIS_Bundle_ScanInfo` (QtySudah kuota). Grep seluruh folder `sql/` untuk pola `qty_reject_sewing` dan sesuaikan satu per satu. `SIS_WorkflowLog_ListByArticle` dan SP timeline: tambah kolom QtyRejectRework, QtyLost, LogType.

## 3. API

- Semua request/DTO log (StationCompleteRequest, StationLogUpdateRequest, StationReviseHandoverRequest, WorkflowInputCreateRequest, DTO list/timeline) ditambah `QtyRejectRework`, `QtyLost` (+ `LogType` pada DTO baca).
- Endpoint baru POST `api/station/adjust` ([RequireStationToken]) — body: ArticleWorkflowId, BundleId, ResourceId, keenam nilai qty, TargetDivisionId nullable, Remark → SIS_WorkflowLog_Manage @Action='ADJUST', @ActingDivisionId dari token, created_by = user sistem station.

## 4. Blazor Client

### Form input hasil (station Serahkan + Revisi, dan /workflow-input)

Tambah dua input: **Reject Rework** dan **Hilang** (default 0, pola input numerik yang sama). Info kuota "Masuk/Tercatat/Sisa" otomatis benar karena SP-nya sudah direvisi.

### /b/{serial} — panel Penyesuaian (BundleScanCard)

1. Tombol **"Penyesuaian"** muncul hanya bila scan info `allowed_adjust = 1` dan operator sudah dipilih.
2. Form: pilih step (kalau divisi ini punya lebih dari satu step ber-saldo; kalau satu, langsung terpilih), lalu per kategori tampilkan **saldo saat ini** + input mutasi: Reject Print, Reject Bahan, Reject Sewing, Reject Rework, Hilang (boleh minus/plus), dan Qty OK (hanya plus). Baris total live di bawah form: hijau bila 0, merah + tombol simpan disabled bila <> 0. Client juga cegah mutasi minus melebihi saldo.
3. Divisi tujuan: tampil terkunci (divisi step ber-bundle berikutnya) hanya bila Qty OK > 0.
4. Remark opsional. Simpan → refresh scan info.
5. Timeline: baris ADJUSTMENT diberi badge "Penyesuaian" dan tampilkan nilai bertanda (+/-). Baris qty_ok = 0 tidak menampilkan status "Menunggu diterima".
6. Tab Masuk /station: item dari baris ADJUSTMENT (qty_ok > 0) tampil dengan badge "Penyesuaian".

## Yang TIDAK boleh dilakukan

- Jangan izinkan qty_ok berkurang lewat ADJUST dalam bentuk apa pun.
- Jangan tambahkan fitur penyesuaian di /workflow-input (non-bundle) — di luar scope.
- Jangan ubah format serial, alur cetak label, packing, atau surat jalan.
- Jangan hard delete; semua aturan soft delete & immutability tetap.
- Jangan mengeksekusi SQL ke database — hasilkan script manual di `sql/` saja.

## Verifikasi

- `dotnet build` sukses.
- Uji: catat hasil dengan reject bahan 2 → penyesuaian Reject Bahan -2, OK +1, Rework +1 → total kuota step tidak berubah, QtyMasuk step berikutnya bertambah 1, baris OK +1 muncul di Menunggu Diterima divisi tujuan.
- Penyesuaian dengan total <> 0 atau saldo tidak cukup ditolak SP.
- Baris qty_ok = 0 tidak muncul di Menunggu Diterima / Dikirim.

Setelah selesai: daftar file dibuat/diubah + daftar script SQL yang harus dijalankan manual.

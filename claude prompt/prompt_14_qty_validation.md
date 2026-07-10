# Prompt 14 — Validasi Keseimbangan Qty, Hapus Rework, Laporan Selisih

## Prasyarat

Dijalankan SETELAH Prompt 12d dan Prompt 13 selesai.

## Konteks & keputusan

1. Rantai qty per bundle: keluaran satu step tidak boleh diam-diam melebihi
   masukan. Batas step N = SUM qty_ok step sebelumnya (step bundle pertama =
   bundles.qty). Reject tidak mengalir ke step berikutnya.
2. Melebihi batas BOLEH (kasus nyata: menemukan barang dari bundle lain), tapi
   harus lewat konfirmasi sadar — bukan blok keras.
3. Kurang dari batas tidak diblok sama sekali; kebocoran ditangkap laporan selisih.
4. qty_rework DIHAPUS dari sistem — skenarionya belum ada, membuat rantai qty ambigu.
5. Cutting (step non-bundle) boleh melebihi qty pesanan — wajar karena bahan tidak
   bisa dikontrol pas. Tidak ada validasi terhadap pesanan; progres di laporan
   dibatasi 100% dan kelebihan ditampilkan per size.

## 1. Skema — hapus qty_rework

- `sql/alter_14_drop_rework.sql` (idempotent): DROP COLUMN qty_rework dari
  article_workflow_logs (drop default constraint dulu bila ada).
- Perbarui `sql/create_tables_tmos_final.sql`: hilangkan kolom qty_rework.
- Bersihkan qty_rework dari: SIS_WorkflowLog_Manage (param, INSERT, UPDATE),
  semua SP read yang menyebutnya, SP laporan Prompt 13 (rumus QtyReject menjadi
  hanya 3 kolom reject), DTO Shared, form stasiun & Hasil Cutting, tampilan
  riwayat/laporan.

## 2. SIS_WorkflowLog_Manage — validasi kuota

Berlaku untuk action CREATE dan UPDATE, hanya pada step ber-bundle
(@BundleId NOT NULL):

- Hitung @QtyMasuk:
  - step bundle pertama artikel (sort_order terkecil requires_bundle = 1) →
    bundles.qty;
  - selain itu → SUM(qty_ok) log hidup bundle tsb pada step sebelumnya
    (sort_order requires_bundle = 1 tepat di bawahnya).
- Hitung @QtySudah = SUM(qty_ok + qty_reject_print + qty_reject_fabric +
  qty_reject_sewing) log hidup bundle tsb pada step ini (untuk UPDATE: kecualikan
  baris yang sedang direvisi).
- Jika @QtySudah + qty baris baru > @QtyMasuk DAN @ConfirmExceed = 0 →
  RAISERROR dengan format tetap:
  'QTY_EXCEED|Total melebihi qty masuk step ini (masuk %d, sudah tercatat %d).'
  (prefix QTY_EXCEED| dipakai UI untuk mengenali kasus ini).
- Parameter baru: @ConfirmExceed BIT = 0. Jika 1 → lolos.
- Tidak ada validasi bawah (boleh kurang). Tidak ada validasi qty untuk step
  non-bundle.

## 3. Info kuota untuk UI

SP kecil `SIS_WorkflowLog_QuotaInfo` (@ArticleWorkflowId, @BundleId):
mengembalikan QtyMasuk, QtySudah, Sisa. Endpoint GET di API (dipakai stasiun dan
halaman login saat form add/edit hasil terbuka).

## 4. API & Client

- Request add/update hasil (stasiun + Hasil Cutting): tambah field ConfirmExceed
  (default false), diteruskan ke SP.
- UI form add/edit hasil (step ber-bundle):
  - tampilkan baris info: "Masuk: {QtyMasuk} • Tercatat: {QtySudah} • Sisa: {Sisa}".
  - saat submit ditolak dengan pesan berprefix QTY_EXCEED| → tampilkan dialog
    konfirmasi berisi pesan tsb + "Yakin tetap simpan?" → jika ya, kirim ulang
    dengan ConfirmExceed = true.
- Pesan error lain tetap tampil seperti biasa.

## 5. Laporan (menambah modul Prompt 13)

### Tab baru "Selisih" di /report-bundle
- SP `SIS_Report_BundleVariance` (@ProjectId = NULL, @ArticleId = NULL):
  per bundle per step ber-bundle (mulai step ke-2): BundleNo, Serial, ArticleName,
  SizeName, StepName, QtyMasuk, QtyKeluar (ok + reject step ini), Selisih
  (QtyMasuk - QtyKeluar). Hanya baris Selisih <> 0; kelebihan tampil negatif.
- UI: filter Project/Artikel, tabel dengan badge merah (kurang) / kuning (lebih),
  ringkasan total selisih di atas.

### Laporan Progres (SIS_Report_ArticleProgress)
- Step non-bundle: progres = MIN(QtyOk / QtyTarget, 100%).
- Tambahan result set per artikel per size untuk step non-bundle:
  SizeName, QtyTarget, QtyOk, Surplus (QtyOk - QtyTarget, hanya jika > 0).
- UI: bar progres mentok 100%; jika ada surplus tampilkan badge
  "+{Surplus} pcs {SizeName}" di bawah baris step.

## Yang TIDAK boleh dilakukan

- Jangan blok qty yang KURANG dari batas.
- Jangan validasi qty step non-bundle terhadap pesanan.
- Jangan sentuh alur receive, scan publik, bundle, print.
- Jangan tambah tabel baru.

Setelah selesai: daftar file dibuat/diubah + script SQL manual
(alter_14_drop_rework.sql, SP yang diperbarui).

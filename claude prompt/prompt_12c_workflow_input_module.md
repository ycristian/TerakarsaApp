# Prompt 12c — Module Input Log Non-Bundle (WORKFLOW_INPUT)

## Konteks

Jalankan SETELAH Prompt 12b. Input log step non-bundle (cutting, dsb.) pindah dari stasiun ke UI login dengan module sendiri — karena pencatatnya supervisor/admin, bukan operator kiosk. Stasiun diramping jadi dua fungsi: scan bundle + menunggu diterima. Endpoint/SP log dari 12b DIPAKAI ULANG — prompt ini hanya module, halaman, dan perampingan.

## 1. Module & SQL

`sql/seed_workflow_input_module.sql` (idempotent, pola seed module yang ada):
- Code `WORKFLOW_INPUT`, Name "Hasil Cutting", Route `workflow-input`, icon cocok (mis. fe fe-scissors), penempatan grup & SortOrder bersebelahan dengan module Bundle.
- Assign otomatis ke semua user Role = Admin.

Catatan nama: label menu "Hasil Cutting" (bahasa lapangan), tapi halaman generik untuk SEMUA step requires_bundle = 0.

## 2. API

- Endpoint create log non-bundle & list log yang sudah ada dari 12b: pastikan bisa diakses via `RequireModule("WORKFLOW_INPUT")` (endpoint stasiun untuk ini dihapus — lihat bagian 4).
- Endpoint kecil baru bila belum ada: GET `api/articles/{articleId}/nonbundle-steps` → step hidup requires_bundle = 0 milik artikel + divisi step + **divisi step berikutnya** (untuk prefill tujuan).

## 3. Blazor Client — halaman `/workflow-input`

1. **Pemilih artikel**: pakai ulang pola dari `/bundles` (dropdown project → tabel artikel + pencarian lintas project). Ekstrak jadi komponen bersama (mis. `ArticlePicker.razor`) dan pakai di kedua halaman — jangan duplikasi markup.
2. Setelah artikel terpilih:
   - Daftar step non-bundle artikel (biasanya satu: Cutting). Kalau hanya satu, langsung terpilih.
   - **Form input**: size (dropdown, WAJIB), qty ok / reject print / reject fabric / reject sewing / rework (default 0), resource pencatat (dropdown resource divisi step, opsional), **divisi tujuan** (prefill divisi step berikutnya, bisa diganti, boleh kosong jika step terakhir), remark opsional. Simpan → tetap di form, size dipertahankan (input beruntun).
   - **Riwayat input** step itu: waktu, size, qty-qty, tujuan, badge "Diterima {waktu} oleh {nama}" / "Menunggu diterima", remark. Hapus: hanya Admin, alasan wajib (endpoint delete yang ada).
   - **Ringkasan per size**: total qty_ok tercatat vs qty order size (dari article_sizes) — kolom selisih.

## 4. Perampingan stasiun

- Hapus tab "Dikerjakan" beserta pemanggilan `SIS_Station_ActiveWork` dari halaman `/station` (SP-nya boleh dibiarkan, cukup tidak dipakai; endpoint `api/station/active-work` dan endpoint complete non-bundle stasiun DIHAPUS dari API).
- Halaman stasiun tersisa: panel Scan (default) + tab "Menunggu Diterima". Sesuaikan navigasi/tab.
- POST `api/station/complete` kini menolak step requires_bundle = 0 ('Step tanpa bundle dicatat lewat menu Hasil Cutting.') — validasi tambahan di API (SP sudah benar dari 12b, ini hanya pesan yang lebih jelas).

## Yang TIDAK boleh dilakukan

- Jangan ubah SIS_WorkflowLog_Manage atau aturan validasi 12b.
- Jangan sentuh alur scan bundle, terima, print.
- Jangan duplikasi pemilih artikel — wajib komponen bersama.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

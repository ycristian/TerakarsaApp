# Prompt 12 — Scan QR Bundle, Halaman /b/{serial}, Alur Per-Bundle

## Konteks

Bundle + label QR (isi: `{PublicBaseUrl}/b/{serial}`) sudah berjalan. Prompt ini menghidupkan alur per-bundle: scan QR jadi pintu masuk universal — sistem yang menentukan aksi (Terima / Selesaikan / info saja) berdasarkan posisi bundle. Prefix SP mengikuti repo: `SIS_`.

Aturan kepemilikan yang berlaku (sudah disepakati):
- Step ber-bundle PERTAMA (sort_order terkecil di antara step requires_bundle = 1 hidup milik artikel): tidak ada RECEIVED per bundle — penunjukan line saat pembuatan bundle menggantikannya (syarat: RECEIVED level artikel di step itu sudah ada). Yang boleh COMPLETED = resource yang ditunjuk di `bundles.resource_id`; jika bundle tidak punya resource, siapa pun di divisi step itu boleh.
- Step ber-bundle SELANJUTNYA: bundle wajib RECEIVED per bundle di step itu sebelum COMPLETED. Yang menerima = operator divisi step (siapa pun), dialah pemilik berikutnya.
- Satu bundle maksimal satu RECEIVED hidup + satu COMPLETED hidup per step.
- Aturan level artikel (bundle NULL) yang sudah ada TIDAK berubah.

## 1. Revisi SIS_WorkflowLog_Manage (CREATE)

Jadikan validasi sadar-bundle (pertahankan perilaku lama untuk @BundleId NULL):

1. Penolakan ganda: cek EXISTS per (article_workflow_id, [status]) **dengan filter bundle**: `AND ((@BundleId IS NULL AND bundle_id IS NULL) OR bundle_id = @BundleId)`.
2. COMPLETED dengan @BundleId:
   - Tentukan @FirstBundleSort = MIN(sort_order) step hidup requires_bundle = 1 milik artikel.
   - Jika step ini = @FirstBundleSort: wajib ada RECEIVED level artikel (bundle NULL) hidup di step ini; DAN jika `bundles.resource_id` IS NOT NULL maka @ResourceId harus sama dengannya — jika beda: RAISERROR 'Bundle ini ditugaskan ke line lain.'
   - Jika step ini > @FirstBundleSort: wajib ada RECEIVED hidup untuk (step ini, bundle ini).
3. RECEIVED dengan @BundleId: step sebelumnya (sort_order hidup tepat di bawah) harus punya COMPLETED hidup untuk bundle ini dengan target_division_id = division step ini; jika tidak: RAISERROR 'Bundle belum diserahkan ke divisi ini.'
4. Parameter baru @ActingDivisionId INT = NULL: jika diisi (dari station token) dan ≠ division_id step → RAISERROR 'Step ini bukan milik divisi Anda.'
5. Aturan lama tetap: qty non-negatif, bundle harus milik artikel, TargetDivisionId wajib untuk COMPLETED kecuali step terakhir, RECEIVED/COMPLETED level artikel seperti semula.

## 2. SP Baru

### SIS_Bundle_ScanInfo (@Serial, @DivisionId INT = NULL, @ResourceId INT = NULL)

Tiga result set:
1. **Info bundle**: bundle_id, bundle_no, serial, qty, size_name, article_id, article_name, style, color, project_name, line (resource bundle), status ringkas posisi: step & divisi terakhir + statusnya.
2. **Timeline**: semua log hidup bundle ini DIGABUNG log level artikel milik artikelnya (bundle NULL), urut sort_order + created_at: step, status, divisi, resource, qty, target divisi, waktu.
3. **Aksi** (dihitung di SP): kolom `allowed_action` ('RECEIVE' / 'COMPLETE' / 'NONE'), `action_article_workflow_id`, `message` (alasan bila NONE, mis. 'Menunggu diterima DTF — masih tanggung jawab QC' / 'Bundle ini ditugaskan ke Line 3' / 'Seluruh workflow selesai'). Logika mengikuti aturan kepemilikan di atas terhadap @DivisionId + @ResourceId; jika @DivisionId NULL (pengunjung tanpa token) → selalu NONE tanpa pesan negatif.

### SIS_Article_Wip (@ArticleId)

Per step artikel: step_name, sort_order, division_name, requires_bundle, jumlah bundle RECEIVED, jumlah bundle COMPLETED, total bundle artikel, total qty_ok COMPLETED. Untuk step level artikel: status RECEIVED/COMPLETED-nya. Dipakai di layar info scan dan jadi fondasi dashboard Prompt 13.

### Revisi SIS_Station_PendingReceives

Tambahkan item level bundle: bundle yang step sebelumnya COMPLETED bertarget divisi ini dan belum RECEIVED di step ini — kolom tambahan bundle_id, bundle_no, serial (NULL untuk item level artikel yang sudah ada).

## 3. API

### Stasiun ([RequireStationToken])
- GET `api/station/scan/{serial}` → SIS_Bundle_ScanInfo dengan @DivisionId dari token + @ResourceId dari query (operator sesi).
- POST `api/station/receive` dan `api/station/complete`: tambah field BundleId nullable di body; teruskan @ActingDivisionId dari token.

### Publik (tanpa autentikasi, read-only)
- GET `api/public/bundles/{serial}` → SIS_Bundle_ScanInfo (@DivisionId NULL) + SIS_Article_Wip. Hanya GET, tidak ada endpoint tulis publik.

## 4. Blazor Client

### Halaman `/station` — tambah panel Scan
1. Tombol besar **"Scan Bundle"** → kamera via JS interop (pakai library html5-qrcode dari file lokal di wwwroot/lib, bukan CDN) + input teks fallback (scanner USB / ketik serial). Ekstrak serial dari teks apa pun: bila berupa URL ambil segmen setelah `/b/`, selain itu anggap serial mentah.
2. Hasil scan → panggil `api/station/scan/{serial}` → tampilkan **kartu bundle**: No bundle besar, size, qty, artikel, posisi sekarang, timeline ringkas (5 terakhir, bisa diperluas).
3. Di bawah kartu, SATU tombol sesuai `allowed_action`: **Terima** (+ varian Terima dengan Catatan) atau **Selesaikan** (form qty + divisi tujuan yang sudah ada, kini membawa BundleId) atau tanpa tombol dengan `message` dari server.
4. Setelah aksi sukses → kembali ke mode scan (siap bundle berikutnya).
5. Tab "Menunggu Diterima": tampilkan juga item bundle (badge No bundle + serial), tetap bisa terima borongan multi-pilih.

### Halaman baru `/b/{serial}` (rute publik, tanpa layout sidebar)
- Jika localStorage punya station token → render komponen kartu-scan yang sama (aksi kontekstual aktif). Ekstrak komponen bersama, mis. `BundleScanCard.razor`.
- Tanpa token → read-only: kartu bundle + timeline lengkap + tabel WIP artikel (dari endpoint publik).

## Aturan tetap berlaku

Soft delete, filter deleted_at IS NULL, log immutable, UI bahasa Indonesia, layar sentuh (tombol besar) untuk stasiun.

## Yang TIDAK boleh dilakukan

- Jangan ubah skema tabel — semua kebutuhan terpenuhi kolom yang ada.
- Jangan buat dashboard lintas project — Prompt 13 (SIS_Article_Wip cukup per artikel).
- Jangan buat endpoint tulis tanpa autentikasi.
- Jangan ubah alur level artikel (cutting) yang sudah jalan.

Setelah selesai: daftar file yang dibuat/diubah + script SQL yang harus dijalankan manual.

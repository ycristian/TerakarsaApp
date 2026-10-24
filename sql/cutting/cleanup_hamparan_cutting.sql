/* =============================================================
   Hapus data PERCOBAAN hamparan Cutting (Prompt 78-80).

   Hard delete (bukan soft delete): ini data coba-coba, tidak boleh tertinggal
   di stok cutting / laporan mana pun.

   Yang dihapus (hanya yang berasal dari hamparan):
     1. print_jobs  job_type = 'CUTTING_BUNDLE_LABEL' milik bundle hamparan
     2. bundles     source  = 'CUTTING' (bundle manual TIDAK disentuh)
     3. spread_sizes + spreads

   PENGAMAN (script berhenti tanpa menghapus apa pun kalau kena):
     - ada bundle hamparan yang sudah PUNYA log workflow  -> sudah dipakai produksi
     - ada bundle hamparan berstatus TAKEN                 -> sudah diambil Bundling
   Kalau memang mau tetap dihapus, set @Paksa = 1.

   CATATAN: nomor serial bundle (B26-xxxxxx) yang sudah terpakai TIDAK
   dikembalikan -- serial dihitung dari MAX(serial) termasuk baris mati, jadi
   lompatan nomor memang perilaku normal sistem dan tidak merusak apa pun.
   Nomor urut hamparan (H01, H02, ...) dan numbering size dihitung ulang dari
   baris hidup, jadi setelah dihapus akan mulai lagi dari awal.
   ============================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ====== PILIH CAKUPAN ======
-- NULL = SEMUA hamparan. Isi salah satu kalau mau sebagian saja.
DECLARE @SpreadId  INT = NULL;   -- hapus satu hamparan saja (spreads.spread_id)
DECLARE @ArticleId INT = NULL;   -- hapus semua hamparan milik satu artikel
DECLARE @Paksa     BIT = 0;      -- 1 = abaikan pengaman di bawah

-- ---------- kumpulkan target ----------
DECLARE @Spreads TABLE (spread_id INT PRIMARY KEY);
INSERT INTO @Spreads (spread_id)
SELECT s.spread_id
FROM spreads s
WHERE (@SpreadId  IS NULL OR s.spread_id  = @SpreadId)
  AND (@ArticleId IS NULL OR s.article_id = @ArticleId);

DECLARE @Bundles TABLE (bundle_id INT PRIMARY KEY);
INSERT INTO @Bundles (bundle_id)
SELECT b.bundle_id
FROM bundles b
WHERE b.source = 'CUTTING'
  AND (
        b.spread_id IN (SELECT spread_id FROM @Spreads)
        -- bundle cutting yatim (hamparannya sudah hilang) ikut dibersihkan
        -- hanya kalau cakupannya SEMUA hamparan
        OR (@SpreadId IS NULL AND @ArticleId IS NULL AND b.spread_id IS NULL)
      );

-- ---------- pratinjau sebelum hapus ----------
PRINT '--- Yang akan dihapus ---';
SELECT 'spreads'      AS tabel, COUNT(*) AS baris FROM @Spreads
UNION ALL SELECT 'spread_sizes', COUNT(*) FROM spread_sizes WHERE spread_id IN (SELECT spread_id FROM @Spreads)
UNION ALL SELECT 'bundles CUTTING', COUNT(*) FROM @Bundles
UNION ALL SELECT 'print_jobs stiker cutting', COUNT(*) FROM print_jobs
          WHERE job_type = 'CUTTING_BUNDLE_LABEL' AND ref_id IN (SELECT bundle_id FROM @Bundles);

SELECT s.spread_id, p.project_name, a.article_name, s.spread_code, s.spread_date,
       s.set_count, s.sheets_per_set, s.[status],
       (SELECT COUNT(*) FROM bundles b WHERE b.spread_id = s.spread_id) AS jml_bundle
FROM spreads s
INNER JOIN articles a ON a.article_id = s.article_id
INNER JOIN projects p ON p.project_id = a.project_id
WHERE s.spread_id IN (SELECT spread_id FROM @Spreads)
ORDER BY s.spread_id;

IF NOT EXISTS (SELECT 1 FROM @Spreads) AND NOT EXISTS (SELECT 1 FROM @Bundles)
BEGIN
    PRINT 'Tidak ada data hamparan cutting. Tidak ada yang dibersihkan.';
    RETURN;
END

-- ---------- pengaman ----------
DECLARE @AdaLog INT = (SELECT COUNT(*) FROM article_workflow_logs
                       WHERE bundle_id IN (SELECT bundle_id FROM @Bundles));
DECLARE @AdaTaken INT = (SELECT COUNT(*) FROM bundles
                         WHERE bundle_id IN (SELECT bundle_id FROM @Bundles)
                           AND stock_status = 'TAKEN');

IF @Paksa = 0 AND (@AdaLog > 0 OR @AdaTaken > 0)
BEGIN
    PRINT '';
    PRINT '*** DIBATALKAN -- bukan sekadar data percobaan: ***';
    PRINT '    log workflow terkait : ' + CAST(@AdaLog AS VARCHAR(10));
    PRINT '    bundle sudah TAKEN   : ' + CAST(@AdaTaken AS VARCHAR(10));
    PRINT '    Set @Paksa = 1 kalau memang mau dihapus sekalian dengan lognya.';
    RETURN;
END

BEGIN TRAN;

-- 1. antrian cetak stiker (PENDING ikut dibatalkan supaya tidak jadi dicetak
--    ke printer TSC oleh TerakarsaApp.PrintService)
DELETE FROM print_jobs
WHERE job_type = 'CUTTING_BUNDLE_LABEL'
  AND ref_id IN (SELECT bundle_id FROM @Bundles);

-- 2. log workflow hasil Take (hanya ada kalau @Paksa = 1)
DELETE FROM article_workflow_logs
WHERE bundle_id IN (SELECT bundle_id FROM @Bundles);

-- 3. bundle hamparan (bundle manual tidak ikut -- filter source = 'CUTTING' di atas)
DELETE FROM bundles
WHERE bundle_id IN (SELECT bundle_id FROM @Bundles);

-- 4. rincian lalu header hamparan (urut FK)
DELETE FROM spread_sizes WHERE spread_id IN (SELECT spread_id FROM @Spreads);
DELETE FROM spreads      WHERE spread_id IN (SELECT spread_id FROM @Spreads);

COMMIT TRAN;

PRINT '';
PRINT 'Selesai.';
GO

-- ---------- verifikasi: sisa data hamparan ----------
SELECT 'spreads'                   AS tabel, COUNT(*) AS sisa FROM spreads
UNION ALL SELECT 'spread_sizes',            COUNT(*) FROM spread_sizes
UNION ALL SELECT 'bundles CUTTING',         COUNT(*) FROM bundles WHERE source = 'CUTTING'
UNION ALL SELECT 'bundles MANUAL (utuh)',   COUNT(*) FROM bundles WHERE source = 'MANUAL'
UNION ALL SELECT 'print_jobs stiker cutting', COUNT(*) FROM print_jobs WHERE job_type = 'CUTTING_BUNDLE_LABEL';
GO

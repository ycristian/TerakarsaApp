/* =============================================================
   Bersihkan data uji sql/cutting/test_78_79_cutting.sql (+ uji Prompt 80).

   HANYA menyentuh baris milik project uji 'UJI CUTTING 78-80' -- tidak ada PO
   produksi yang ikut. Hard delete (bukan soft delete): ini data uji, tidak boleh
   tertinggal di laporan mana pun.

   PENTING: print_jobs CUTTING_BUNDLE_LABEL dari hamparan uji dibatalkan DULU --
   statusnya PENDING, jadi kalau dibiarkan akan benar-benar dicetak oleh
   TerakarsaApp.PrintService ke printer TSC di lantai produksi.

   Serial bundle (bundle_serial_seq) yang terpakai TIDAK dikembalikan -- nomor urut
   serial dihitung dari MAX(serial) termasuk baris mati, jadi lompatan nomor memang
   perilaku normal sistem (lihat sp_Bundle_Manage.sql aturan #2) dan tidak merusak apa pun.
   ============================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @ProjectId INT = (SELECT project_id FROM projects WHERE project_name = 'UJI CUTTING 78-80');

IF @ProjectId IS NULL
BEGIN
    PRINT 'Tidak ada data uji. Tidak ada yang dibersihkan.';
    RETURN;
END

DECLARE @ArticleIds TABLE (article_id INT);
INSERT INTO @ArticleIds SELECT article_id FROM articles WHERE project_id = @ProjectId;

BEGIN TRAN;

-- 1. antrian cetak stiker uji (PENDING -> dibatalkan, bukan dibiarkan dicetak)
DELETE pj
FROM print_jobs pj
INNER JOIN bundles b ON b.bundle_id = pj.ref_id
WHERE pj.job_type = 'CUTTING_BUNDLE_LABEL'
  AND b.article_id IN (SELECT article_id FROM @ArticleIds);

-- 2. log workflow (bundling hasil Take + log cutting uji)
DELETE awl
FROM article_workflow_logs awl
INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
WHERE aw.article_id IN (SELECT article_id FROM @ArticleIds);

-- 3. bundle, lalu rincian & header hamparan (urut FK)
DELETE FROM bundles WHERE article_id IN (SELECT article_id FROM @ArticleIds);

DELETE ss
FROM spread_sizes ss
INNER JOIN spreads s ON s.spread_id = ss.spread_id
WHERE s.article_id IN (SELECT article_id FROM @ArticleIds);

DELETE FROM spreads WHERE article_id IN (SELECT article_id FROM @ArticleIds);

-- 4. workflow, size, artikel, project uji
DELETE FROM article_workflows WHERE article_id IN (SELECT article_id FROM @ArticleIds);
DELETE FROM article_sizes WHERE article_id IN (SELECT article_id FROM @ArticleIds);
DELETE FROM articles WHERE article_id IN (SELECT article_id FROM @ArticleIds);
DELETE FROM projects WHERE project_id = @ProjectId;

COMMIT TRAN;

-- ---------- verifikasi: semua harus 0 ----------
SELECT 'projects uji' AS sisa, COUNT(*) AS n FROM projects WHERE project_name = 'UJI CUTTING 78-80'
UNION ALL SELECT 'spreads', COUNT(*) FROM spreads
UNION ALL SELECT 'spread_sizes', COUNT(*) FROM spread_sizes
UNION ALL SELECT 'bundles CUTTING', COUNT(*) FROM bundles WHERE source = 'CUTTING'
UNION ALL SELECT 'print_jobs stiker cutting', COUNT(*) FROM print_jobs WHERE job_type = 'CUTTING_BUNDLE_LABEL';
GO

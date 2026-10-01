-- Prompt 55: fungsi saldo bersama -- pengganti aturan revisi berbasis waktu (jendela 1 jam,
-- H+1, "terkunci begitu diterima") yang dihapus dari SIS_WorkflowLog_Manage & SIS_Bundle_Manage.
--
-- SATU PRINSIP di semua pemanggil: perubahan ditolak HANYA kalau membuat saldo negatif DAN
-- memperburuk saldo dibanding sebelum perubahan. Perubahan yang menaikkan qty selalu lolos.
-- Ini penting karena data lama bisa SUDAH minus -- kalau guard-nya "saldo baru >= 0" polos,
-- baris seperti itu tidak akan pernah bisa dikoreksi sama sekali.
--
-- Kedua fungsi membaca keadaan DB APA ADANYA (sebelum perubahan). Pemanggil yang menghitung
-- "sesudah": ambil nilai fungsi, koreksi dengan selisih kontribusi baris yang sedang diubah/
-- dihapus, lalu bandingkan dengan nilai "sebelum".

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Step BER-BUNDLE: total keenam qty baris HIDUP bundle ini di step ber-bundle BERIKUTNYA
-- (sort_order terdekat di atas, requires_bundle = 1, hidup & aktif). 0 kalau step ini sudah
-- step ber-bundle terakhir.
-- Rumus ini SALINAN PERSIS validasi arah bawah yang sudah ada di SIS_SuperAdmin_Manage
-- EDIT_LOG/EDIT_BUNDLE (yang sengaja TIDAK di-refactor -- di luar cakupan Prompt 55). Kalau
-- definisi "total step berikutnya" berubah, sinkronkan manual di sp_SuperAdmin_Manage.sql juga.
-- Saldo step ini = SUM(qty_ok) baris hidup (step, bundle) - nilai fungsi ini.
CREATE OR ALTER FUNCTION dbo.SIS_fn_BundleNextStepTotal(@ArticleWorkflowId INT, @BundleId INT)
RETURNS INT
AS
BEGIN
    IF @ArticleWorkflowId IS NULL OR @BundleId IS NULL
        RETURN 0;

    DECLARE @ArticleId INT, @SortOrder INT;
    SELECT @ArticleId = article_id, @SortOrder = sort_order
    FROM article_workflows
    WHERE article_workflow_id = @ArticleWorkflowId;

    IF @ArticleId IS NULL
        RETURN 0;

    DECLARE @NextArticleWorkflowId INT;
    SELECT TOP 1 @NextArticleWorkflowId = article_workflow_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL
      AND requires_bundle = 1 AND sort_order > @SortOrder
    ORDER BY sort_order ASC;

    IF @NextArticleWorkflowId IS NULL
        RETURN 0;

    RETURN ISNULL((
        SELECT SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost)
        FROM article_workflow_logs
        WHERE article_workflow_id = @NextArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL
    ), 0);
END;
GO

-- Step NON-BUNDLE: SUM(qty_ok) baris hidup step itu untuk SIZE itu, dikurangi pemakaian hilir.
-- Pemakaian hilir dibaca dari step hidup BERIKUTNYA (sort_order terdekat di atas, jenis apa pun):
--   - step berikutnya non-bundle  -> total keenam qty step itu untuk size yang sama;
--   - step berikutnya ber-bundle  -> SUM(bundles.qty) bundle HIDUP artikel + size itu
--     (biasanya step Bundling: potongan Cutting "dipakai" begitu dibungkus jadi bundle).
-- Step terakhir artikel -> tidak ada pemakaian hilir, saldo = SUM(qty_ok).
CREATE OR ALTER FUNCTION dbo.SIS_fn_NonBundleSaldo(@ArticleWorkflowId INT, @ArticleSizeId INT)
RETURNS INT
AS
BEGIN
    IF @ArticleWorkflowId IS NULL OR @ArticleSizeId IS NULL
        RETURN 0;

    DECLARE @ArticleId INT, @SortOrder INT;
    SELECT @ArticleId = article_id, @SortOrder = sort_order
    FROM article_workflows
    WHERE article_workflow_id = @ArticleWorkflowId;

    IF @ArticleId IS NULL
        RETURN 0;

    DECLARE @Saldo INT = ISNULL((
        SELECT SUM(qty_ok)
        FROM article_workflow_logs
        WHERE article_workflow_id = @ArticleWorkflowId AND article_size_id = @ArticleSizeId AND deleted_at IS NULL
    ), 0);

    DECLARE @NextArticleWorkflowId INT, @NextRequiresBundle BIT;
    SELECT TOP 1 @NextArticleWorkflowId = article_workflow_id, @NextRequiresBundle = requires_bundle
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL
      AND sort_order > @SortOrder
    ORDER BY sort_order ASC;

    IF @NextArticleWorkflowId IS NULL
        RETURN @Saldo;

    IF @NextRequiresBundle = 0
        SET @Saldo = @Saldo - ISNULL((
            SELECT SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost)
            FROM article_workflow_logs
            WHERE article_workflow_id = @NextArticleWorkflowId AND article_size_id = @ArticleSizeId AND deleted_at IS NULL
        ), 0);
    ELSE
        SET @Saldo = @Saldo - ISNULL((
            SELECT SUM(qty)
            FROM bundles
            WHERE article_id = @ArticleId AND article_size_id = @ArticleSizeId AND deleted_at IS NULL
        ), 0);

    RETURN @Saldo;
END;
GO

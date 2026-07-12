-- WIP (work-in-progress) ringkas per step artikel — dipakai di layar info scan publik
-- (/b/{serial}, kartu "Progres Artikel"). Model 1-baris (Prompt 12b, tanpa kolom status).
-- Disederhanakan: per step hanya StepName+SortOrder, Diterima/Selesai dalam pcs bundle DAN
-- jumlah bundle (dibanding total pcs/jumlah bundle yang sudah terbentuk untuk artikel),
-- Qty Order (total order artikel), Qty OK dan Qty Reject step tsb.
--
-- PENTING soal arti received_at (lihat sp_WorkflowLog_Manage.sql @Action = 'RECEIVE'/'CREATE'):
-- baris log dibuat di article_workflow_id STEP SUMBER (yang baru selesai kerja), dengan
-- target_division_id = divisi step BERIKUTNYA. received_at pada baris itu terisi saat divisi
-- TUJUAN (step berikutnya) menerima. Jadi:
--   - Selesai step X   = ada baris log article_workflow_id = step X (bundle_id unik).
--   - Diterima step X  = baris log step SEBELUM X (bundle ber-bundle, sort_order < X)
--                        sudah received_at terisi -- BUKAN baris log step X sendiri.
-- Step ber-bundle pertama tidak punya step sebelumnya -> Diterima selalu 0 (tidak ada
-- konsep "menerima" untuk step asal pembuatan bundle).
-- Diterima/Selesai dihitung dari bundle_id UNIK yang tersentuh (DISTINCT) supaya baris
-- susulan (Prompt 14b, satu bundle bisa lebih dari satu baris log per step) tidak dihitung
-- dobel.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Article_Wip
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalBundlePcs INT = (
        SELECT ISNULL(SUM(qty), 0) FROM bundles WHERE article_id = @ArticleId AND deleted_at IS NULL
    );
    DECLARE @TotalBundleCount INT = (
        SELECT COUNT(*) FROM bundles WHERE article_id = @ArticleId AND deleted_at IS NULL
    );
    DECLARE @QtyOrder INT = (
        SELECT ISNULL(SUM(qty), 0) FROM article_sizes WHERE article_id = @ArticleId AND deleted_at IS NULL
    );

    SELECT
        aw.article_workflow_id AS ArticleWorkflowId,
        aw.step_name AS StepName,
        aw.sort_order AS SortOrder,
        aw.requires_bundle AS RequiresBundle,
        (
            SELECT ISNULL(SUM(b.qty), 0)
            FROM (
                SELECT DISTINCT bundle_id FROM article_workflow_logs
                WHERE article_workflow_id = aw.article_workflow_id AND bundle_id IS NOT NULL AND deleted_at IS NULL
            ) l
            INNER JOIN bundles b ON b.bundle_id = l.bundle_id
        ) AS CompletedPcs,
        (
            SELECT COUNT(*)
            FROM (
                SELECT DISTINCT bundle_id FROM article_workflow_logs
                WHERE article_workflow_id = aw.article_workflow_id AND bundle_id IS NOT NULL AND deleted_at IS NULL
            ) l
        ) AS CompletedBundleCount,
        (
            SELECT ISNULL(SUM(b.qty), 0)
            FROM (
                SELECT DISTINCT bundle_id FROM article_workflow_logs
                WHERE article_workflow_id = prevaw.article_workflow_id AND bundle_id IS NOT NULL
                  AND received_at IS NOT NULL AND deleted_at IS NULL
            ) l
            INNER JOIN bundles b ON b.bundle_id = l.bundle_id
        ) AS ReceivedPcs,
        (
            SELECT COUNT(*)
            FROM (
                SELECT DISTINCT bundle_id FROM article_workflow_logs
                WHERE article_workflow_id = prevaw.article_workflow_id AND bundle_id IS NOT NULL
                  AND received_at IS NOT NULL AND deleted_at IS NULL
            ) l
        ) AS ReceivedBundleCount,
        @TotalBundlePcs AS TotalBundlePcs,
        @TotalBundleCount AS TotalBundleCount,
        @QtyOrder AS QtyOrder,
        (
            SELECT ISNULL(SUM(qty_ok), 0) FROM article_workflow_logs
            WHERE article_workflow_id = aw.article_workflow_id AND deleted_at IS NULL
        ) AS QtyOk,
        (
            SELECT ISNULL(SUM(qty_reject_print + qty_reject_fabric + qty_reject_sewing), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = aw.article_workflow_id AND deleted_at IS NULL
        ) AS QtyReject
    FROM article_workflows aw
    OUTER APPLY (
        SELECT TOP 1 aw2.article_workflow_id
        FROM article_workflows aw2
        WHERE aw2.article_id = aw.article_id AND aw2.deleted_at IS NULL AND aw2.requires_bundle = 1
          AND aw2.sort_order < aw.sort_order
        ORDER BY aw2.sort_order DESC
    ) prevaw
    WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL
    ORDER BY aw.sort_order ASC;
END;
GO

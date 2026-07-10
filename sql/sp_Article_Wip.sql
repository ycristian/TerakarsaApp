-- WIP (work-in-progress) ringkas per step artikel — dipakai di layar info scan publik
-- (/b/{serial} tanpa token) dan fondasi dashboard Prompt 13.
-- Model 1-baris (Prompt 12b, tanpa kolom status):
--   - Step non-bundle: EntryCount (jumlah baris input), TotalQtyOkCompleted (SUM qty_ok),
--     rincian per size (SizeBreakdownJson, FOR JSON) karena baris non-bundle bebas
--     berulang dan tidak sekali pakai.
--   - Step ber-bundle: CompletedBundleCount (baris ada = "selesai"), ReceivedBundleCount
--     (baris ada + received_at terisi = "diterima"), TotalBundleCount, TotalQtyOkCompleted.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Article_Wip
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalBundles INT = (
        SELECT COUNT(*) FROM bundles WHERE article_id = @ArticleId AND deleted_at IS NULL
    );

    SELECT
        aw.article_workflow_id AS ArticleWorkflowId,
        aw.step_name AS StepName,
        aw.sort_order AS SortOrder,
        d.division_name AS DivisionName,
        aw.requires_bundle AS RequiresBundle,
        (
            SELECT COUNT(*) FROM article_workflow_logs
            WHERE article_workflow_id = aw.article_workflow_id AND bundle_id IS NOT NULL AND deleted_at IS NULL
        ) AS CompletedBundleCount,
        (
            SELECT COUNT(*) FROM article_workflow_logs
            WHERE article_workflow_id = aw.article_workflow_id AND bundle_id IS NOT NULL
              AND received_at IS NOT NULL AND deleted_at IS NULL
        ) AS ReceivedBundleCount,
        @TotalBundles AS TotalBundleCount,
        (
            SELECT ISNULL(SUM(qty_ok), 0) FROM article_workflow_logs
            WHERE article_workflow_id = aw.article_workflow_id AND deleted_at IS NULL
        ) AS TotalQtyOkCompleted,
        (
            SELECT COUNT(*) FROM article_workflow_logs
            WHERE article_workflow_id = aw.article_workflow_id AND bundle_id IS NULL AND deleted_at IS NULL
        ) AS EntryCount,
        (
            SELECT spd.size_name AS SizeName, SUM(awl.qty_ok) AS QtyOk
            FROM article_workflow_logs awl
            INNER JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
            INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
            WHERE awl.article_workflow_id = aw.article_workflow_id AND awl.bundle_id IS NULL AND awl.deleted_at IS NULL
            GROUP BY spd.size_name, spd.sort_order
            ORDER BY spd.sort_order
            FOR JSON PATH
        ) AS SizeBreakdownJson
    FROM article_workflows aw
    LEFT JOIN divisions d ON d.division_id = aw.division_id
    WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL
    ORDER BY aw.sort_order ASC;
END;
GO

-- Pengambilan data bundles (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete/reprint) ada di sp_Bundle_Manage.sql.
-- Dipakai di halaman "Kelola Bundle" (/articles/{articleId}/bundles).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Semua bundle hidup milik artikel, dengan status label terakhir (job print_jobs
-- hidup terbaru per bundle). Urut size sort_order, lalu bundle sort_order.
CREATE OR ALTER PROCEDURE SIS_Bundle_ListByArticle
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        b.bundle_id AS Id,
        b.article_id AS ArticleId,
        b.article_size_id AS ArticleSizeId,
        spd.size_name AS SizeName,
        spd.sort_order AS SizeSortOrder,
        b.serial AS Serial,
        b.bundle_no AS BundleNo,
        b.qty AS Qty,
        b.sort_order AS SortOrder,
        b.resource_id AS ResourceId,
        r.resource_name AS ResourceName,
        b.resource_person_name AS ResourcePersonName,
        pj.LabelStatus AS LabelStatus,
        pj.PrintedAt AS PrintedAt,
        b.created_at AS CreatedAt
    FROM bundles b
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = b.resource_id
    OUTER APPLY (
        SELECT TOP 1 pj2.[status] AS LabelStatus, pj2.printed_at AS PrintedAt
        FROM print_jobs pj2
        WHERE pj2.job_type = 'BUNDLE_LABEL' AND pj2.ref_id = b.bundle_id AND pj2.deleted_at IS NULL
        ORDER BY pj2.created_at DESC
    ) pj
    WHERE b.article_id = @ArticleId AND b.deleted_at IS NULL
    ORDER BY spd.sort_order ASC, b.sort_order ASC;
END;
GO

-- Ringkasan per size: qty order, saran bundle_qty, jumlah bundle, total qty bundle.
-- Plus flag: apakah step ber-bundle pertama artikel ini (requires_bundle = 1, sort_order
-- terkecil) sudah punya log RECEIVED hidup -- dipakai untuk banner peringatan cutting
-- belum dikonfirmasi diterima (tidak memblokir pembuatan bundle).
CREATE OR ALTER PROCEDURE SIS_Article_BundleSummary
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FirstBundleStepId INT, @FirstBundleStepDivisionId INT;
    SELECT TOP 1 @FirstBundleStepId = article_workflow_id, @FirstBundleStepDivisionId = division_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1
    ORDER BY sort_order ASC;

    DECLARE @HasFirstBundleStep BIT = CASE WHEN @FirstBundleStepId IS NULL THEN 0 ELSE 1 END;
    DECLARE @IsFirstBundleStepReceived BIT = CASE WHEN EXISTS (
        SELECT 1 FROM article_workflow_logs
        WHERE article_workflow_id = @FirstBundleStepId AND [status] = 'RECEIVED' AND deleted_at IS NULL
    ) THEN 1 ELSE 0 END;

    SELECT
        asz.article_size_id AS ArticleSizeId,
        spd.size_name AS SizeName,
        spd.sort_order AS SortOrder,
        asz.qty AS QtyOrder,
        asz.bundle_qty AS BundleQty,
        COUNT(b.bundle_id) AS BundleCount,
        ISNULL(SUM(b.qty), 0) AS TotalBundleQty,
        @HasFirstBundleStep AS HasFirstBundleStep,
        @IsFirstBundleStepReceived AS IsFirstBundleStepReceived,
        @FirstBundleStepDivisionId AS FirstBundleStepDivisionId
    FROM article_sizes asz
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN bundles b ON b.article_size_id = asz.article_size_id AND b.deleted_at IS NULL
    WHERE asz.article_id = @ArticleId AND asz.deleted_at IS NULL
    GROUP BY asz.article_size_id, spd.size_name, spd.sort_order, asz.qty, asz.bundle_qty
    ORDER BY spd.sort_order ASC;
END;
GO

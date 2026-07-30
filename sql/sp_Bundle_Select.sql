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
        p.bundle_letter AS BundleLetter,
        b.qty AS Qty,
        b.sort_order AS SortOrder,
        b.resource_id AS ResourceId,
        r.resource_name AS ResourceName,
        b.remarks AS Remarks,
        pj.LabelStatus AS LabelStatus,
        pj.PrintedAt AS PrintedAt,
        b.created_at AS CreatedAt,
        b.employee_id AS EmployeeId,
        e.employee_name AS EmployeeName
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = b.resource_id
    LEFT JOIN employees e ON e.employee_id = b.employee_id AND e.deleted_at IS NULL
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
-- terkecil -- sejak Prompt 17 ini SELALU step Bundling implisit) sudah punya log RECEIVED
-- hidup -- dipakai untuk banner peringatan cutting belum dikonfirmasi diterima (tidak
-- memblokir pembuatan bundle). Bundling-lah penerima hasil cutting sekarang (auto-receive
-- di SIS_Bundle_Manage CREATE), jadi flag ini pada dasarnya sudah menjawab pertanyaan yang
-- sama seperti sebelum Prompt 17, tanpa perlu logika tambahan.
-- Prompt 17: FirstBundleStepDivisionId TIDAK LAGI berarti divisi step Bundling -- field ini
-- dipakai client untuk dropdown "Penjahit (resource)" di BundleManager.razor, yaitu resource
-- divisi STATION ber-bundle pertama (mis. Sewing, is_bundling = 0), bukan divisi Bundling.
-- BundlingDivisionId (baru) dipakai untuk dropdown terpisah "Pelaksana Bundling".
-- StockCutting (baru): total qty step non-bundle TERAKHIR (mis. Cutting) yang sudah DITERIMA
-- divisi Bundling untuk size ini, dikurangi total qty bundle yang sudah dibuat dari size ini --
-- sisa hasil potong yang belum dijadikan bundle. Definisi step sumbernya SAMA dengan
-- @LastNonBundleStepId di SIS_Bundle_Manage CREATE (step requires_bundle = 0 dengan sort_order
-- terbesar). Dipakai station "Buat Bundle" (StationDevice.razor) menggantikan "Saran Bundle
-- Qty" (asz.bundle_qty, tetap dipertahankan sebagai kolom BundleQty untuk BundleManager.razor).
CREATE OR ALTER PROCEDURE SIS_Article_BundleSummary
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FirstBundleStepId INT;
    SELECT TOP 1 @FirstBundleStepId = article_workflow_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1
    ORDER BY sort_order ASC;

    DECLARE @HasFirstBundleStep BIT = CASE WHEN @FirstBundleStepId IS NULL THEN 0 ELSE 1 END;
    DECLARE @IsFirstBundleStepReceived BIT = CASE WHEN EXISTS (
        SELECT 1 FROM article_workflow_logs
        WHERE article_workflow_id = @FirstBundleStepId AND received_at IS NOT NULL AND deleted_at IS NULL
    ) THEN 1 ELSE 0 END;

    DECLARE @FirstStationBundleDivisionId INT;
    SELECT TOP 1 @FirstStationBundleDivisionId = division_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1 AND is_bundling = 0
    ORDER BY sort_order ASC;

    DECLARE @BundlingDivisionId INT;
    SELECT @BundlingDivisionId = division_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

    DECLARE @LastNonBundleStepId INT;
    SELECT TOP 1 @LastNonBundleStepId = article_workflow_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 0
    ORDER BY sort_order DESC;

    SELECT
        asz.article_size_id AS ArticleSizeId,
        spd.size_name AS SizeName,
        spd.sort_order AS SortOrder,
        asz.qty AS QtyOrder,
        asz.bundle_qty AS BundleQty,
        COUNT(b.bundle_id) AS BundleCount,
        ISNULL(SUM(b.qty), 0) AS TotalBundleQty,
        ISNULL((
            SELECT SUM(awl.qty_ok)
            FROM article_workflow_logs awl
            WHERE awl.article_workflow_id = @LastNonBundleStepId
              AND awl.article_size_id = asz.article_size_id
              AND awl.deleted_at IS NULL
              AND awl.received_at IS NOT NULL
        ), 0) - ISNULL(SUM(b.qty), 0) AS StockCutting,
        @HasFirstBundleStep AS HasFirstBundleStep,
        @IsFirstBundleStepReceived AS IsFirstBundleStepReceived,
        @FirstStationBundleDivisionId AS FirstBundleStepDivisionId,
        @BundlingDivisionId AS BundlingDivisionId
    FROM article_sizes asz
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN bundles b ON b.article_size_id = asz.article_size_id AND b.deleted_at IS NULL
    WHERE asz.article_id = @ArticleId AND asz.deleted_at IS NULL
    GROUP BY asz.article_size_id, spd.size_name, spd.sort_order, asz.qty, asz.bundle_qty
    ORDER BY spd.sort_order ASC;
END;
GO

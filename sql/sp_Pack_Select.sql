-- Pengambilan data packs/pack_items (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update_plan/confirm/delete/reprint) ada di sp_Pack_Manage.sql.
--
-- Stok tersedia (dipakai di CREATE/UPDATE_PLAN/CONFIRM sp_Pack_Manage.sql juga, logika
-- diulang di sana karena T-SQL tidak punya CTE yang bisa dipakai lintas statement) =
-- qty_ok log hidup STEP TERAKHIR artikel (sort_order terbesar milik artikel itu SENDIRI,
-- bukan global lintas artikel) dikurangi Σ COALESCE(qty_actual, qty_plan) pack_items hidup
-- untuk (artikel, size) yang sama. Size baris log direktori artikel bundle_id NULL ada
-- langsung di article_size_id; baris ber-bundle article_size_id NULL, size-nya diambil dari
-- bundles.article_size_id lewat bundle_id (pola sama seperti sp_Article_Wip.sql).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Pack_StockAvailable
    @ProjectId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH LastStep AS (
        SELECT a.article_id,
               (SELECT TOP 1 aw.article_workflow_id
                FROM article_workflows aw
                WHERE aw.article_id = a.article_id AND aw.deleted_at IS NULL AND aw.inactive_at IS NULL
                ORDER BY aw.sort_order DESC) AS LastStepId
        FROM articles a
        WHERE a.project_id = @ProjectId AND a.deleted_at IS NULL
    ),
    Done AS (
        SELECT ls.article_id AS ArticleId,
               COALESCE(awl.article_size_id, b.article_size_id) AS ArticleSizeId,
               SUM(awl.qty_ok) AS QtyDone
        FROM LastStep ls
        INNER JOIN article_workflow_logs awl ON awl.article_workflow_id = ls.LastStepId AND awl.deleted_at IS NULL
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
        GROUP BY ls.article_id, COALESCE(awl.article_size_id, b.article_size_id)
    ),
    Packed AS (
        SELECT pi.article_id AS ArticleId, pi.article_size_id AS ArticleSizeId,
               SUM(COALESCE(pi.qty_actual, pi.qty_plan)) AS QtyPacked
        FROM pack_items pi
        INNER JOIN packs p ON p.pack_id = pi.pack_id AND p.deleted_at IS NULL
        WHERE pi.deleted_at IS NULL AND p.project_id = @ProjectId
        GROUP BY pi.article_id, pi.article_size_id
    )
    SELECT
        a.article_id AS ArticleId,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        asz.article_size_id AS ArticleSizeId,
        spd.size_name AS SizeName,
        spd.sort_order AS SortOrder,
        ISNULL(d.QtyDone, 0) AS QtyDone,
        ISNULL(pk.QtyPacked, 0) AS QtyPacked,
        ISNULL(d.QtyDone, 0) - ISNULL(pk.QtyPacked, 0) AS QtyAvailable
    FROM article_sizes asz
    INNER JOIN articles a ON a.article_id = asz.article_id AND a.deleted_at IS NULL
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN Done d ON d.ArticleId = a.article_id AND d.ArticleSizeId = asz.article_size_id
    LEFT JOIN Packed pk ON pk.ArticleId = a.article_id AND pk.ArticleSizeId = asz.article_size_id
    WHERE a.project_id = @ProjectId AND asz.deleted_at IS NULL
    ORDER BY a.article_name ASC, spd.sort_order ASC;
END;
GO

-- Result set 1: pack hidup + agregat. Result set 2: seluruh items dari pack-pack itu.
CREATE OR ALTER PROCEDURE SIS_Pack_ListByProject
    @ProjectId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.pack_id AS Id,
        p.pack_no AS PackNo,
        p.serial AS Serial,
        (SELECT COUNT(DISTINCT pi.article_id) FROM pack_items pi WHERE pi.pack_id = p.pack_id AND pi.deleted_at IS NULL) AS ArticleCount,
        ISNULL((SELECT SUM(pi.qty_plan) FROM pack_items pi WHERE pi.pack_id = p.pack_id AND pi.deleted_at IS NULL), 0) AS TotalPlan,
        ISNULL((SELECT SUM(ISNULL(pi.qty_actual, 0)) FROM pack_items pi WHERE pi.pack_id = p.pack_id AND pi.deleted_at IS NULL), 0) AS TotalActual,
        CASE WHEN EXISTS (SELECT 1 FROM pack_items pi WHERE pi.pack_id = p.pack_id AND pi.deleted_at IS NULL)
              AND NOT EXISTS (SELECT 1 FROM pack_items pi WHERE pi.pack_id = p.pack_id AND pi.deleted_at IS NULL AND pi.qty_actual IS NULL)
             THEN 1 ELSE 0 END AS IsConfirmed,
        pj.LabelStatus AS LabelStatus,
        pj.PrintedAt AS PrintedAt,
        p.created_at AS CreatedAt
    FROM packs p
    OUTER APPLY (
        SELECT TOP 1 pj2.[status] AS LabelStatus, pj2.printed_at AS PrintedAt
        FROM print_jobs pj2
        WHERE pj2.job_type = 'PACK_LABEL' AND pj2.ref_id = p.pack_id AND pj2.deleted_at IS NULL
        ORDER BY pj2.created_at DESC
    ) pj
    WHERE p.project_id = @ProjectId AND p.deleted_at IS NULL
    ORDER BY p.pack_no ASC;

    SELECT
        pi.pack_item_id AS PackItemId,
        pi.pack_id AS PackId,
        pi.article_id AS ArticleId,
        pi.article_size_id AS ArticleSizeId,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        spd.size_name AS SizeName,
        pi.qty_plan AS QtyPlan,
        pi.qty_actual AS QtyActual
    FROM pack_items pi
    INNER JOIN packs p ON p.pack_id = pi.pack_id
    INNER JOIN articles a ON a.article_id = pi.article_id
    INNER JOIN article_sizes asz ON asz.article_size_id = pi.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE p.project_id = @ProjectId AND p.deleted_at IS NULL AND pi.deleted_at IS NULL
    ORDER BY pi.pack_id ASC, a.article_name ASC, spd.sort_order ASC;
END;
GO

-- Pintu masuk "scan QR karung" -- /station panel & halaman publik /pack/{serial}.
CREATE OR ALTER PROCEDURE SIS_Pack_ScanInfo
    @Serial VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PackId INT, @ProjectId INT;
    SELECT @PackId = pack_id, @ProjectId = project_id
    FROM packs WHERE serial = @Serial AND deleted_at IS NULL;

    IF @PackId IS NULL
    BEGIN
        RAISERROR('Karung tidak ditemukan.', 16, 1);
        RETURN;
    END

    DECLARE @TotalPacks INT = (SELECT COUNT(*) FROM packs WHERE project_id = @ProjectId AND deleted_at IS NULL);
    DECLARE @HasItems BIT = CASE WHEN EXISTS (SELECT 1 FROM pack_items WHERE pack_id = @PackId AND deleted_at IS NULL) THEN 1 ELSE 0 END;
    DECLARE @IsConfirmed BIT = CASE WHEN @HasItems = 1 AND NOT EXISTS (
        SELECT 1 FROM pack_items WHERE pack_id = @PackId AND deleted_at IS NULL AND qty_actual IS NULL
    ) THEN 1 ELSE 0 END;

    -- 1. Info pack
    SELECT
        p.pack_id AS PackId,
        p.pack_no AS PackNo,
        p.serial AS Serial,
        pr.project_name AS ProjectName,
        @TotalPacks AS TotalPacks,
        ISNULL((SELECT SUM(COALESCE(pi.qty_actual, pi.qty_plan)) FROM pack_items pi WHERE pi.pack_id = p.pack_id AND pi.deleted_at IS NULL), 0) AS TotalQty,
        @IsConfirmed AS IsConfirmed,
        p.created_at AS CreatedAt
    FROM packs p
    INNER JOIN projects pr ON pr.project_id = p.project_id
    WHERE p.pack_id = @PackId;

    -- 2. Items
    SELECT
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        spd.size_name AS SizeName,
        pi.qty_plan AS QtyPlan,
        pi.qty_actual AS QtyActual
    FROM pack_items pi
    INNER JOIN articles a ON a.article_id = pi.article_id
    INNER JOIN article_sizes asz ON asz.article_size_id = pi.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE pi.pack_id = @PackId AND pi.deleted_at IS NULL
    ORDER BY a.article_name ASC, spd.sort_order ASC;
END;
GO

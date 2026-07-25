-- Pengambilan data projects (SELECT saja, tidak menyentuh data).
-- INNER JOIN buyers (customer_id, wajib diisi), LEFT JOIN employees 2x (project_md/project_pic, nullable).
-- Mutasi (create/update/delete/set_status) ada di sp_Project_Manage.sql (SIS_Project_Manage).
--
-- Fix: ProgressPercent -- % progress project (SIS_Project_GetAll LIST & SIS_Project_GetById),
-- dihitung PER SIZE lalu digabung, BUKAN total bundle / total order mentah. Alasan: kalau satu
-- size over-produced (surplus) dan size lain under-produced (kurang), rasio total bisa
-- kelihatan 100% padahal sebenarnya belum lengkap (mis. order S10/M10, bundle S12/M8 -> total
-- 20/20 = 100% padahal M kurang 2). Per size: CappedQty = MIN(SUM(bundles.qty size itu),
-- article_sizes.qty order size itu) -- surplus di satu size TIDAK menutupi kekurangan size
-- lain. ProgressPercent = SUM(CappedQty semua size) / SUM(OrderQty semua size) * 100 --
-- otomatis tidak akan pernah > 100% karena tiap suku sudah dibatasi order-nya sendiri.
--
-- Prompt 18 -- derived_status: manual_status TIDAK PERNAH disimpan untuk status otomatis --
-- diturunkan di sini setiap kali dibaca lewat CROSS APPLY (satu sumber kebenaran, tidak bisa
-- basi). Kalau manual_status terisi (ON_HOLD/COMPLETED/CANCELLED), itulah derived_status.
-- Kalau NULL: ON_GOING bila artikel project ini punya log workflow hidup; kalau belum
-- ada log tapi start_date sudah tiba/lewat (<= hari ini), STARTED (Dimulai -- project sudah
-- boleh jalan, kartu input non-bundle & Buat Bundle di station mulai muncul, lihat
-- SIS_Station_ActiveWork di sp_Station_Operations.sql); selain itu NOT_STARTED.
-- @Status (opsional) memfilter berdasarkan derived_status ini, bukan kolom mentah. @Status
-- NULL ("Semua" -- juga default awal halaman) TIDAK berarti tanpa filter -- tetap
-- menyembunyikan COMPLETED/CANCELLED (hanya NOT_STARTED/STARTED/ON_GOING/ON_HOLD)
-- supaya project selesai/batal tidak membanjiri daftar; harus pilih status itu secara
-- eksplisit lewat dropdown utk melihatnya.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Project_GetAll
    @Action        VARCHAR(10) = 'LIST',  -- LIST atau COUNT
    @SearchTerm    VARCHAR(150) = NULL,
    @Status        VARCHAR(20) = NULL,    -- filter derived_status: NOT_STARTED/STARTED/ON_GOING/ON_HOLD/COMPLETED/CANCELLED
    @PageNumber    INT = 1,
    @PageSize      INT = 10,
    @SortColumn    VARCHAR(50) = NULL,
    @SortDirection VARCHAR(4) = 'asc'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'COUNT'
    BEGIN
        SELECT COUNT(*) AS TotalCount
        FROM projects p
        INNER JOIN buyers b ON b.buyer_id = p.customer_id
        CROSS APPLY (
            SELECT CASE WHEN p.manual_status IS NOT NULL THEN p.manual_status
                        WHEN EXISTS (SELECT 1 FROM article_workflow_logs awl
                                     INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
                                     INNER JOIN articles a ON a.article_id = aw.article_id
                                     WHERE a.project_id = p.project_id
                                       AND awl.deleted_at IS NULL AND aw.deleted_at IS NULL AND a.deleted_at IS NULL)
                        THEN 'ON_GOING'
                        WHEN p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE)
                        THEN 'STARTED' ELSE 'NOT_STARTED' END AS DerivedStatus
        ) ds
        WHERE p.deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR p.project_name LIKE '%' + @SearchTerm + '%'
               OR p.no_po LIKE '%' + @SearchTerm + '%'
               OR b.buyer_name LIKE '%' + @SearchTerm + '%')
          AND (
                (@Status IS NOT NULL AND ds.DerivedStatus = @Status)
                OR (@Status IS NULL AND ds.DerivedStatus IN ('NOT_STARTED', 'STARTED', 'ON_GOING', 'ON_HOLD'))
              );
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'ProjectName' THEN 'p.project_name'
            WHEN 'BuyerName' THEN 'b.buyer_name'
            WHEN 'NoPo' THEN 'p.no_po'
            WHEN 'OrderDate' THEN 'p.order_date'
            WHEN 'Deadline' THEN 'p.deadline'
            WHEN 'CreatedAt' THEN 'p.created_at'
            ELSE 'p.project_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'p.project_id' THEN '' ELSE ', p.project_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT p.project_id AS Id,
                   p.customer_id AS CustomerId, b.buyer_name AS BuyerName,
                   p.project_md AS ProjectMd, md.employee_name AS ProjectMdName,
                   p.project_pic AS ProjectPic, pic.employee_name AS ProjectPicName,
                   p.project_name AS ProjectName, p.no_po AS NoPo,
                   p.material_name AS MaterialName,
                   p.order_date AS OrderDate, p.[start_date] AS StartDate,
                   p.deadline AS Deadline, p.delivery_date AS DeliveryDate,
                   p.remarks AS Remarks, p.is_urgent AS IsUrgent,
                   ds.DerivedStatus AS DerivedStatus,
                   p.status_reason AS StatusReason, p.status_changed_at AS StatusChangedAt,
                   su.FullName AS StatusChangedByName,
                   p.created_at AS CreatedAt, p.created_by AS CreatedBy,
                   p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy,
                   ISNULL(prog.ProgressPercent, 0) AS ProgressPercent
            FROM projects p
            INNER JOIN buyers b ON b.buyer_id = p.customer_id
            LEFT JOIN employees md ON md.employee_id = p.project_md
            LEFT JOIN employees pic ON pic.employee_id = p.project_pic
            LEFT JOIN Users su ON su.Id = p.status_changed_by
            CROSS APPLY (
                SELECT CASE WHEN p.manual_status IS NOT NULL THEN p.manual_status
                            WHEN EXISTS (SELECT 1 FROM article_workflow_logs awl
                                         INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
                                         INNER JOIN articles a ON a.article_id = aw.article_id
                                         WHERE a.project_id = p.project_id
                                           AND awl.deleted_at IS NULL AND aw.deleted_at IS NULL AND a.deleted_at IS NULL)
                            THEN ''ON_GOING''
                            WHEN p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE)
                            THEN ''STARTED'' ELSE ''NOT_STARTED'' END AS DerivedStatus
            ) ds
            OUTER APPLY (
                SELECT CASE WHEN SUM(sz.OrderQty) > 0
                            THEN CAST(ROUND(100.0 * SUM(sz.CappedQty) / SUM(sz.OrderQty), 1) AS FLOAT)
                            ELSE CAST(0 AS FLOAT) END AS ProgressPercent
                FROM (
                    SELECT asz.article_size_id, asz.qty AS OrderQty,
                           CASE WHEN ISNULL(bq.BundleQty, 0) > asz.qty THEN asz.qty ELSE ISNULL(bq.BundleQty, 0) END AS CappedQty
                    FROM article_sizes asz
                    INNER JOIN articles a2 ON a2.article_id = asz.article_id AND a2.deleted_at IS NULL
                    OUTER APPLY (
                        SELECT SUM(bnd.qty) AS BundleQty FROM bundles bnd
                        WHERE bnd.article_size_id = asz.article_size_id AND bnd.deleted_at IS NULL
                    ) bq
                    WHERE a2.project_id = p.project_id AND asz.deleted_at IS NULL
                ) sz
            ) prog
            WHERE p.deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR p.project_name LIKE ''%'' + @SearchTerm + ''%''
                   OR p.no_po LIKE ''%'' + @SearchTerm + ''%''
                   OR b.buyer_name LIKE ''%'' + @SearchTerm + ''%'')
              AND (
                    (@Status IS NOT NULL AND ds.DerivedStatus = @Status)
                    OR (@Status IS NULL AND ds.DerivedStatus IN (''NOT_STARTED'', ''STARTED'', ''ON_GOING'', ''ON_HOLD''))
                  )
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @Status VARCHAR(20), @PageNumber INT, @PageSize INT',
            @SearchTerm, @Status, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_Project_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.project_id AS Id,
           p.customer_id AS CustomerId, b.buyer_name AS BuyerName,
           p.project_md AS ProjectMd, md.employee_name AS ProjectMdName,
           p.project_pic AS ProjectPic, pic.employee_name AS ProjectPicName,
           p.project_name AS ProjectName, p.no_po AS NoPo,
           p.material_name AS MaterialName,
           p.order_date AS OrderDate, p.[start_date] AS StartDate,
           p.deadline AS Deadline, p.delivery_date AS DeliveryDate,
           p.remarks AS Remarks, p.is_urgent AS IsUrgent,
           CASE WHEN p.manual_status IS NOT NULL THEN p.manual_status
                WHEN EXISTS (SELECT 1 FROM article_workflow_logs awl
                             INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
                             INNER JOIN articles a ON a.article_id = aw.article_id
                             WHERE a.project_id = p.project_id
                               AND awl.deleted_at IS NULL AND aw.deleted_at IS NULL AND a.deleted_at IS NULL)
                THEN 'ON_GOING'
                WHEN p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE)
                THEN 'STARTED' ELSE 'NOT_STARTED' END AS DerivedStatus,
           p.status_reason AS StatusReason, p.status_changed_at AS StatusChangedAt,
           su.FullName AS StatusChangedByName,
           p.created_at AS CreatedAt, p.created_by AS CreatedBy,
           p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy,
           ISNULL(prog.ProgressPercent, 0) AS ProgressPercent
    FROM projects p
    INNER JOIN buyers b ON b.buyer_id = p.customer_id
    LEFT JOIN employees md ON md.employee_id = p.project_md
    LEFT JOIN employees pic ON pic.employee_id = p.project_pic
    LEFT JOIN Users su ON su.Id = p.status_changed_by
    OUTER APPLY (
        SELECT CASE WHEN SUM(sz.OrderQty) > 0
                    THEN CAST(ROUND(100.0 * SUM(sz.CappedQty) / SUM(sz.OrderQty), 1) AS FLOAT)
                    ELSE CAST(0 AS FLOAT) END AS ProgressPercent
        FROM (
            SELECT asz.article_size_id, asz.qty AS OrderQty,
                   CASE WHEN ISNULL(bq.BundleQty, 0) > asz.qty THEN asz.qty ELSE ISNULL(bq.BundleQty, 0) END AS CappedQty
            FROM article_sizes asz
            INNER JOIN articles a2 ON a2.article_id = asz.article_id AND a2.deleted_at IS NULL
            OUTER APPLY (
                SELECT SUM(bnd.qty) AS BundleQty FROM bundles bnd
                WHERE bnd.article_size_id = asz.article_size_id AND bnd.deleted_at IS NULL
            ) bq
            WHERE a2.project_id = p.project_id AND asz.deleted_at IS NULL
        ) sz
    ) prog
    WHERE p.project_id = @Id AND p.deleted_at IS NULL;
END;
GO

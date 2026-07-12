-- Pengambilan data projects (SELECT saja, tidak menyentuh data).
-- INNER JOIN buyers (customer_id, wajib diisi), LEFT JOIN employees 2x (project_md/project_pic, nullable).
-- Mutasi (create/update/delete/set_status) ada di sp_Project_Manage.sql (SIS_Project_Manage).
--
-- Prompt 18 -- derived_status: manual_status TIDAK PERNAH disimpan untuk status otomatis --
-- diturunkan di sini setiap kali dibaca lewat CROSS APPLY (satu sumber kebenaran, tidak bisa
-- basi). Kalau manual_status terisi (ON_HOLD/COMPLETED/CANCELLED), itulah derived_status.
-- Kalau NULL: ON_GOING bila artikel project ini punya log workflow hidup, selain itu
-- NOT_STARTED. @Status (opsional) memfilter berdasarkan derived_status ini, bukan kolom
-- mentah. @Status NULL ("Semua" -- juga default awal halaman) TIDAK berarti tanpa filter --
-- tetap menyembunyikan COMPLETED/CANCELLED (hanya NOT_STARTED/ON_GOING/ON_HOLD) supaya
-- project selesai/batal tidak membanjiri daftar; harus pilih status itu secara eksplisit
-- lewat dropdown utk melihatnya.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Project_GetAll
    @Action        VARCHAR(10) = 'LIST',  -- LIST atau COUNT
    @SearchTerm    VARCHAR(150) = NULL,
    @Status        VARCHAR(20) = NULL,    -- filter derived_status: NOT_STARTED/ON_GOING/ON_HOLD/COMPLETED/CANCELLED
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
                        THEN 'ON_GOING' ELSE 'NOT_STARTED' END AS DerivedStatus
        ) ds
        WHERE p.deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR p.project_name LIKE '%' + @SearchTerm + '%'
               OR p.no_po LIKE '%' + @SearchTerm + '%'
               OR b.buyer_name LIKE '%' + @SearchTerm + '%')
          AND (
                (@Status IS NOT NULL AND ds.DerivedStatus = @Status)
                OR (@Status IS NULL AND ds.DerivedStatus IN ('NOT_STARTED', 'ON_GOING', 'ON_HOLD'))
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
                   ds.DerivedStatus AS DerivedStatus,
                   p.status_reason AS StatusReason, p.status_changed_at AS StatusChangedAt,
                   su.FullName AS StatusChangedByName,
                   p.created_at AS CreatedAt, p.created_by AS CreatedBy,
                   p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy
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
                            THEN ''ON_GOING'' ELSE ''NOT_STARTED'' END AS DerivedStatus
            ) ds
            WHERE p.deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR p.project_name LIKE ''%'' + @SearchTerm + ''%''
                   OR p.no_po LIKE ''%'' + @SearchTerm + ''%''
                   OR b.buyer_name LIKE ''%'' + @SearchTerm + ''%'')
              AND (
                    (@Status IS NOT NULL AND ds.DerivedStatus = @Status)
                    OR (@Status IS NULL AND ds.DerivedStatus IN (''NOT_STARTED'', ''ON_GOING'', ''ON_HOLD''))
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
           CASE WHEN p.manual_status IS NOT NULL THEN p.manual_status
                WHEN EXISTS (SELECT 1 FROM article_workflow_logs awl
                             INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
                             INNER JOIN articles a ON a.article_id = aw.article_id
                             WHERE a.project_id = p.project_id
                               AND awl.deleted_at IS NULL AND aw.deleted_at IS NULL AND a.deleted_at IS NULL)
                THEN 'ON_GOING' ELSE 'NOT_STARTED' END AS DerivedStatus,
           p.status_reason AS StatusReason, p.status_changed_at AS StatusChangedAt,
           su.FullName AS StatusChangedByName,
           p.created_at AS CreatedAt, p.created_by AS CreatedBy,
           p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy
    FROM projects p
    INNER JOIN buyers b ON b.buyer_id = p.customer_id
    LEFT JOIN employees md ON md.employee_id = p.project_md
    LEFT JOIN employees pic ON pic.employee_id = p.project_pic
    LEFT JOIN Users su ON su.Id = p.status_changed_by
    WHERE p.project_id = @Id AND p.deleted_at IS NULL;
END;
GO

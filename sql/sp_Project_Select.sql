-- Pengambilan data projects (SELECT saja, tidak menyentuh data).
-- INNER JOIN buyers (customer_id, wajib diisi), LEFT JOIN employees 2x (project_md/project_pic, nullable).
-- Mutasi (create/update/delete) ada di sp_Project_Manage.sql (SIS_Project_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Project_GetAll
    @Action        VARCHAR(10) = 'LIST',  -- LIST atau COUNT
    @SearchTerm    VARCHAR(150) = NULL,
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
        WHERE p.deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR p.project_name LIKE '%' + @SearchTerm + '%'
               OR p.no_po LIKE '%' + @SearchTerm + '%'
               OR b.buyer_name LIKE '%' + @SearchTerm + '%');
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
                   p.order_date AS OrderDate, p.[start_date] AS StartDate,
                   p.deadline AS Deadline, p.delivery_date AS DeliveryDate,
                   p.created_at AS CreatedAt, p.created_by AS CreatedBy,
                   p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy
            FROM projects p
            INNER JOIN buyers b ON b.buyer_id = p.customer_id
            LEFT JOIN employees md ON md.employee_id = p.project_md
            LEFT JOIN employees pic ON pic.employee_id = p.project_pic
            WHERE p.deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR p.project_name LIKE ''%'' + @SearchTerm + ''%''
                   OR p.no_po LIKE ''%'' + @SearchTerm + ''%''
                   OR b.buyer_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
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
           p.order_date AS OrderDate, p.[start_date] AS StartDate,
           p.deadline AS Deadline, p.delivery_date AS DeliveryDate,
           p.created_at AS CreatedAt, p.created_by AS CreatedBy,
           p.updated_at AS UpdatedAt, p.updated_by AS UpdatedBy
    FROM projects p
    INNER JOIN buyers b ON b.buyer_id = p.customer_id
    LEFT JOIN employees md ON md.employee_id = p.project_md
    LEFT JOIN employees pic ON pic.employee_id = p.project_pic
    WHERE p.project_id = @Id AND p.deleted_at IS NULL;
END;
GO

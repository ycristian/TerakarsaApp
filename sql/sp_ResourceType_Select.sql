-- Pengambilan data resource_types (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_ResourceType_Manage.sql (SIS_ResourceType_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_ResourceType_GetAll
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
        FROM resource_types
        WHERE deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR resource_type_code LIKE '%' + @SearchTerm + '%'
               OR resource_type_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'ResourceTypeCode' THEN 'resource_type_code'
            WHEN 'ResourceTypeName' THEN 'resource_type_name'
            WHEN 'CreatedAt' THEN 'created_at'
            ELSE 'resource_type_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'resource_type_id' THEN '' ELSE ', resource_type_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT resource_type_id AS Id, resource_type_code AS ResourceTypeCode, resource_type_name AS ResourceTypeName,
                   created_at AS CreatedAt, created_by AS CreatedBy,
                   updated_at AS UpdatedAt, updated_by AS UpdatedBy
            FROM resource_types
            WHERE deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR resource_type_code LIKE ''%'' + @SearchTerm + ''%''
                   OR resource_type_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_ResourceType_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT resource_type_id AS Id, resource_type_code AS ResourceTypeCode, resource_type_name AS ResourceTypeName,
           created_at AS CreatedAt, created_by AS CreatedBy,
           updated_at AS UpdatedAt, updated_by AS UpdatedBy
    FROM resource_types
    WHERE resource_type_id = @Id AND deleted_at IS NULL;
END;
GO

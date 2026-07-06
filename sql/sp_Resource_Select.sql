-- Pengambilan data resources (SELECT saja, tidak menyentuh data).
-- JOIN ke divisions dan resource_types karena resources punya 2 FK wajib.
-- Mutasi (create/update/delete) ada di sp_Resource_Manage.sql (SIS_Resource_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Resource_GetAll
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
        FROM resources r
        INNER JOIN divisions d ON d.division_id = r.division_id
        INNER JOIN resource_types rt ON rt.resource_type_id = r.resource_type_id
        WHERE r.deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR r.resource_name LIKE '%' + @SearchTerm + '%'
               OR d.division_name LIKE '%' + @SearchTerm + '%'
               OR rt.resource_type_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'ResourceName' THEN 'r.resource_name'
            WHEN 'DivisionName' THEN 'd.division_name'
            WHEN 'ResourceTypeName' THEN 'rt.resource_type_name'
            WHEN 'IsActive' THEN 'r.is_active'
            WHEN 'CreatedAt' THEN 'r.created_at'
            ELSE 'r.resource_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'r.resource_id' THEN '' ELSE ', r.resource_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT r.resource_id AS Id,
                   r.division_id AS DivisionId, d.division_name AS DivisionName,
                   r.resource_type_id AS ResourceTypeId, rt.resource_type_name AS ResourceTypeName,
                   r.resource_name AS ResourceName, r.is_active AS IsActive,
                   r.created_at AS CreatedAt, r.created_by AS CreatedBy,
                   r.updated_at AS UpdatedAt, r.updated_by AS UpdatedBy
            FROM resources r
            INNER JOIN divisions d ON d.division_id = r.division_id
            INNER JOIN resource_types rt ON rt.resource_type_id = r.resource_type_id
            WHERE r.deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR r.resource_name LIKE ''%'' + @SearchTerm + ''%''
                   OR d.division_name LIKE ''%'' + @SearchTerm + ''%''
                   OR rt.resource_type_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_Resource_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.resource_id AS Id,
           r.division_id AS DivisionId, d.division_name AS DivisionName,
           r.resource_type_id AS ResourceTypeId, rt.resource_type_name AS ResourceTypeName,
           r.resource_name AS ResourceName, r.is_active AS IsActive,
           r.created_at AS CreatedAt, r.created_by AS CreatedBy,
           r.updated_at AS UpdatedAt, r.updated_by AS UpdatedBy
    FROM resources r
    INNER JOIN divisions d ON d.division_id = r.division_id
    INNER JOIN resource_types rt ON rt.resource_type_id = r.resource_type_id
    WHERE r.resource_id = @Id AND r.deleted_at IS NULL;
END;
GO

-- Lookup resource aktif untuk dropdown Employees, terfilter berdasarkan Division
-- (cascading dropdown: pilihan resource berubah mengikuti division yang dipilih).
CREATE OR ALTER PROCEDURE SIS_Resource_GetActiveByDivision
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT resource_id AS Id, resource_name AS ResourceName
    FROM resources
    WHERE division_id = @DivisionId
      AND is_active = 1
      AND deleted_at IS NULL
    ORDER BY resource_name ASC;
END;
GO

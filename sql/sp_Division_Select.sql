-- Pengambilan data divisions (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_Division_Manage.sql (SIS_Division_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Division_GetAll
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
        FROM divisions
        WHERE deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR division_code LIKE '%' + @SearchTerm + '%'
               OR division_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'DivisionCode' THEN 'division_code'
            WHEN 'DivisionName' THEN 'division_name'
            WHEN 'CreatedAt' THEN 'created_at'
            ELSE 'division_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'division_id' THEN '' ELSE ', division_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT division_id AS Id, division_code AS DivisionCode, division_name AS DivisionName,
                   created_at AS CreatedAt, created_by AS CreatedBy,
                   updated_at AS UpdatedAt, updated_by AS UpdatedBy
            FROM divisions
            WHERE deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR division_code LIKE ''%'' + @SearchTerm + ''%''
                   OR division_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_Division_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT division_id AS Id, division_code AS DivisionCode, division_name AS DivisionName,
           created_at AS CreatedAt, created_by AS CreatedBy,
           updated_at AS UpdatedAt, updated_by AS UpdatedBy
    FROM divisions
    WHERE division_id = @Id AND deleted_at IS NULL;
END;
GO

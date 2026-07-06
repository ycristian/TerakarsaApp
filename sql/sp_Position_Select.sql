-- Pengambilan data positions (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_Position_Manage.sql (SIS_Position_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Position_GetAll
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
        FROM positions
        WHERE deleted_at IS NULL
          AND (@SearchTerm IS NULL OR position_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'PositionName' THEN 'position_name'
            WHEN 'CreatedAt' THEN 'created_at'
            ELSE 'position_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'position_id' THEN '' ELSE ', position_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT position_id AS Id, position_name AS PositionName,
                   created_at AS CreatedAt, created_by AS CreatedBy,
                   updated_at AS UpdatedAt, updated_by AS UpdatedBy
            FROM positions
            WHERE deleted_at IS NULL
              AND (@SearchTerm IS NULL OR position_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_Position_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT position_id AS Id, position_name AS PositionName,
           created_at AS CreatedAt, created_by AS CreatedBy,
           updated_at AS UpdatedAt, updated_by AS UpdatedBy
    FROM positions
    WHERE position_id = @Id AND deleted_at IS NULL;
END;
GO

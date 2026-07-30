-- Pengambilan data buyers (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_Buyer_Manage.sql (SIS_Buyer_Manage).
--
-- Fix: @SearchTerm kini pencarian antar-atribut (tiap kata dipisah spasi dicek independen ke
-- SEMUA kolom via STRING_SPLIT) -- lihat komentar sama di sp_Employee_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Buyer_GetAll
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
        FROM buyers
        WHERE deleted_at IS NULL
          AND (@SearchTerm IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@SearchTerm, ' ') tok
                WHERE tok.value <> ''
                  AND NOT (
                        buyer_code LIKE '%' + tok.value + '%'
                     OR buyer_name LIKE '%' + tok.value + '%'
                  )
              ));
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'BuyerCode' THEN 'buyer_code'
            WHEN 'BuyerName' THEN 'buyer_name'
            WHEN 'CreatedAt' THEN 'created_at'
            ELSE 'buyer_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'buyer_id' THEN '' ELSE ', buyer_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT buyer_id AS Id, buyer_code AS BuyerCode, buyer_name AS BuyerName,
                   [address] AS [Address], phone AS Phone,
                   created_at AS CreatedAt, created_by AS CreatedBy,
                   updated_at AS UpdatedAt, updated_by AS UpdatedBy
            FROM buyers
            WHERE deleted_at IS NULL
              AND (@SearchTerm IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@SearchTerm, '' '') tok
                    WHERE tok.value <> ''''
                      AND NOT (
                            buyer_code LIKE ''%'' + tok.value + ''%''
                         OR buyer_name LIKE ''%'' + tok.value + ''%''
                      )
                  ))
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

CREATE OR ALTER PROCEDURE SIS_Buyer_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT buyer_id AS Id, buyer_code AS BuyerCode, buyer_name AS BuyerName,
           [address] AS [Address], phone AS Phone,
           created_at AS CreatedAt, created_by AS CreatedBy,
           updated_at AS UpdatedAt, updated_by AS UpdatedBy
    FROM buyers
    WHERE buyer_id = @Id AND deleted_at IS NULL;
END;
GO

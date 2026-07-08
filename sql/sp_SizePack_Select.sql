-- Pengambilan data size_packs (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete) ada di sp_SizePack_Manage.sql (SIS_SizePack_Manage).
-- GetById hanya mengembalikan header (EF SqlQueryRaw hanya baca 1 result set);
-- detail diambil terpisah lewat SIS_SizePackDetail_GetBySizePack.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_SizePack_GetAll
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
        FROM size_packs sp
        LEFT JOIN buyers b ON b.buyer_id = sp.buyer_id
        WHERE sp.deleted_at IS NULL
          AND (@SearchTerm IS NULL
               OR sp.size_pack_name LIKE '%' + @SearchTerm + '%'
               OR b.buyer_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'SizePackName' THEN 'sp.size_pack_name'
            WHEN 'BuyerName' THEN 'b.buyer_name'
            WHEN 'CreatedAt' THEN 'sp.created_at'
            ELSE 'sp.size_pack_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'sp.size_pack_id' THEN '' ELSE ', sp.size_pack_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT sp.size_pack_id AS Id, sp.buyer_id AS BuyerId, b.buyer_name AS BuyerName,
                   sp.size_pack_name AS SizePackName,
                   sp.created_at AS CreatedAt, sp.created_by AS CreatedBy,
                   sp.updated_at AS UpdatedAt, sp.updated_by AS UpdatedBy
            FROM size_packs sp
            LEFT JOIN buyers b ON b.buyer_id = sp.buyer_id
            WHERE sp.deleted_at IS NULL
              AND (@SearchTerm IS NULL
                   OR sp.size_pack_name LIKE ''%'' + @SearchTerm + ''%''
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

CREATE OR ALTER PROCEDURE SIS_SizePack_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT sp.size_pack_id AS Id, sp.buyer_id AS BuyerId, b.buyer_name AS BuyerName,
           sp.size_pack_name AS SizePackName,
           sp.created_at AS CreatedAt, sp.created_by AS CreatedBy,
           sp.updated_at AS UpdatedAt, sp.updated_by AS UpdatedBy
    FROM size_packs sp
    LEFT JOIN buyers b ON b.buyer_id = sp.buyer_id
    WHERE sp.size_pack_id = @Id AND sp.deleted_at IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE SIS_SizePackDetail_GetBySizePack
    @SizePackId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT size_pack_detail_id AS Id, size_pack_id AS SizePackId, size_name AS SizeName,
           sort_order AS SortOrder, [description] AS [Description]
    FROM size_pack_details
    WHERE size_pack_id = @SizePackId AND deleted_at IS NULL
    ORDER BY sort_order ASC, size_pack_detail_id ASC;
END;
GO

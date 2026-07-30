-- Direkonstruksi dari pemanggilan di ProductService.cs (definisi asli tidak ada di repo ini).
-- Aman dijalankan kapan pun: CREATE OR ALTER hanya memperbarui definisi proc, tidak menyentuh data.
--
-- Fix: @Search kini pencarian antar-atribut (tiap kata dipisah spasi dicek independen ke
-- SEMUA kolom via STRING_SPLIT) -- lihat komentar sama di sp_Employee_Select.sql.

CREATE OR ALTER PROCEDURE SIS_Product_Manage
    @Action        NVARCHAR(20),
    @Id            INT = NULL,
    @Name          NVARCHAR(150) = NULL,
    @Price         DECIMAL(18,2) = NULL,
    @Stock         INT = NULL,
    @Search        NVARCHAR(150) = NULL,
    @PageNumber    INT = 1,
    @PageSize      INT = 10,
    @SortColumn    NVARCHAR(50) = NULL,
    @SortDirection NVARCHAR(4) = 'asc'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'GET' AND @Id IS NOT NULL
    BEGIN
        SELECT Id, Name, Price, Stock, IsActive, CreatedAt
        FROM Products
        WHERE Id = @Id;
    END

    ELSE IF @Action = 'GET'
    BEGIN
        DECLARE @OrderCol NVARCHAR(50) = CASE @SortColumn
            WHEN 'Name' THEN 'Name'
            WHEN 'Price' THEN 'Price'
            WHEN 'Stock' THEN 'Stock'
            WHEN 'CreatedAt' THEN 'CreatedAt'
            ELSE 'Id'
        END;
        DECLARE @Dir NVARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak NVARCHAR(20) = CASE WHEN @OrderCol = 'Id' THEN N'' ELSE N', Id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT Id, Name, Price, Stock, IsActive, CreatedAt
            FROM Products
            WHERE (@Search IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@Search, '' '') tok
                    WHERE tok.value <> '''' AND NOT (Name LIKE ''%'' + tok.value + ''%'')
                  ))
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@Search NVARCHAR(150), @PageNumber INT, @PageSize INT',
            @Search, @PageNumber, @PageSize;
    END

    ELSE IF @Action = 'COUNT'
    BEGIN
        SELECT COUNT(*) AS TotalCount
        FROM Products
        WHERE (@Search IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@Search, ' ') tok
                WHERE tok.value <> '' AND NOT (Name LIKE '%' + tok.value + '%')
              ));
    END

    ELSE IF @Action = 'INSERT'
    BEGIN
        INSERT INTO Products (Name, Price, Stock, IsActive, CreatedAt)
        VALUES (@Name, @Price, @Stock, 1, GETDATE());
        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE Products
        SET Name = @Name,
            Price = @Price,
            Stock = @Stock
        WHERE Id = @Id;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE Products SET IsActive = 0 WHERE Id = @Id;
    END
END;
GO

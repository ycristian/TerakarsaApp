-- Menambahkan kolom SubCategory ke Modules, untuk mendukung grup collapsible
-- di sidebar: Category (header section) > SubCategory (grup collapsible, opsional) > Name (halaman).
-- Module tanpa SubCategory tetap tampil flat langsung di bawah Category, seperti sebelumnya.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.
--
-- Fix: @Search (action GET/COUNT) kini pencarian antar-atribut (tiap kata dipisah spasi
-- dicek independen ke SEMUA kolom via STRING_SPLIT) -- lihat komentar sama di
-- sp_Employee_Select.sql.

IF COL_LENGTH('Modules', 'SubCategory') IS NULL
BEGIN
    ALTER TABLE Modules ADD SubCategory NVARCHAR(100) NULL;
END
GO

CREATE OR ALTER PROCEDURE SIS_Module_Manage
    @Action        NVARCHAR(20),
    @Id            INT = NULL,
    @UserId        INT = NULL,
    @Code          NVARCHAR(50) = NULL,
    @Name          NVARCHAR(100) = NULL,
    @Category      NVARCHAR(100) = NULL,
    @SubCategory   NVARCHAR(100) = NULL,
    @Route         NVARCHAR(100) = NULL,
    @Icon          NVARCHAR(50) = NULL,
    @SortOrder     INT = NULL,
    @IsActive      BIT = NULL,
    @Search        NVARCHAR(150) = NULL,
    @PageNumber    INT = 1,
    @PageSize      INT = 10,
    @SortColumn    NVARCHAR(50) = NULL,
    @SortDirection NVARCHAR(4) = 'asc'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'GET'
    BEGIN
        DECLARE @OrderCol NVARCHAR(50) = CASE @SortColumn
            WHEN 'Code' THEN 'Code'
            WHEN 'Name' THEN 'Name'
            WHEN 'Category' THEN 'Category'
            WHEN 'SubCategory' THEN 'SubCategory'
            WHEN 'Route' THEN 'Route'
            WHEN 'SortOrder' THEN 'SortOrder'
            ELSE 'SortOrder'
        END;
        DECLARE @Dir NVARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT Id, Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt
            FROM Modules
            WHERE (@Search IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@Search, '' '') tok
                    WHERE tok.value <> ''''
                      AND NOT (Name LIKE ''%'' + tok.value + ''%'' OR Code LIKE ''%'' + tok.value + ''%'')
                  ))
            ORDER BY ' + @OrderCol + N' ' + @Dir + N', Id ASC
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@Search NVARCHAR(150), @PageNumber INT, @PageSize INT',
            @Search, @PageNumber, @PageSize;
    END

    ELSE IF @Action = 'COUNT'
    BEGIN
        SELECT COUNT(*) AS TotalCount
        FROM Modules
        WHERE (@Search IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@Search, ' ') tok
                WHERE tok.value <> ''
                  AND NOT (Name LIKE '%' + tok.value + '%' OR Code LIKE '%' + tok.value + '%')
              ));
    END

    ELSE IF @Action = 'GET_BY_USER'
    BEGIN
        SELECT m.Id, m.Code, m.Name, m.Category, m.SubCategory, m.Route, m.Icon, m.SortOrder, m.IsActive, m.CreatedAt
        FROM Modules m
        INNER JOIN UserModules um ON um.ModuleId = m.Id
        WHERE um.UserId = @UserId AND m.IsActive = 1
        ORDER BY m.SortOrder ASC, m.Id ASC;
    END

    ELSE IF @Action = 'INSERT'
    BEGIN
        INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
        VALUES (@Code, @Name, @Category, @SubCategory, @Route, @Icon, ISNULL(@SortOrder, 0), 1, GETDATE());
        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE Modules
        SET Code = @Code,
            Name = @Name,
            Category = @Category,
            SubCategory = @SubCategory,
            Route = @Route,
            Icon = @Icon,
            SortOrder = ISNULL(@SortOrder, SortOrder),
            IsActive = @IsActive
        WHERE Id = @Id;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE Modules SET IsActive = 0 WHERE Id = @Id;
    END
END;
GO

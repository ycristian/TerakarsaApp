-- Fix: @Search kini pencarian antar-atribut (tiap kata dipisah spasi dicek independen ke
-- SEMUA kolom via STRING_SPLIT) -- lihat komentar sama di sp_Employee_Select.sql.
CREATE OR ALTER PROCEDURE SIS_User_Manage
    @Action        NVARCHAR(20),
    @Id            INT = NULL,
    @Username      NVARCHAR(100) = NULL,
    @Password      NVARCHAR(255) = NULL,
    @FullName      NVARCHAR(150) = NULL,
    @Role          NVARCHAR(50) = NULL,
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
            WHEN 'Username' THEN 'Username'
            WHEN 'FullName' THEN 'FullName'
            WHEN 'Role' THEN 'Role'
            WHEN 'CreatedAt' THEN 'CreatedAt'
            ELSE 'Id'
        END;
        DECLARE @Dir NVARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak NVARCHAR(20) = CASE WHEN @OrderCol = 'Id' THEN N'' ELSE N', Id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT Id, Username, FullName, Role, IsActive, CreatedAt
            FROM Users
            WHERE (@Search IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@Search, '' '') tok
                    WHERE tok.value <> ''''
                      AND NOT (Username LIKE ''%'' + tok.value + ''%'' OR FullName LIKE ''%'' + tok.value + ''%'')
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
        FROM Users
        WHERE (@Search IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@Search, ' ') tok
                WHERE tok.value <> ''
                  AND NOT (Username LIKE '%' + tok.value + '%' OR FullName LIKE '%' + tok.value + '%')
              ));
    END

    ELSE IF @Action = 'INSERT'
    BEGIN
        INSERT INTO Users (Username, Password, FullName, Role, IsActive, CreatedAt)
        VALUES (@Username, @Password, @FullName, @Role, 1, GETDATE());
        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE Users
        SET FullName = @FullName,
            Role = @Role,
            IsActive = @IsActive
        WHERE Id = @Id;
    END

    ELSE IF @Action = 'RESET_PASSWORD'
    BEGIN
        UPDATE Users
        SET Password = @Password
        WHERE Id = @Id;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE Users SET IsActive = 0 WHERE Id = @Id;
    END
END;
GO

-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF OBJECT_ID('Modules', 'U') IS NULL
BEGIN
    CREATE TABLE Modules (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        Code        NVARCHAR(50) NOT NULL UNIQUE,
        Name        NVARCHAR(100) NOT NULL,
        Category    NVARCHAR(100) NOT NULL,
        Route       NVARCHAR(100) NOT NULL,
        Icon        NVARCHAR(50) NOT NULL,
        SortOrder   INT NOT NULL DEFAULT 0,
        IsActive    BIT NOT NULL DEFAULT 1,
        CreatedAt   DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO

IF OBJECT_ID('UserModules', 'U') IS NULL
BEGIN
    CREATE TABLE UserModules (
        Id          INT IDENTITY(1,1) PRIMARY KEY,
        UserId      INT NOT NULL,
        ModuleId    INT NOT NULL,
        CreatedAt   DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT FK_UserModules_Users FOREIGN KEY (UserId) REFERENCES Users(Id),
        CONSTRAINT FK_UserModules_Modules FOREIGN KEY (ModuleId) REFERENCES Modules(Id),
        CONSTRAINT UQ_UserModules_User_Module UNIQUE (UserId, ModuleId)
    );
END
GO

CREATE OR ALTER PROCEDURE SIS_Module_Manage
    @Action        NVARCHAR(20),
    @Id            INT = NULL,
    @UserId        INT = NULL,
    @Code          NVARCHAR(50) = NULL,
    @Name          NVARCHAR(100) = NULL,
    @Category      NVARCHAR(100) = NULL,
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
            WHEN 'Route' THEN 'Route'
            WHEN 'SortOrder' THEN 'SortOrder'
            ELSE 'SortOrder'
        END;
        DECLARE @Dir NVARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT Id, Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt
            FROM Modules
            WHERE (@Search IS NULL OR Name LIKE ''%'' + @Search + ''%'' OR Code LIKE ''%'' + @Search + ''%'')
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
        WHERE (@Search IS NULL OR Name LIKE '%' + @Search + '%' OR Code LIKE '%' + @Search + '%');
    END

    ELSE IF @Action = 'GET_BY_USER'
    BEGIN
        SELECT m.Id, m.Code, m.Name, m.Category, m.Route, m.Icon, m.SortOrder, m.IsActive, m.CreatedAt
        FROM Modules m
        INNER JOIN UserModules um ON um.ModuleId = m.Id
        WHERE um.UserId = @UserId AND m.IsActive = 1
        ORDER BY m.SortOrder ASC, m.Id ASC;
    END

    ELSE IF @Action = 'INSERT'
    BEGIN
        INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
        VALUES (@Code, @Name, @Category, @Route, @Icon, ISNULL(@SortOrder, 0), 1, GETDATE());
        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE Modules
        SET Code = @Code,
            Name = @Name,
            Category = @Category,
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

CREATE OR ALTER PROCEDURE SIS_UserModule_Manage
    @Action     NVARCHAR(20),
    @UserId     INT = NULL,
    @ModuleIds  NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'GET_BY_USER'
    BEGIN
        SELECT ModuleId
        FROM UserModules
        WHERE UserId = @UserId;
    END

    ELSE IF @Action = 'SET'
    BEGIN
        DELETE FROM UserModules WHERE UserId = @UserId;

        INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
        SELECT @UserId, CAST(value AS INT), GETDATE()
        FROM STRING_SPLIT(@ModuleIds, ',')
        WHERE LTRIM(RTRIM(value)) <> '';
    END
END;
GO

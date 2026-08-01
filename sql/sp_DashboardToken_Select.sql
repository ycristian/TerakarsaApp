-- Pengambilan data dashboard_tokens (SELECT saja, tidak menyentuh data). Mutasi ada di
-- sp_DashboardToken_Manage.sql (SIS_DashboardToken_Manage).
-- Token PENUH TIDAK PERNAH dikembalikan di sini -- TokenPreview di-mask total (bukan lagi
-- 8 karakter awal seperti token GUID lama: sejak token dipersingkat jadi 5 karakter pola
-- station pairing code, "8 karakter awal" akan membocorkan seluruh token).
-- (SIS_DashboardToken_Manage CREATE/REGENERATE saja yang mengembalikan token penuh, sekali).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_DashboardToken_List
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
        FROM dashboard_tokens
        WHERE deleted_at IS NULL
          AND (@SearchTerm IS NULL OR token_name LIKE '%' + @SearchTerm + '%');
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'TokenName' THEN 'token_name'
            WHEN 'IsActive' THEN 'is_active'
            WHEN 'RefreshIntervalMinutes' THEN 'refresh_interval_minutes'
            WHEN 'LastSeenAt' THEN 'last_seen_at'
            WHEN 'CreatedAt' THEN 'created_at'
            ELSE 'dashboard_token_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 'dashboard_token_id' THEN '' ELSE ', dashboard_token_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT dashboard_token_id AS Id, token_name AS TokenName,
                   REPLICATE(''•'', LEN(dashboard_token)) AS TokenPreview,
                   is_active AS IsActive, refresh_interval_minutes AS RefreshIntervalMinutes,
                   last_seen_at AS LastSeenAt,
                   created_at AS CreatedAt, created_by AS CreatedBy,
                   updated_at AS UpdatedAt, updated_by AS UpdatedBy
            FROM dashboard_tokens
            WHERE deleted_at IS NULL
              AND (@SearchTerm IS NULL OR token_name LIKE ''%'' + @SearchTerm + ''%'')
            ORDER BY ' + @OrderCol + N' ' + @Dir + @Tiebreak + N'
            OFFSET (@PageNumber - 1) * @PageSize ROWS
            FETCH NEXT @PageSize ROWS ONLY;';

        EXEC sp_executesql @Sql,
            N'@SearchTerm VARCHAR(150), @PageNumber INT, @PageSize INT',
            @SearchTerm, @PageNumber, @PageSize;
    END
END;
GO

-- Link lengkap satu token untuk tombol "Salin Link" (admin tidak perlu regenerate hanya
-- untuk menyalin) -- INI SATU-SATUNYA SELECT selain CREATE/REGENERATE yang mengembalikan
-- token penuh, dan hanya dipanggil oleh admin yang sudah [Authorize] + RequireModule.
CREATE OR ALTER PROCEDURE SIS_DashboardToken_GetToken
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dashboard_token AS Token
    FROM dashboard_tokens
    WHERE dashboard_token_id = @Id AND deleted_at IS NULL;
END;
GO

-- Autentikasi kiosk: cari token hidup + aktif berdasarkan token mentah dari header
-- X-Dashboard-Token. Dipakai oleh RequireDashboardTokenAttribute.
CREATE OR ALTER PROCEDURE SIS_DashboardToken_GetByToken
    @Token VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dashboard_token_id AS DashboardTokenId, token_name AS TokenName,
           refresh_interval_minutes AS RefreshIntervalMinutes
    FROM dashboard_tokens
    WHERE dashboard_token = @Token AND is_active = 1 AND deleted_at IS NULL;
END;
GO

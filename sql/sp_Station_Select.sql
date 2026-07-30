-- Pengambilan data stations (SELECT saja, tidak menyentuh data).
-- Mutasi (create/update/delete/pairing/unpair) ada di sp_Station_Manage.sql (SIS_Station_Manage).
-- Token penuh TIDAK pernah dikembalikan lewat SP di file ini -- admin hanya melihat status
-- pairing (paired_at/pairing_code_expires_at); station_token hanya dikembalikan oleh
-- SIS_Station_Manage saat CREATE/CLAIM_PAIRING.
--
-- Fix: @SearchTerm kini pencarian antar-atribut (tiap kata dipisah spasi dicek independen ke
-- SEMUA kolom via STRING_SPLIT) -- lihat komentar sama di sp_Employee_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Station_GetAll
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
        FROM stations s
        INNER JOIN divisions d ON d.division_id = s.division_id
        WHERE s.deleted_at IS NULL
          AND (@SearchTerm IS NULL OR NOT EXISTS (
                SELECT 1 FROM STRING_SPLIT(@SearchTerm, ' ') tok
                WHERE tok.value <> ''
                  AND NOT (
                        s.station_code LIKE '%' + tok.value + '%'
                     OR s.station_name LIKE '%' + tok.value + '%'
                     OR d.division_name LIKE '%' + tok.value + '%'
                  )
              ));
    END
    ELSE
    BEGIN
        DECLARE @OrderCol VARCHAR(50) = CASE @SortColumn
            WHEN 'StationCode' THEN 's.station_code'
            WHEN 'StationName' THEN 's.station_name'
            WHEN 'DivisionName' THEN 'd.division_name'
            WHEN 'IsActive' THEN 's.is_active'
            WHEN 'CreatedAt' THEN 's.created_at'
            ELSE 's.station_id'
        END;
        DECLARE @Dir VARCHAR(4) = CASE WHEN @SortDirection = 'desc' THEN 'DESC' ELSE 'ASC' END;
        DECLARE @Tiebreak VARCHAR(30) = CASE WHEN @OrderCol = 's.station_id' THEN '' ELSE ', s.station_id ASC' END;

        DECLARE @Sql NVARCHAR(MAX) = N'
            SELECT s.station_id AS Id, s.station_code AS StationCode, s.station_name AS StationName,
                   s.division_id AS DivisionId, d.division_name AS DivisionName,
                   s.is_active AS IsActive,
                   s.default_resource_id AS DefaultResourceId, r.resource_name AS DefaultResourceName,
                   s.allow_resource_change AS AllowResourceChange,
                   s.enable_packing AS EnablePacking,
                   s.paired_at AS PairedAt,
                   CASE WHEN s.pairing_code_expires_at > SYSDATETIME() THEN s.pairing_code_expires_at ELSE NULL END AS PairingCodeExpiresAt,
                   s.created_at AS CreatedAt, s.created_by AS CreatedBy,
                   s.updated_at AS UpdatedAt, s.updated_by AS UpdatedBy
            FROM stations s
            INNER JOIN divisions d ON d.division_id = s.division_id
            LEFT JOIN resources r ON r.resource_id = s.default_resource_id
            WHERE s.deleted_at IS NULL
              AND (@SearchTerm IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@SearchTerm, '' '') tok
                    WHERE tok.value <> ''''
                      AND NOT (
                            s.station_code LIKE ''%'' + tok.value + ''%''
                         OR s.station_name LIKE ''%'' + tok.value + ''%''
                         OR d.division_name LIKE ''%'' + tok.value + ''%''
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

CREATE OR ALTER PROCEDURE SIS_Station_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.station_id AS Id, s.station_code AS StationCode, s.station_name AS StationName,
           s.division_id AS DivisionId, d.division_name AS DivisionName,
           s.is_active AS IsActive,
           s.default_resource_id AS DefaultResourceId, r.resource_name AS DefaultResourceName,
           s.allow_resource_change AS AllowResourceChange,
           s.enable_packing AS EnablePacking,
           s.paired_at AS PairedAt,
           CASE WHEN s.pairing_code_expires_at > SYSDATETIME() THEN s.pairing_code_expires_at ELSE NULL END AS PairingCodeExpiresAt,
           s.created_at AS CreatedAt, s.created_by AS CreatedBy,
           s.updated_at AS UpdatedAt, s.updated_by AS UpdatedBy
    FROM stations s
    INNER JOIN divisions d ON d.division_id = s.division_id
    LEFT JOIN resources r ON r.resource_id = s.default_resource_id
    WHERE s.station_id = @Id AND s.deleted_at IS NULL;
END;
GO

-- Autentikasi perangkat stasiun: cari stasiun hidup + aktif berdasarkan token mentah
-- yang dikirim lewat header X-Station-Token. Dipakai oleh RequireStationTokenAttribute.
CREATE OR ALTER PROCEDURE SIS_Station_GetByToken
    @Token VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.station_id AS StationId, s.station_name AS StationName,
           s.division_id AS DivisionId, d.division_name AS DivisionName,
           s.default_resource_id AS DefaultResourceId, r.resource_name AS DefaultResourceName,
           s.allow_resource_change AS AllowResourceChange,
           s.enable_packing AS EnablePacking
    FROM stations s
    INNER JOIN divisions d ON d.division_id = s.division_id
    LEFT JOIN resources r ON r.resource_id = s.default_resource_id
    WHERE s.station_token = @Token AND s.is_active = 1 AND s.deleted_at IS NULL;
END;
GO

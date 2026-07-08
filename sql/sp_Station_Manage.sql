-- Mutasi data stations (create/update/delete/regenerate token).
-- Pengambilan data ada di sp_Station_Select.sql.
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: stations punya filtered unique index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Station_Manage
    @Action      VARCHAR(20),
    @Id          INT = NULL,
    @StationCode VARCHAR(30) = NULL,
    @StationName VARCHAR(150) = NULL,
    @DivisionId  INT = NULL,
    @IsActive    BIT = 1,
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM stations WHERE station_code = @StationCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode stasiun "%s" sudah digunakan.', 16, 1, @StationCode);
            RETURN;
        END

        DECLARE @NewToken VARCHAR(64) = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        INSERT INTO stations (station_code, station_name, division_id, station_token, is_active, created_at, created_by)
        VALUES (@StationCode, @StationName, @DivisionId, @NewToken, @IsActive, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId, @NewToken AS NewToken;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM stations
            WHERE station_code = @StationCode AND deleted_at IS NULL AND station_id <> @Id
        )
        BEGIN
            RAISERROR('Kode stasiun "%s" sudah digunakan.', 16, 1, @StationCode);
            RETURN;
        END

        UPDATE stations
        SET station_code = @StationCode,
            station_name = @StationName,
            division_id = @DivisionId,
            is_active = @IsActive,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE stations
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'REGENERATE_TOKEN'
    BEGIN
        DECLARE @RegeneratedToken VARCHAR(64) = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        UPDATE stations
        SET station_token = @RegeneratedToken,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;

        SELECT @RegeneratedToken AS NewToken;
    END
END;
GO

-- Mutasi data stations (create/update/delete/regenerate token).
-- Pengambilan data ada di sp_Station_Select.sql.
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: stations punya filtered unique index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Station_Manage
    @Action               VARCHAR(20),
    @Id                   INT = NULL,
    @StationCode          VARCHAR(30) = NULL,
    @StationName          VARCHAR(150) = NULL,
    @DivisionId           INT = NULL,
    @IsActive             BIT = 1,
    @DefaultResourceId    INT = NULL,
    @AllowResourceChange  BIT = 1,
    @EnablePacking        BIT = 0,
    @PairingCode          VARCHAR(10) = NULL,
    @NewToken             VARCHAR(64) = NULL,
    @UserId               INT = NULL
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

        IF @DefaultResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @DefaultResourceId AND division_id = @DivisionId
              AND is_active = 1 AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Resource bukan milik divisi stasiun ini.', 16, 1);
            RETURN;
        END

        IF @AllowResourceChange = 0 AND @DefaultResourceId IS NULL
        BEGIN
            RAISERROR('Stasiun terkunci wajib punya resource bawaan.', 16, 1);
            RETURN;
        END

        DECLARE @NewToken VARCHAR(64) = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        INSERT INTO stations (station_code, station_name, division_id, station_token, is_active,
                               default_resource_id, allow_resource_change, enable_packing, created_at, created_by)
        VALUES (@StationCode, @StationName, @DivisionId, @NewToken, @IsActive,
                @DefaultResourceId, @AllowResourceChange, @EnablePacking, SYSDATETIME(), @UserId);

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

        -- Resource bawaan tidak lagi cocok dengan divisi stasiun (mis. division_id baru
        -- saja diubah) -- kosongkan otomatis alih-alih menolak update.
        IF @DefaultResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @DefaultResourceId AND division_id = @DivisionId
              AND is_active = 1 AND deleted_at IS NULL
        )
        BEGIN
            SET @DefaultResourceId = NULL;
            SET @AllowResourceChange = 1;
        END

        IF @AllowResourceChange = 0 AND @DefaultResourceId IS NULL
        BEGIN
            RAISERROR('Stasiun terkunci wajib punya resource bawaan.', 16, 1);
            RETURN;
        END

        UPDATE stations
        SET station_code = @StationCode,
            station_name = @StationName,
            division_id = @DivisionId,
            is_active = @IsActive,
            default_resource_id = @DefaultResourceId,
            allow_resource_change = @AllowResourceChange,
            enable_packing = @EnablePacking,
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

    -- Prompt 20: admin membuat kode pairing baru (menimpa kode lama bila ada -- kode
    -- lama otomatis hangus). Kode digenerate di API, SP hanya menyimpan + set expiry 15 menit.
    ELSE IF @Action = 'GENERATE_PAIRING'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM stations WHERE station_id = @Id AND deleted_at IS NULL AND is_active = 1)
        BEGIN
            RAISERROR('Stasiun tidak ditemukan atau nonaktif.', 16, 1);
            RETURN;
        END

        DECLARE @ExpiresAt DATETIME2 = DATEADD(MINUTE, 15, SYSDATETIME());

        UPDATE stations
        SET pairing_code = @PairingCode,
            pairing_code_expires_at = @ExpiresAt,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;

        SELECT @PairingCode AS PairingCode, @ExpiresAt AS ExpiresAt;
    END

    -- Prompt 20: perangkat menukar kode pairing dengan station_token baru (rotate --
    -- token lama langsung mati, satu perangkat aktif per station). Kode sekali pakai:
    -- UPDATE tunggal ini sekaligus memvalidasi & menghanguskan kode (atomik).
    ELSE IF @Action = 'CLAIM_PAIRING'
    BEGIN
        DECLARE @ClaimedStation TABLE (StationId INT);

        UPDATE stations
        SET station_token = @NewToken,
            pairing_code = NULL,
            pairing_code_expires_at = NULL,
            paired_at = SYSDATETIME(),
            updated_at = SYSDATETIME()
        OUTPUT INSERTED.station_id INTO @ClaimedStation
        WHERE pairing_code = @PairingCode
          AND pairing_code_expires_at > SYSDATETIME()
          AND is_active = 1 AND deleted_at IS NULL;

        IF NOT EXISTS (SELECT 1 FROM @ClaimedStation)
        BEGIN
            RAISERROR('Kode pairing tidak valid atau sudah kedaluwarsa.', 16, 1);
            RETURN;
        END

        SELECT StationId FROM @ClaimedStation;
    END

    -- Prompt 20: putuskan perangkat -- station_token diganti GUID baru (token lama mati)
    -- baik dipicu admin ("Putuskan Perangkat") maupun perangkat sendiri (logout).
    ELSE IF @Action = 'UNPAIR'
    BEGIN
        DECLARE @UnpairedToken VARCHAR(64) = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        UPDATE stations
        SET station_token = @UnpairedToken,
            paired_at = NULL,
            pairing_code = NULL,
            pairing_code_expires_at = NULL,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;
    END
END;
GO

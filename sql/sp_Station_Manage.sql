-- Mutasi data stations (create/update/delete/regenerate token).
-- Pengambilan data ada di sp_Station_Select.sql.
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: stations punya filtered unique index.
--
-- Prompt 85 (alter_88): kode login terkunci (LOCK_CODE/UNLOCK_CODE), peringatan ambil alih
-- "DIPAKAI|nama|terakhir aktif" di CLAIM_PAIRING, dan TOUCH (kehadiran perangkat).
-- Generate/refresh/kunci kode TIDAK pernah merotasi station_token -- token hanya berganti
-- saat klaim (saling tendang) atau UNPAIR.

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
    @AllowAllDivisions    BIT = 0,
    @PairingCode          VARCHAR(10) = NULL,
    @NewToken             VARCHAR(64) = NULL,
    @UserId               INT = NULL,
    @DeviceId             VARCHAR(64) = NULL,     -- Prompt 85: NULL = dipanggil API lama
    @DeviceName           NVARCHAR(100) = NULL,
    @Force                BIT = 0                 -- Prompt 85: 1 = ambil alih setelah konfirmasi DIPAKAI|
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

        -- alter_87: stasiun semua divisi memilih resource per sesi di divisi mana pun,
        -- jadi tidak bisa sekaligus dikunci ke satu resource bawaan.
        IF @AllowAllDivisions = 1 AND @AllowResourceChange = 0
        BEGIN
            RAISERROR('Stasiun semua divisi tidak boleh dikunci ke resource bawaan.', 16, 1);
            RETURN;
        END

        -- @NewToken sudah parameter SP (dipakai CLAIM_PAIRING) -- DECLARE ulang gagal compile.
        -- Disamakan dengan versi yang sudah jalan di DB.
        SET @NewToken = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        INSERT INTO stations (station_code, station_name, division_id, station_token, is_active,
                               default_resource_id, allow_resource_change, enable_packing, allow_all_divisions,
                               created_at, created_by)
        VALUES (@StationCode, @StationName, @DivisionId, @NewToken, @IsActive,
                @DefaultResourceId, @AllowResourceChange, @EnablePacking, @AllowAllDivisions,
                SYSDATETIME(), @UserId);

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

        -- alter_87: stasiun semua divisi memilih resource per sesi di divisi mana pun,
        -- jadi tidak bisa sekaligus dikunci ke satu resource bawaan.
        IF @AllowAllDivisions = 1 AND @AllowResourceChange = 0
        BEGIN
            RAISERROR('Stasiun semua divisi tidak boleh dikunci ke resource bawaan.', 16, 1);
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
            allow_all_divisions = @AllowAllDivisions,
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

        -- Prompt 85: kode sekali pakai akan menimpa kode login terkunci -- harus lewat Buka Kunci.
        IF EXISTS (SELECT 1 FROM stations WHERE station_id = @Id AND pairing_code_locked = 1)
        BEGIN
            RAISERROR('Kode login stasiun ini terkunci. Buka kunci dulu untuk membuat kode pairing sekali pakai.', 16, 1);
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
    -- token lama langsung mati, satu perangkat aktif per station).
    --
    -- Prompt 85:
    -- - Kode terkunci (pairing_code_locked = 1) tidak hangus dan tidak dihapus saat diklaim.
    -- - Stasiun yang sedang dipegang perangkat LAIN -> error "DIPAKAI|nama|terakhir aktif"
    --   kecuali @Force = 1 (UI sudah minta konfirmasi). paired_device_id NULL = perangkat
    --   lama yang belum teradopsi TOUCH, BUKAN stasiun bebas. "Dipegang" = paired_at atau
    --   last_seen_at terisi (last_seen_at menutup token pra-Prompt 20 yang paired_at-nya NULL);
    --   UNPAIR mengosongkan keduanya.
    -- - @DeviceId NULL = dipanggil API lama (jendela deploy SQL -> API) -> perilaku lama,
    --   tanpa peringatan.
    -- - UPDLOCK/HOLDLOCK: dua perangkat yang klaim bersamaan tidak bisa sama-sama lolos cek.
    ELSE IF @Action = 'CLAIM_PAIRING'
    BEGIN
        SET XACT_ABORT ON;

        DECLARE @ClaimStationId INT, @ClaimLocked BIT, @ClaimPairedAt DATETIME2,
                @ClaimLastSeen DATETIME2, @ClaimHolderId VARCHAR(64), @ClaimHolderName NVARCHAR(100),
                @ClaimMsg NVARCHAR(400);

        BEGIN TRAN;

        SELECT @ClaimStationId = station_id,
               @ClaimLocked = pairing_code_locked,
               @ClaimPairedAt = paired_at,
               @ClaimLastSeen = last_seen_at,
               @ClaimHolderId = paired_device_id,
               @ClaimHolderName = paired_device_name
        FROM stations WITH (UPDLOCK, HOLDLOCK)
        WHERE UPPER(pairing_code) = UPPER(@PairingCode)
          AND is_active = 1 AND deleted_at IS NULL
          AND (pairing_code_locked = 1 OR pairing_code_expires_at > SYSDATETIME());

        IF @ClaimStationId IS NULL
        BEGIN
            ROLLBACK TRAN;
            RAISERROR('Kode pairing tidak valid atau sudah kedaluwarsa.', 16, 1);
            RETURN;
        END

        IF @DeviceId IS NOT NULL AND @Force = 0
           AND (@ClaimPairedAt IS NOT NULL OR @ClaimLastSeen IS NOT NULL)
           AND (@ClaimHolderId IS NULL OR @ClaimHolderId <> @DeviceId)
        BEGIN
            ROLLBACK TRAN;
            SET @ClaimMsg = N'DIPAKAI|'
                + ISNULL(NULLIF(REPLACE(@ClaimHolderName, N'|', N''), N''), N'Perangkat lama') + N'|'
                + ISNULL(CONVERT(NVARCHAR(19), ISNULL(@ClaimLastSeen, @ClaimPairedAt), 126), N'');
            -- '%s' supaya nama perangkat yang mengandung % tidak dibaca sebagai format.
            RAISERROR(N'%s', 16, 1, @ClaimMsg);
            RETURN;
        END

        UPDATE stations
        SET station_token = @NewToken,
            pairing_code = CASE WHEN pairing_code_locked = 1 THEN pairing_code ELSE NULL END,
            pairing_code_expires_at = NULL,
            paired_at = SYSDATETIME(),
            last_seen_at = SYSDATETIME(),
            paired_device_id = @DeviceId,
            paired_device_name = CASE WHEN @DeviceId IS NULL THEN NULL ELSE @DeviceName END,
            updated_at = SYSDATETIME()
        WHERE station_id = @ClaimStationId;

        COMMIT TRAN;

        SELECT @ClaimStationId AS StationId;
    END

    -- Prompt 20: putuskan perangkat -- station_token diganti GUID baru (token lama mati)
    -- baik dipicu admin ("Putuskan Perangkat") maupun perangkat sendiri (logout).
    -- Prompt 85: stasiun jadi bebas (paired_*/last_seen_at dikosongkan); kode login terkunci
    -- TIDAK ikut hilang -- hanya kode sekali pakai yang dihapus.
    ELSE IF @Action = 'UNPAIR'
    BEGIN
        DECLARE @UnpairedToken VARCHAR(64) = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        UPDATE stations
        SET station_token = @UnpairedToken,
            paired_at = NULL,
            paired_device_id = NULL,
            paired_device_name = NULL,
            last_seen_at = NULL,
            pairing_code = CASE WHEN pairing_code_locked = 1 THEN pairing_code ELSE NULL END,
            pairing_code_expires_at = NULL,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;
    END

    -- Prompt 85: kunci kode login -- dipakai untuk "Kunci Kode Login" DAN "Refresh Kode".
    -- Kode 10 karakter digenerate di API (retry kalau bentrok UX_stations_pairing_code).
    -- Tidak menyentuh station_token/paired_*: perangkat yang sedang jalan tetap jalan.
    ELSE IF @Action = 'LOCK_CODE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM stations WHERE station_id = @Id AND deleted_at IS NULL AND is_active = 1)
        BEGIN
            RAISERROR('Stasiun tidak ditemukan atau nonaktif.', 16, 1);
            RETURN;
        END

        UPDATE stations
        SET pairing_code = @PairingCode,
            pairing_code_expires_at = NULL,
            pairing_code_locked = 1,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;

        SELECT @PairingCode AS PairingCode;
    END

    -- Prompt 85: buka kunci -- kode login dihapus. Token tidak disentuh.
    ELSE IF @Action = 'UNLOCK_CODE'
    BEGIN
        UPDATE stations
        SET pairing_code = NULL,
            pairing_code_expires_at = NULL,
            pairing_code_locked = 0,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE station_id = @Id AND deleted_at IS NULL;
    END

    -- Prompt 85: kehadiran perangkat pemegang token (dipanggil RequireStationTokenAttribute,
    -- maks 1x/menit/stasiun). Sekaligus mengadopsi perangkat yang login sebelum alter_88:
    -- paired_device_id hanya diisi kalau masih NULL. Telemetri, bukan perubahan data --
    -- updated_at/updated_by sengaja tidak disentuh.
    ELSE IF @Action = 'TOUCH'
    BEGIN
        UPDATE stations
        SET last_seen_at = SYSDATETIME(),
            paired_device_name = CASE WHEN @DeviceId IS NOT NULL AND @DeviceName IS NOT NULL
                                           AND (paired_device_id IS NULL OR paired_device_id = @DeviceId)
                                      THEN @DeviceName ELSE paired_device_name END,
            paired_device_id = ISNULL(paired_device_id, @DeviceId)
        WHERE station_id = @Id AND deleted_at IS NULL;
    END
END;
GO

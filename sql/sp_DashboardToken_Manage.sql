-- Mutasi data dashboard_tokens (CREATE/UPDATE/REGENERATE/DELETE/TOUCH). Pengambilan data
-- ada di procedure terpisah: sp_DashboardToken_Select.sql. Token PENUH hanya pernah
-- dikembalikan oleh CREATE dan REGENERATE (sekali saja, saat itu juga) -- SELECT lain
-- (list/paged) tidak pernah menampilkannya, lihat sp_DashboardToken_Select.sql.
--
-- Token 5 karakter (pola sama dengan station pairing code) digenerate di C#
-- (DashboardTokenService.GenerateToken) dan dikirim lewat @Token -- SP TIDAK men-generate
-- sendiri lewat NEWID(), supaya charset-nya konsisten (menghindari karakter yang gampang
-- tertukar 0/O/l/1/I) dan C# bisa retry bila bentrok (lihat pesan error di bawah).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_DashboardToken_Manage
    @Action                  VARCHAR(20),
    @Id                      INT = NULL,
    @TokenName               VARCHAR(150) = NULL,
    @IsActive                BIT = 1,
    @RefreshIntervalMinutes  INT = 30,
    @Token                   VARCHAR(64) = NULL,   -- CREATE/REGENERATE (digenerate di C#) / TOUCH
    @UserId                  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action IN ('CREATE', 'UPDATE') AND @RefreshIntervalMinutes NOT IN (5, 10, 15, 20, 30, 60)
    BEGIN
        RAISERROR('Interval refresh harus salah satu dari 5, 10, 15, 20, 30, atau 60 menit.', 16, 1);
        RETURN;
    END

    IF @Action = 'CREATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM dashboard_tokens WHERE token_name = @TokenName AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Nama TV "%s" sudah digunakan.', 16, 1, @TokenName);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM dashboard_tokens WHERE dashboard_token = @Token AND deleted_at IS NULL)
        BEGIN
            RAISERROR('TOKEN_COLLISION|Token bentrok, coba lagi.', 16, 1);
            RETURN;
        END

        INSERT INTO dashboard_tokens (token_name, dashboard_token, is_active, refresh_interval_minutes, created_at, created_by)
        VALUES (@TokenName, @Token, @IsActive, @RefreshIntervalMinutes, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM dashboard_tokens
            WHERE token_name = @TokenName AND deleted_at IS NULL AND dashboard_token_id <> @Id
        )
        BEGIN
            RAISERROR('Nama TV "%s" sudah digunakan.', 16, 1, @TokenName);
            RETURN;
        END

        UPDATE dashboard_tokens
        SET token_name = @TokenName,
            is_active = @IsActive,
            refresh_interval_minutes = @RefreshIntervalMinutes,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE dashboard_token_id = @Id AND deleted_at IS NULL;
    END

    -- Token lama langsung mati -- TV yang masih memakainya akan ditolak (401) pada refresh
    -- berikutnya dan kembali ke layar aktivasi.
    ELSE IF @Action = 'REGENERATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM dashboard_tokens WHERE dashboard_token = @Token AND deleted_at IS NULL)
        BEGIN
            RAISERROR('TOKEN_COLLISION|Token bentrok, coba lagi.', 16, 1);
            RETURN;
        END

        UPDATE dashboard_tokens
        SET dashboard_token = @Token,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE dashboard_token_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE dashboard_tokens
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE dashboard_token_id = @Id AND deleted_at IS NULL;
    END

    -- Dipanggil oleh RequireDashboardTokenAttribute (di-throttle di memori API, tidak
    -- setiap request) -- murni menandai TV masih aktif, bukan aksi admin.
    ELSE IF @Action = 'TOUCH'
    BEGIN
        UPDATE dashboard_tokens
        SET last_seen_at = SYSDATETIME()
        WHERE dashboard_token = @Token AND is_active = 1 AND deleted_at IS NULL;
    END
END;
GO

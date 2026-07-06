-- Mutasi data divisions (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Division_Select.sql (SIS_Division_GetAll / SIS_Division_GetById).
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: divisions punya filtered unique index (UX_divisions_code),
-- dan setting ini "dibekukan" pada saat CREATE PROCEDURE, bukan dibaca dari sesi pemanggil.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Division_Manage
    @Action       VARCHAR(20),
    @Id           INT = NULL,
    @DivisionCode VARCHAR(30) = NULL,
    @DivisionName VARCHAR(150) = NULL,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM divisions WHERE division_code = @DivisionCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode divisi "%s" sudah digunakan.', 16, 1, @DivisionCode);
            RETURN;
        END

        INSERT INTO divisions (division_code, division_name, created_at, created_by)
        VALUES (@DivisionCode, @DivisionName, SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM divisions
            WHERE division_code = @DivisionCode AND deleted_at IS NULL AND division_id <> @Id
        )
        BEGIN
            RAISERROR('Kode divisi "%s" sudah digunakan.', 16, 1, @DivisionCode);
            RETURN;
        END

        UPDATE divisions
        SET division_code = @DivisionCode,
            division_name = @DivisionName,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE division_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE divisions
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE division_id = @Id AND deleted_at IS NULL;
    END
END;
GO

-- Mutasi data positions (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Position_Select.sql (SIS_Position_GetAll / SIS_Position_GetById).
-- Catatan: positions tidak punya kolom code / unique index, jadi tidak ada pengecekan duplikat.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Position_Manage
    @Action       VARCHAR(20),
    @Id           INT = NULL,
    @PositionName VARCHAR(150) = NULL,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO positions (position_name, created_at, created_by)
        VALUES (@PositionName, SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE positions
        SET position_name = @PositionName,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE position_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE positions
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE position_id = @Id AND deleted_at IS NULL;
    END
END;
GO

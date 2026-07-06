-- Mutasi data resources (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Resource_Select.sql (SIS_Resource_GetAll / SIS_Resource_GetById).
-- Tidak ada kolom kode/unique index di resources, jadi tidak ada pengecekan duplikat.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Resource_Manage
    @Action         VARCHAR(20),
    @Id             INT = NULL,
    @DivisionId     INT = NULL,
    @ResourceTypeId INT = NULL,
    @ResourceName   VARCHAR(150) = NULL,
    @IsActive       BIT = 1,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO resources (division_id, resource_type_id, resource_name, is_active, created_at, created_by)
        VALUES (@DivisionId, @ResourceTypeId, @ResourceName, @IsActive, SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE resources
        SET division_id = @DivisionId,
            resource_type_id = @ResourceTypeId,
            resource_name = @ResourceName,
            is_active = @IsActive,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE resource_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE resources
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE resource_id = @Id AND deleted_at IS NULL;
    END
END;
GO

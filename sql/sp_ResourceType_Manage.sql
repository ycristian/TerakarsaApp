-- Mutasi data resource_types (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_ResourceType_Select.sql (SIS_ResourceType_GetAll / SIS_ResourceType_GetById).
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: resource_types punya filtered unique index (UX_resource_types_code).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_ResourceType_Manage
    @Action           VARCHAR(20),
    @Id               INT = NULL,
    @ResourceTypeCode VARCHAR(30) = NULL,
    @ResourceTypeName VARCHAR(150) = NULL,
    @UserId           INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM resource_types WHERE resource_type_code = @ResourceTypeCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode tipe resource "%s" sudah digunakan.', 16, 1, @ResourceTypeCode);
            RETURN;
        END

        INSERT INTO resource_types (resource_type_code, resource_type_name, created_at, created_by)
        VALUES (@ResourceTypeCode, @ResourceTypeName, SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM resource_types
            WHERE resource_type_code = @ResourceTypeCode AND deleted_at IS NULL AND resource_type_id <> @Id
        )
        BEGIN
            RAISERROR('Kode tipe resource "%s" sudah digunakan.', 16, 1, @ResourceTypeCode);
            RETURN;
        END

        UPDATE resource_types
        SET resource_type_code = @ResourceTypeCode,
            resource_type_name = @ResourceTypeName,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE resource_type_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE resource_types
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE resource_type_id = @Id AND deleted_at IS NULL;
    END
END;
GO

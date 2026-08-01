-- Mutasi data resources (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Resource_Select.sql (SIS_Resource_GetAll / SIS_Resource_GetById).
-- Tidak ada kolom kode/unique index di resources, jadi tidak ada pengecekan duplikat.
--
-- Prompt 39: @CounterpartResourceId -- resource pasangan di divisi lanjutan (opsional).
-- Nilai dipakai apa adanya (BUKAN ISNULL ke nilai lama) -- user harus bisa mengosongkan
-- pasangan lewat UI, baik CREATE maupun UPDATE.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Resource_Manage
    @Action                  VARCHAR(20),
    @Id                      INT = NULL,
    @DivisionId              INT = NULL,
    @ResourceTypeId          INT = NULL,
    @ResourceName            VARCHAR(150) = NULL,
    @IsActive                BIT = 1,
    @IncludeInDashboard      BIT = 1,
    @CounterpartResourceId   INT = NULL,
    @UserId                  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action IN ('CREATE', 'UPDATE') AND @CounterpartResourceId IS NOT NULL
    BEGIN
        DECLARE @CounterpartDivisionId INT;
        SELECT @CounterpartDivisionId = division_id FROM resources
        WHERE resource_id = @CounterpartResourceId AND deleted_at IS NULL;

        IF @CounterpartDivisionId IS NULL
        BEGIN
            RAISERROR('Resource pasangan tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @Action = 'UPDATE' AND @CounterpartResourceId = @Id
        BEGIN
            RAISERROR('Resource pasangan tidak boleh diri sendiri.', 16, 1);
            RETURN;
        END

        IF @CounterpartDivisionId = @DivisionId
        BEGIN
            RAISERROR('Resource pasangan harus dari divisi lain.', 16, 1);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO resources (division_id, resource_type_id, resource_name, is_active, include_in_dashboard, counterpart_resource_id, created_at, created_by)
        VALUES (@DivisionId, @ResourceTypeId, @ResourceName, @IsActive, @IncludeInDashboard, @CounterpartResourceId, SYSDATETIME(), @UserId);

        SELECT SCOPE_IDENTITY() AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE resources
        SET division_id = @DivisionId,
            resource_type_id = @ResourceTypeId,
            resource_name = @ResourceName,
            is_active = @IsActive,
            include_in_dashboard = @IncludeInDashboard,
            counterpart_resource_id = @CounterpartResourceId,
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

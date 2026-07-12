-- Mutasi data projects (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Project_Select.sql (SIS_Project_GetAll / SIS_Project_GetById).
--
-- Prompt 18 -- @Action = 'SET_STATUS': ubah status manual project (ON_HOLD/COMPLETED/
-- CANCELLED) atau kembalikan ke otomatis (@ManualStatus = NULL, "Lanjutkan"/"Buka Kembali").
-- Status otomatis (Not Started/On Going) TIDAK disimpan -- hanya diturunkan di SP select.
-- ON_HOLD & CANCELLED wajib @StatusReason (komunikasi lintas divisi, tampil di detail
-- project & pesan error penolakan aksi produksi -- lihat sp_Bundle_Manage.sql /
-- sp_WorkflowLog_Manage.sql). COMPLETED dan NULL: reason opsional; saat NULL, status_reason
-- ikut dikosongkan (riwayat alasan lama tidak relevan lagi setelah dibuka kembali).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Project_Manage
    @Action       VARCHAR(20),
    @Id           INT = NULL,
    @CustomerId   INT = NULL,
    @ProjectMd    INT = NULL,
    @ProjectPic   INT = NULL,
    @ProjectName  VARCHAR(150) = NULL,
    @NoPo         VARCHAR(50) = NULL,
    @MaterialName VARCHAR(150) = NULL,
    @OrderDate    DATE = NULL,
    @StartDate    DATE = NULL,
    @Deadline     DATE = NULL,
    @DeliveryDate DATE = NULL,
    @ManualStatus VARCHAR(20) = NULL,
    @StatusReason VARCHAR(255) = NULL,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO projects (customer_id, project_md, project_pic, project_name, no_po, material_name, order_date, [start_date], deadline, delivery_date, created_at, created_by)
        VALUES (@CustomerId, @ProjectMd, @ProjectPic, @ProjectName, @NoPo, @MaterialName, @OrderDate, @StartDate, @Deadline, @DeliveryDate, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE projects
        SET customer_id = @CustomerId,
            project_md = @ProjectMd,
            project_pic = @ProjectPic,
            project_name = @ProjectName,
            no_po = @NoPo,
            material_name = @MaterialName,
            order_date = @OrderDate,
            [start_date] = @StartDate,
            deadline = @Deadline,
            delivery_date = @DeliveryDate,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE project_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE projects
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE project_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'SET_STATUS'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM projects WHERE project_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Project tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @ManualStatus IS NOT NULL AND @ManualStatus NOT IN ('ON_HOLD', 'COMPLETED', 'CANCELLED')
        BEGIN
            RAISERROR('Status tidak valid.', 16, 1);
            RETURN;
        END

        IF @ManualStatus IN ('ON_HOLD', 'CANCELLED') AND (@StatusReason IS NULL OR LTRIM(RTRIM(@StatusReason)) = '')
        BEGIN
            RAISERROR('Alasan wajib diisi untuk status ini.', 16, 1);
            RETURN;
        END

        UPDATE projects
        SET manual_status = @ManualStatus,
            status_reason = CASE WHEN @ManualStatus IS NULL THEN NULL ELSE @StatusReason END,
            status_changed_at = SYSDATETIME(),
            status_changed_by = @UserId,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE project_id = @Id AND deleted_at IS NULL;
    END
END;
GO

-- Mutasi data projects (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Project_Select.sql (SIS_Project_GetAll / SIS_Project_GetById).

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
    @OrderDate    DATE = NULL,
    @StartDate    DATE = NULL,
    @Deadline     DATE = NULL,
    @DeliveryDate DATE = NULL,
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO projects (customer_id, project_md, project_pic, project_name, no_po, order_date, [start_date], deadline, delivery_date, created_at, created_by)
        VALUES (@CustomerId, @ProjectMd, @ProjectPic, @ProjectName, @NoPo, @OrderDate, @StartDate, @Deadline, @DeliveryDate, SYSDATETIME(), @UserId);

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
END;
GO

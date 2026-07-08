-- Mutasi data workflow_templates + workflow_template_steps (CREATE/UPDATE/DELETE),
-- header + steps dalam satu transaksi. Steps dikirim sebagai JSON (@Steps, di-parse
-- dengan OPENJSON), sama pola dengan sp_SizePack_Manage.sql.
-- UPDATE: baris dengan Id -> update, baris tanpa Id (NULL) -> insert baru,
-- baris lama yang tidak ada lagi di JSON -> soft delete.
-- Pengambilan data ada di procedure terpisah: sp_WorkflowTemplate_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowTemplate_Manage
    @Action       VARCHAR(20),
    @Id           INT = NULL,
    @WorkflowCode VARCHAR(30) = NULL,
    @WorkflowName VARCHAR(150) = NULL,
    @Steps        NVARCHAR(MAX) = NULL,  -- JSON array: [{"Id":null,"StepName":"Cutting","DivisionId":1,"SortOrder":1}, ...]
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        IF EXISTS (SELECT 1 FROM workflow_templates WHERE workflow_code = @WorkflowCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode workflow "%s" sudah digunakan.', 16, 1, @WorkflowCode);
            RETURN;
        END

        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO workflow_templates (workflow_code, workflow_name, created_at, created_by)
            VALUES (@WorkflowCode, @WorkflowName, SYSDATETIME(), @UserId);

            DECLARE @NewTemplateId INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO workflow_template_steps (workflow_template_id, step_name, division_id, sort_order, requires_bundle, created_at, created_by)
            SELECT @NewTemplateId, j.StepName, j.DivisionId, j.SortOrder, j.RequiresBundle, SYSDATETIME(), @UserId
            FROM OPENJSON(@Steps)
                WITH (
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle'
                ) j;

            COMMIT TRAN;
            SELECT @NewTemplateId AS NewId;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM workflow_templates
            WHERE workflow_code = @WorkflowCode AND deleted_at IS NULL AND workflow_template_id <> @Id
        )
        BEGIN
            RAISERROR('Kode workflow "%s" sudah digunakan.', 16, 1, @WorkflowCode);
            RETURN;
        END

        BEGIN TRAN;
        BEGIN TRY
            UPDATE workflow_templates
            SET workflow_code = @WorkflowCode,
                workflow_name = @WorkflowName,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE workflow_template_id = @Id AND deleted_at IS NULL;

            -- Baris dengan Id -> update
            UPDATE wts
            SET wts.step_name = j.StepName,
                wts.division_id = j.DivisionId,
                wts.sort_order = j.SortOrder,
                wts.requires_bundle = j.RequiresBundle,
                wts.updated_at = SYSDATETIME(),
                wts.updated_by = @UserId
            FROM workflow_template_steps wts
            INNER JOIN OPENJSON(@Steps)
                WITH (
                    Id             INT          '$.Id',
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle'
                ) j ON j.Id = wts.step_id
            WHERE wts.workflow_template_id = @Id AND wts.deleted_at IS NULL;

            -- Baris tanpa Id -> insert baru
            INSERT INTO workflow_template_steps (workflow_template_id, step_name, division_id, sort_order, requires_bundle, created_at, created_by)
            SELECT @Id, j.StepName, j.DivisionId, j.SortOrder, j.RequiresBundle, SYSDATETIME(), @UserId
            FROM OPENJSON(@Steps)
                WITH (
                    Id             INT          '$.Id',
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle'
                ) j
            WHERE j.Id IS NULL;

            -- Baris lama yang sudah tidak ada di JSON -> soft delete
            UPDATE wts
            SET wts.deleted_at = SYSDATETIME(),
                wts.deleted_by = @UserId
            FROM workflow_template_steps wts
            WHERE wts.workflow_template_id = @Id AND wts.deleted_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Steps) WITH (Id INT '$.Id') j
                  WHERE j.Id = wts.step_id
              );

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            UPDATE workflow_templates
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE workflow_template_id = @Id AND deleted_at IS NULL;

            UPDATE workflow_template_steps
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE workflow_template_id = @Id AND deleted_at IS NULL;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END
END;
GO

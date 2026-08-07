-- Mutasi data workflow_templates + workflow_template_steps (CREATE/UPDATE/DELETE),
-- header + steps dalam satu transaksi. Steps dikirim sebagai JSON (@Steps, di-parse
-- dengan OPENJSON), sama pola dengan sp_SizePack_Manage.sql.
-- UPDATE: baris dengan Id -> update, baris tanpa Id (NULL) -> insert baru,
-- baris lama yang tidak ada lagi di JSON -> soft delete.
-- Pengambilan data ada di procedure terpisah: sp_WorkflowTemplate_Select.sql.
--
-- Prompt 41 -- print_kupon per step: sama pola dengan auto_receive (JSON @Steps membawa
-- PrintKupon). v1 hanya valid utk step ber-bundle -- step manapun di JSON dengan
-- PrintKupon = 1 DAN RequiresBundle = 0 ditolak (RAISERROR), baik CREATE maupun UPDATE.
--
-- Fix: CREATE & UPDATE sekarang menolak (RAISERROR) step dengan DivisionId kosong ATAU
-- menunjuk divisi yang sudah di-soft-delete -- sebelumnya cuma ditegakkan lewat NOT NULL/FK
-- divisions, yang tidak menangkap divisi yang deleted_at-nya terisi (baris masih ada di FK,
-- tapi sudah tidak boleh dipakai) dan melempar error SQL mentah alih-alih pesan Indonesia
-- kalau DivisionId NULL/0 dari client. Client (WorkflowTemplate.razor) sudah menolak baris
-- tanpa divisi sebelum submit -- guard ini menutup jalur langsung ke API/SP.

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

        -- Fix: divisi tiap step wajib diisi dan harus divisi yang masih hidup -- sebelum ini
        -- cuma ditegakkan lewat NOT NULL/FK divisions, yang tidak menolak divisi yang sudah
        -- di-soft-delete (deleted_at terisi tapi baris masih ada, FK tetap lolos) dan
        -- melempar error SQL mentah alih-alih pesan Indonesia kalau DivisionId kosong.
        IF EXISTS (
            SELECT 1 FROM OPENJSON(@Steps) WITH (DivisionId INT '$.DivisionId') j
            WHERE j.DivisionId IS NULL
               OR NOT EXISTS (SELECT 1 FROM divisions d WHERE d.division_id = j.DivisionId AND d.deleted_at IS NULL)
        )
        BEGIN
            RAISERROR('Setiap step wajib memiliki divisi yang valid.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM OPENJSON(@Steps) WITH (SortOrder INT '$.SortOrder', RequiresBundle BIT '$.RequiresBundle') nb
            WHERE nb.RequiresBundle = 0
              AND EXISTS (
                  SELECT 1 FROM OPENJSON(@Steps) WITH (SortOrder INT '$.SortOrder', RequiresBundle BIT '$.RequiresBundle') b
                  WHERE b.RequiresBundle = 1 AND b.SortOrder < nb.SortOrder
              )
        )
        BEGIN
            RAISERROR('Step tanpa bundle harus berada sebelum semua step ber-bundle.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM OPENJSON(@Steps) WITH (StepName VARCHAR(150) '$.StepName', RequiresBundle BIT '$.RequiresBundle', PrintKupon BIT '$.PrintKupon')
            WHERE ISNULL(PrintKupon, 0) = 1 AND RequiresBundle = 0
        )
        BEGIN
            RAISERROR('Kupon hanya berlaku untuk step ber-bundle.', 16, 1);
            RETURN;
        END

        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO workflow_templates (workflow_code, workflow_name, created_at, created_by)
            VALUES (@WorkflowCode, @WorkflowName, SYSDATETIME(), @UserId);

            DECLARE @NewTemplateId INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO workflow_template_steps (workflow_template_id, step_name, division_id, sort_order, requires_bundle, auto_receive, print_kupon, created_at, created_by)
            SELECT @NewTemplateId, j.StepName, j.DivisionId, j.SortOrder, j.RequiresBundle, ISNULL(j.AutoReceive, 0), ISNULL(j.PrintKupon, 0), SYSDATETIME(), @UserId
            FROM OPENJSON(@Steps)
                WITH (
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle',
                    AutoReceive    BIT          '$.AutoReceive',
                    PrintKupon     BIT          '$.PrintKupon'
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

        -- Fix: lihat komentar di CREATE.
        IF EXISTS (
            SELECT 1 FROM OPENJSON(@Steps) WITH (DivisionId INT '$.DivisionId') j
            WHERE j.DivisionId IS NULL
               OR NOT EXISTS (SELECT 1 FROM divisions d WHERE d.division_id = j.DivisionId AND d.deleted_at IS NULL)
        )
        BEGIN
            RAISERROR('Setiap step wajib memiliki divisi yang valid.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM OPENJSON(@Steps) WITH (SortOrder INT '$.SortOrder', RequiresBundle BIT '$.RequiresBundle') nb
            WHERE nb.RequiresBundle = 0
              AND EXISTS (
                  SELECT 1 FROM OPENJSON(@Steps) WITH (SortOrder INT '$.SortOrder', RequiresBundle BIT '$.RequiresBundle') b
                  WHERE b.RequiresBundle = 1 AND b.SortOrder < nb.SortOrder
              )
        )
        BEGIN
            RAISERROR('Step tanpa bundle harus berada sebelum semua step ber-bundle.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM OPENJSON(@Steps) WITH (StepName VARCHAR(150) '$.StepName', RequiresBundle BIT '$.RequiresBundle', PrintKupon BIT '$.PrintKupon')
            WHERE ISNULL(PrintKupon, 0) = 1 AND RequiresBundle = 0
        )
        BEGIN
            RAISERROR('Kupon hanya berlaku untuk step ber-bundle.', 16, 1);
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
                wts.auto_receive = ISNULL(j.AutoReceive, 0),
                wts.print_kupon = ISNULL(j.PrintKupon, 0),
                wts.updated_at = SYSDATETIME(),
                wts.updated_by = @UserId
            FROM workflow_template_steps wts
            INNER JOIN OPENJSON(@Steps)
                WITH (
                    Id             INT          '$.Id',
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle',
                    AutoReceive    BIT          '$.AutoReceive',
                    PrintKupon     BIT          '$.PrintKupon'
                ) j ON j.Id = wts.step_id
            WHERE wts.workflow_template_id = @Id AND wts.deleted_at IS NULL;

            -- Baris lama yang sudah tidak ada di JSON -> soft delete. HARUS dijalankan
            -- SEBELUM insert baris baru di bawah -- baris baru belum punya Id di JSON
            -- (Id null) sehingga kalau insert duluan, baris itu langsung cocok "tidak
            -- ada di JSON" dan ikut ke-soft-delete pada transaksi yang sama (bug lama:
            -- created_at == deleted_at persis pada baris yang baru ditambahkan).
            UPDATE wts
            SET wts.deleted_at = SYSDATETIME(),
                wts.deleted_by = @UserId
            FROM workflow_template_steps wts
            WHERE wts.workflow_template_id = @Id AND wts.deleted_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Steps) WITH (Id INT '$.Id') j
                  WHERE j.Id = wts.step_id
              );

            -- Baris tanpa Id -> insert baru
            INSERT INTO workflow_template_steps (workflow_template_id, step_name, division_id, sort_order, requires_bundle, auto_receive, print_kupon, created_at, created_by)
            SELECT @Id, j.StepName, j.DivisionId, j.SortOrder, j.RequiresBundle, ISNULL(j.AutoReceive, 0), ISNULL(j.PrintKupon, 0), SYSDATETIME(), @UserId
            FROM OPENJSON(@Steps)
                WITH (
                    Id             INT          '$.Id',
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle',
                    AutoReceive    BIT          '$.AutoReceive',
                    PrintKupon     BIT          '$.PrintKupon'
                ) j
            WHERE j.Id IS NULL;

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

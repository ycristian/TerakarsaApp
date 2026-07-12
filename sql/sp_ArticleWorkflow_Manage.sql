-- Mutasi data article_workflows (APPLY/SAVE). Template hanyalah arahan awal:
-- APPLY menyalin steps dari workflow_template_steps ke article_workflows dengan
-- workflow_template_id diisi sebagai info asal. Setelah itu workflow sepenuhnya
-- milik artikel; SAVE tidak lagi menyentuh workflow_template_id baris yang sudah ada
-- dan mengisi NULL untuk baris manual baru.
-- Guard SAVE: baris yang mau dihapus (tidak ada lagi di JSON) ditolak jika sudah
-- punya log hidup di article_workflow_logs (tabel disiapkan untuk Phase E).
-- Pengambilan data ada di procedure terpisah: sp_ArticleWorkflow_Select.sql.
--
-- Prompt 17 -- step Bundling implisit (article_workflows.is_bundling = 1): disisipkan
-- OTOMATIS oleh SP ini (APPLY & SAVE) tepat sebelum step ber-bundle pertama yang bukan
-- Bundling (requires_bundle = 1 AND is_bundling = 0), TIDAK pernah datang dari
-- workflow_template_steps atau dari payload @Steps (client tidak mengenalnya). SAVE
-- mengecualikan baris ini dari deteksi "dihapus user" dan dari update/insert manual,
-- lalu menyisipkan/menghapus/mereposisi ulang secara terpisah setelah operasi user selesai.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_ArticleWorkflow_Manage
    @Action             VARCHAR(20),
    @ArticleId          INT = NULL,
    @WorkflowTemplateId INT = NULL,
    @Steps              NVARCHAR(MAX) = NULL,  -- JSON array: [{"Id":null,"StepName":"Cutting","DivisionId":1,"SortOrder":1}, ...]
    @UserId             INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'APPLY'
    BEGIN
        IF EXISTS (SELECT 1 FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Artikel ini sudah memiliki workflow. Template tidak bisa diterapkan ulang.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM workflow_templates WHERE workflow_template_id = @WorkflowTemplateId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Template workflow tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM workflow_template_steps nb
            WHERE nb.workflow_template_id = @WorkflowTemplateId AND nb.deleted_at IS NULL AND nb.requires_bundle = 0
              AND EXISTS (
                  SELECT 1 FROM workflow_template_steps b
                  WHERE b.workflow_template_id = @WorkflowTemplateId AND b.deleted_at IS NULL
                    AND b.requires_bundle = 1 AND b.sort_order < nb.sort_order
              )
        )
        BEGIN
            RAISERROR('Step tanpa bundle harus berada sebelum semua step ber-bundle.', 16, 1);
            RETURN;
        END

        DECLARE @ApplyHasBundle BIT = CASE WHEN EXISTS (
            SELECT 1 FROM workflow_template_steps
            WHERE workflow_template_id = @WorkflowTemplateId AND deleted_at IS NULL AND requires_bundle = 1
        ) THEN 1 ELSE 0 END;

        DECLARE @ApplyBundlingDivisionId INT;
        IF @ApplyHasBundle = 1
        BEGIN
            SELECT @ApplyBundlingDivisionId = division_id FROM divisions WHERE division_code = 'BUNDLING' AND deleted_at IS NULL;

            IF @ApplyBundlingDivisionId IS NULL
            BEGIN
                RAISERROR('Divisi Bundling belum di-seed.', 16, 1);
                RETURN;
            END
        END

        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO article_workflows (article_id, workflow_template_id, step_name, division_id, sort_order, requires_bundle, created_at, created_by)
            SELECT @ArticleId, @WorkflowTemplateId, wts.step_name, wts.division_id, wts.sort_order, wts.requires_bundle, SYSDATETIME(), @UserId
            FROM workflow_template_steps wts
            WHERE wts.workflow_template_id = @WorkflowTemplateId AND wts.deleted_at IS NULL;

            IF @ApplyHasBundle = 1
            BEGIN
                DECLARE @ApplyFirstBundleSort INT;
                SELECT @ApplyFirstBundleSort = MIN(sort_order)
                FROM workflow_template_steps
                WHERE workflow_template_id = @WorkflowTemplateId AND deleted_at IS NULL AND requires_bundle = 1;

                UPDATE article_workflows
                SET sort_order = sort_order + 1
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1;

                INSERT INTO article_workflows (article_id, workflow_template_id, step_name, division_id, sort_order, requires_bundle, is_bundling, created_at, created_by)
                VALUES (@ArticleId, @WorkflowTemplateId, 'Bundling', @ApplyBundlingDivisionId, @ApplyFirstBundleSort, 1, 1, SYSDATETIME(), @UserId);
            END

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'SAVE'
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM article_workflows aw
            INNER JOIN article_workflow_logs awl ON awl.article_workflow_id = aw.article_workflow_id AND awl.deleted_at IS NULL
            WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL AND aw.is_bundling = 0
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Steps) WITH (Id INT '$.Id') j
                  WHERE j.Id = aw.article_workflow_id
              )
        )
        BEGIN
            RAISERROR('Tidak bisa menghapus step yang sudah memiliki log produksi.', 16, 1);
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

        BEGIN TRAN;
        BEGIN TRY
            -- Baris dengan Id -> update (workflow_template_id asal tidak diubah). JSON tidak
            -- pernah memuat baris is_bundling = 1 sehingga join ini otomatis melewatinya.
            UPDATE aw
            SET aw.step_name = j.StepName,
                aw.division_id = j.DivisionId,
                aw.sort_order = j.SortOrder,
                aw.requires_bundle = j.RequiresBundle,
                aw.updated_at = SYSDATETIME(),
                aw.updated_by = @UserId
            FROM article_workflows aw
            INNER JOIN OPENJSON(@Steps)
                WITH (
                    Id             INT          '$.Id',
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle'
                ) j ON j.Id = aw.article_workflow_id
            WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL;

            -- Baris tanpa Id -> insert baru, workflow_template_id = NULL (step manual)
            INSERT INTO article_workflows (article_id, workflow_template_id, step_name, division_id, sort_order, requires_bundle, created_at, created_by)
            SELECT @ArticleId, NULL, j.StepName, j.DivisionId, j.SortOrder, j.RequiresBundle, SYSDATETIME(), @UserId
            FROM OPENJSON(@Steps)
                WITH (
                    Id             INT          '$.Id',
                    StepName       VARCHAR(150) '$.StepName',
                    DivisionId     INT          '$.DivisionId',
                    SortOrder      INT          '$.SortOrder',
                    RequiresBundle BIT          '$.RequiresBundle'
                ) j
            WHERE j.Id IS NULL;

            -- Baris lama yang sudah tidak ada di JSON -> soft delete (sudah lolos guard log di
            -- atas). is_bundling = 1 dikecualikan -- baris itu memang tidak pernah ada di JSON,
            -- bukan berarti "dihapus user" (dikelola terpisah di bawah).
            UPDATE aw
            SET aw.deleted_at = SYSDATETIME(),
                aw.deleted_by = @UserId
            FROM article_workflows aw
            WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL AND aw.is_bundling = 0
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Steps) WITH (Id INT '$.Id') j
                  WHERE j.Id = aw.article_workflow_id
              );

            -- Prompt 17: kelola step Bundling implisit sesuai hasil akhir step user di atas.
            DECLARE @SaveHasBundleAfter BIT = CASE WHEN EXISTS (
                SELECT 1 FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 0 AND requires_bundle = 1
            ) THEN 1 ELSE 0 END;

            DECLARE @SaveBundlingId INT;
            SELECT @SaveBundlingId = article_workflow_id
            FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

            IF @SaveHasBundleAfter = 0 AND @SaveBundlingId IS NOT NULL
            BEGIN
                IF EXISTS (SELECT 1 FROM article_workflow_logs WHERE article_workflow_id = @SaveBundlingId AND deleted_at IS NULL)
                BEGIN
                    RAISERROR('Step Bundling sudah memiliki log produksi (bundle sudah dibuat). Tidak bisa menghapus semua step ber-bundle.', 16, 1);
                    ROLLBACK TRAN;
                    RETURN;
                END

                UPDATE article_workflows
                SET deleted_at = SYSDATETIME(), deleted_by = @UserId
                WHERE article_workflow_id = @SaveBundlingId;

                SET @SaveBundlingId = NULL;
            END
            ELSE IF @SaveHasBundleAfter = 1 AND @SaveBundlingId IS NULL
            BEGIN
                DECLARE @SaveBundlingDivisionId INT;
                SELECT @SaveBundlingDivisionId = division_id FROM divisions WHERE division_code = 'BUNDLING' AND deleted_at IS NULL;

                IF @SaveBundlingDivisionId IS NULL
                BEGIN
                    RAISERROR('Divisi Bundling belum di-seed.', 16, 1);
                    ROLLBACK TRAN;
                    RETURN;
                END

                INSERT INTO article_workflows (article_id, workflow_template_id, step_name, division_id, sort_order, requires_bundle, is_bundling, created_at, created_by)
                VALUES (@ArticleId, NULL, 'Bundling', @SaveBundlingDivisionId, 0, 1, 1, SYSDATETIME(), @UserId);

                SET @SaveBundlingId = CAST(SCOPE_IDENTITY() AS INT);
            END

            IF @SaveHasBundleAfter = 1
            BEGIN
                -- Posisikan Bundling tepat sebelum step station ber-bundle pertama, lalu
                -- renumber SEMUA step hidup artikel secara berurutan (cara paling aman --
                -- lihat prompt 17) supaya sort_order selalu rapat tanpa celah/tabrakan.
                DECLARE @SaveMinStationBundleSort INT;
                SELECT @SaveMinStationBundleSort = MIN(sort_order)
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 0 AND requires_bundle = 1;

                UPDATE article_workflows SET sort_order = @SaveMinStationBundleSort WHERE article_workflow_id = @SaveBundlingId;

                ;WITH Ordered AS (
                    SELECT article_workflow_id,
                           ROW_NUMBER() OVER (
                               ORDER BY sort_order ASC,
                                        CASE WHEN is_bundling = 1 THEN 0 ELSE 1 END ASC,
                                        article_workflow_id ASC
                           ) AS rn
                    FROM article_workflows
                    WHERE article_id = @ArticleId AND deleted_at IS NULL
                )
                UPDATE aw
                SET aw.sort_order = o.rn
                FROM article_workflows aw
                INNER JOIN Ordered o ON o.article_workflow_id = aw.article_workflow_id;
            END

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END
END;
GO

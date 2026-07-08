-- Mutasi data article_workflow_logs (CREATE/DELETE — LOG MURNI, tanpa UPDATE).
-- Pengambilan data ada di sp_WorkflowLog_Select.sql.
-- Aturan (level artikel, bundle_id NULL — alur per-bundle menyusul di Prompt 12):
--   1. article_workflows target harus hidup.
--   2. COMPLETED: requires_bundle = 1 -> BundleId wajib; requires_bundle = 0 -> BundleId harus NULL.
--      RECEIVED: BundleId boleh NULL apa pun flag-nya.
--   3. BundleId diisi -> bundles.article_id harus = article_workflows.article_id.
--   4. COMPLETED butuh RECEIVED hidup di step yang sama, KECUALI step itu sort_order
--      terkecil (hidup) di artikelnya.
--   5. Tolak COMPLETED ganda dan RECEIVED ganda di step yang sama.
--   6. Qty tidak boleh negatif. TargetDivisionId wajib untuk COMPLETED kecuali step
--      itu sort_order terbesar (step terakhir) di artikelnya.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowLog_Manage
    @Action            VARCHAR(20),
    @Id                INT = NULL,
    @ArticleWorkflowId INT = NULL,
    @BundleId          INT = NULL,
    @ResourceId        INT = NULL,
    @QtyOk             INT = 0,
    @QtyRejectPrint    INT = 0,
    @QtyRejectFabric   INT = 0,
    @QtyRejectSewing   INT = 0,
    @QtyRework         INT = 0,
    @Remark            VARCHAR(500) = NULL,
    @TargetDivisionId  INT = NULL,
    @Status            VARCHAR(20) = NULL,
    @UserId            INT = NULL,
    @DeleteReason      VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        DECLARE @DivisionId INT, @RequiresBundle BIT, @ArticleId INT, @SortOrder INT;

        SELECT @DivisionId = division_id, @RequiresBundle = requires_bundle,
               @ArticleId = article_id, @SortOrder = sort_order
        FROM article_workflows
        WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL;

        IF @DivisionId IS NULL
        BEGIN
            RAISERROR('Step workflow tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0 OR @QtyRework < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        DECLARE @MinSort INT, @MaxSort INT;
        SELECT @MinSort = MIN(sort_order), @MaxSort = MAX(sort_order)
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL;

        IF @Status = 'COMPLETED'
        BEGIN
            IF @RequiresBundle = 1 AND @BundleId IS NULL
            BEGIN
                RAISERROR('Step ini butuh bundle. Bundle wajib diisi.', 16, 1);
                RETURN;
            END

            IF @RequiresBundle = 0 AND @BundleId IS NOT NULL
            BEGIN
                RAISERROR('Step ini tidak butuh bundle. Bundle harus kosong.', 16, 1);
                RETURN;
            END

            IF @SortOrder > @MinSort AND NOT EXISTS (
                SELECT 1 FROM article_workflow_logs
                WHERE article_workflow_id = @ArticleWorkflowId AND [status] = 'RECEIVED' AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Step ini belum diterima (RECEIVED). Terima dulu sebelum menyelesaikan.', 16, 1);
                RETURN;
            END

            IF EXISTS (
                SELECT 1 FROM article_workflow_logs
                WHERE article_workflow_id = @ArticleWorkflowId AND [status] = 'COMPLETED' AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Step ini sudah pernah diselesaikan.', 16, 1);
                RETURN;
            END

            IF @SortOrder < @MaxSort AND @TargetDivisionId IS NULL
            BEGIN
                RAISERROR('Divisi tujuan wajib diisi.', 16, 1);
                RETURN;
            END
        END
        ELSE IF @Status = 'RECEIVED'
        BEGIN
            IF EXISTS (
                SELECT 1 FROM article_workflow_logs
                WHERE article_workflow_id = @ArticleWorkflowId AND [status] = 'RECEIVED' AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Step ini sudah pernah diterima.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            RAISERROR('Status tidak valid.', 16, 1);
            RETURN;
        END

        IF @BundleId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND article_id = @ArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Bundle tidak sesuai dengan artikel step ini.', 16, 1);
            RETURN;
        END

        INSERT INTO article_workflow_logs (
            article_workflow_id, bundle_id, division_id, resource_id, employee_id,
            qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_rework,
            remark, target_division_id, [status], created_at, created_by
        )
        VALUES (
            @ArticleWorkflowId, @BundleId, @DivisionId, @ResourceId, NULL,
            @QtyOk, @QtyRejectPrint, @QtyRejectFabric, @QtyRejectSewing, @QtyRework,
            @Remark, @TargetDivisionId, @Status, SYSDATETIME(), @UserId
        );

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF @DeleteReason IS NULL OR LTRIM(RTRIM(@DeleteReason)) = ''
        BEGIN
            RAISERROR('Alasan hapus wajib diisi.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            delete_reason = @DeleteReason
        WHERE workflow_log_id = @Id AND deleted_at IS NULL;
    END
END;
GO

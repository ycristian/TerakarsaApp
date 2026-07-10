-- Mutasi data article_workflow_logs (Prompt 12b: model 1-baris-per-serah-terima).
-- Pengambilan data ada di sp_WorkflowLog_Select.sql.
--
-- @Action = 'CREATE' (= pekerjaan step selesai, dulu berstatus 'COMPLETED'):
--   Step non-bundle (requires_bundle = 0, @BundleId harus NULL):
--     - Boleh berkali-kali, tanpa prasyarat apa pun (bukan lagi prasyarat step ber-bundle).
--     - @ArticleSizeId wajib diisi dan harus milik artikel step itu.
--   Step ber-bundle (requires_bundle = 1, @BundleId wajib, milik artikel yang sama):
--     - Maksimal satu baris hidup per (step, bundle) -- tolak ganda.
--     - Step ber-bundle PERTAMA (MIN sort_order hidup di antara requires_bundle = 1):
--       tanpa prasyarat baris sebelumnya; kalau bundles.resource_id diisi, @ResourceId
--       wajib sama (bundle ditugaskan ke line tertentu).
--     - Step ber-bundle SELANJUTNYA: baris step ber-bundle tepat sebelumnya (bundle
--       sama) harus ada, received_at sudah terisi, dan target_division_id-nya = divisi
--       step ini (baru diserahkan & diterima ke divisi ini).
--     - @ArticleSizeId harus NULL (size sudah melekat di bundle).
--   Umum: qty tidak boleh negatif; @ActingDivisionId (diisi dari token stasiun bila ada)
--   harus sama dengan divisi step, kalau tidak ditolak. target_division_id TIDAK LAGI
--   diterima dari pemanggil -- dihitung otomatis di sini dari urutan workflow (divisi
--   milik step hidup berikutnya, sort_order tepat di atas; NULL kalau ini step terakhir
--   artikel). Ini membuat "divisi tujuan" terkunci sesuai urutan, bukan pilihan bebas.
--
-- @Action = 'UPDATE' (revisi data SEBELUM diterima -- dipakai oleh divisi PEMBUAT baris,
-- bukan divisi tujuan): boleh mengubah qty_*, remark, article_size_id selama baris masih
-- hidup DAN received_at masih NULL (belum diserahkan/diterima). @ActingDivisionId (bila
-- diisi) harus = division_id baris ini (divisi yang membuatnya), bukan target_division_id.
-- Begitu received_at terisi (lewat RECEIVE), baris terkunci -- UPDATE ditolak.
--
-- @Action = 'RECEIVE' (pengganti log RECEIVED terpisah pada model lama):
--   UPDATE satu-satunya yang diizinkan pada log: received_at, received_by_resource_id,
--   received_remark pada baris @Id. Baris harus hidup, received_at masih NULL, dan
--   target_division_id tidak NULL (baris tanpa tujuan serah tidak bisa "diterima").
--   @ActingDivisionId (bila diisi) harus = target_division_id baris tsb.
--
-- @Action = 'DELETE': soft delete + alasan wajib. Tambahan (Prompt 12b): tolak kalau
-- baris ber-bundle ini sudah dipakai sebagai dasar step berikutnya -- ada baris hidup
-- di step sesudahnya (sort_order lebih besar, artikel sama) untuk bundle yang sama.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowLog_Manage
    @Action              VARCHAR(20),
    @Id                  INT = NULL,
    @ArticleWorkflowId   INT = NULL,
    @BundleId            INT = NULL,
    @ArticleSizeId       INT = NULL,
    @ResourceId          INT = NULL,
    @QtyOk               INT = 0,
    @QtyRejectPrint      INT = 0,
    @QtyRejectFabric     INT = 0,
    @QtyRejectSewing     INT = 0,
    @QtyRework           INT = 0,
    @Remark              VARCHAR(500) = NULL,
    @UserId              INT = NULL,
    @DeleteReason        VARCHAR(255) = NULL,
    @ActingDivisionId    INT = NULL,
    @ReceivedByResourceId INT = NULL,
    @ReceivedRemark      VARCHAR(500) = NULL
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

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @DivisionId
        BEGIN
            RAISERROR('Step ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0 OR @QtyRework < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        DECLARE @MaxSort INT;
        SELECT @MaxSort = MAX(sort_order) FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL;

        -- Divisi tujuan terkunci sesuai urutan workflow: divisi step hidup berikutnya
        -- (NULL kalau step ini adalah step terakhir artikel -- tidak ada serah lanjutan).
        DECLARE @ComputedTargetDivisionId INT;
        SELECT TOP 1 @ComputedTargetDivisionId = division_id
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order > @SortOrder
        ORDER BY sort_order ASC;

        IF @RequiresBundle = 0
        BEGIN
            IF @BundleId IS NOT NULL
            BEGIN
                RAISERROR('Step ini tidak butuh bundle. Bundle harus kosong.', 16, 1);
                RETURN;
            END

            IF @ArticleSizeId IS NULL
            BEGIN
                RAISERROR('Size wajib dipilih untuk step ini.', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM article_sizes
                WHERE article_size_id = @ArticleSizeId AND article_id = @ArticleId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Size tidak sesuai dengan artikel step ini.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            IF @BundleId IS NULL
            BEGIN
                RAISERROR('Step ini butuh bundle. Bundle wajib diisi.', 16, 1);
                RETURN;
            END

            IF @ArticleSizeId IS NOT NULL
            BEGIN
                RAISERROR('Step ini tidak menerima input size (sudah melekat pada bundle).', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND article_id = @ArticleId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Bundle tidak sesuai dengan artikel step ini.', 16, 1);
                RETURN;
            END

            IF EXISTS (
                SELECT 1 FROM article_workflow_logs
                WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Step ini sudah pernah dicatat untuk bundle ini.', 16, 1);
                RETURN;
            END

            DECLARE @FirstBundleSort INT;
            SELECT @FirstBundleSort = MIN(sort_order)
            FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1;

            IF @SortOrder = @FirstBundleSort
            BEGIN
                DECLARE @BundleResourceId INT;
                SELECT @BundleResourceId = resource_id FROM bundles WHERE bundle_id = @BundleId;

                IF @BundleResourceId IS NOT NULL AND (@ResourceId IS NULL OR @BundleResourceId <> @ResourceId)
                BEGIN
                    RAISERROR('Bundle ini ditugaskan ke line lain.', 16, 1);
                    RETURN;
                END
            END
            ELSE
            BEGIN
                DECLARE @PrevArticleWorkflowId INT;
                SELECT TOP 1 @PrevArticleWorkflowId = article_workflow_id
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1 AND sort_order < @SortOrder
                ORDER BY sort_order DESC;

                IF @PrevArticleWorkflowId IS NULL OR NOT EXISTS (
                    SELECT 1 FROM article_workflow_logs
                    WHERE article_workflow_id = @PrevArticleWorkflowId AND bundle_id = @BundleId
                      AND received_at IS NOT NULL AND target_division_id = @DivisionId AND deleted_at IS NULL
                )
                BEGIN
                    RAISERROR('Bundle belum diterima divisi ini.', 16, 1);
                    RETURN;
                END
            END
        END

        INSERT INTO article_workflow_logs (
            article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
            qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_rework,
            remark, target_division_id, created_at, created_by
        )
        VALUES (
            @ArticleWorkflowId, @BundleId, @ArticleSizeId, @DivisionId, @ResourceId, NULL,
            @QtyOk, @QtyRejectPrint, @QtyRejectFabric, @QtyRejectSewing, @QtyRework,
            @Remark, @ComputedTargetDivisionId, SYSDATETIME(), @UserId
        );

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        DECLARE @UpdDivisionId INT, @UpdBundleId INT, @UpdReceivedAt DATETIME2, @UpdArticleId INT;
        SELECT @UpdDivisionId = awl.division_id, @UpdBundleId = awl.bundle_id,
               @UpdReceivedAt = awl.received_at, @UpdArticleId = aw.article_id
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id AND awl.deleted_at IS NULL;

        IF @UpdDivisionId IS NULL
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @UpdReceivedAt IS NOT NULL
        BEGIN
            RAISERROR('Log ini sudah diterima, tidak bisa diubah lagi.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @UpdDivisionId
        BEGIN
            RAISERROR('Log ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0 OR @QtyRework < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        IF @UpdBundleId IS NULL
        BEGIN
            IF @ArticleSizeId IS NULL
            BEGIN
                RAISERROR('Size wajib dipilih untuk step ini.', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM article_sizes
                WHERE article_size_id = @ArticleSizeId AND article_id = @UpdArticleId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Size tidak sesuai dengan artikel step ini.', 16, 1);
                RETURN;
            END
        END
        ELSE IF @ArticleSizeId IS NOT NULL
        BEGIN
            RAISERROR('Step ini tidak menerima input size (sudah melekat pada bundle).', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET qty_ok = @QtyOk,
            qty_reject_print = @QtyRejectPrint,
            qty_reject_fabric = @QtyRejectFabric,
            qty_reject_sewing = @QtyRejectSewing,
            qty_rework = @QtyRework,
            remark = @Remark,
            article_size_id = @ArticleSizeId
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'RECEIVE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM article_workflow_logs WHERE workflow_log_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @RecTargetDivisionId INT, @RecReceivedAt DATETIME2;
        SELECT @RecTargetDivisionId = target_division_id, @RecReceivedAt = received_at
        FROM article_workflow_logs
        WHERE workflow_log_id = @Id;

        IF @RecTargetDivisionId IS NULL
        BEGIN
            RAISERROR('Log ini tidak memiliki tujuan serah, tidak bisa diterima.', 16, 1);
            RETURN;
        END

        IF @RecReceivedAt IS NOT NULL
        BEGIN
            RAISERROR('Log ini sudah diterima sebelumnya.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @RecTargetDivisionId
        BEGIN
            RAISERROR('Serah terima ini bukan untuk divisi Anda.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET received_at = SYSDATETIME(),
            received_by_resource_id = @ReceivedByResourceId,
            received_remark = @ReceivedRemark
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF @DeleteReason IS NULL OR LTRIM(RTRIM(@DeleteReason)) = ''
        BEGIN
            RAISERROR('Alasan hapus wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @DelBundleId INT, @DelSortOrder INT, @DelArticleId INT;
        SELECT @DelBundleId = awl.bundle_id, @DelSortOrder = aw.sort_order, @DelArticleId = aw.article_id
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id AND awl.deleted_at IS NULL;

        IF @DelBundleId IS NOT NULL AND EXISTS (
            SELECT 1
            FROM article_workflow_logs awl2
            INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
            WHERE awl2.bundle_id = @DelBundleId AND awl2.deleted_at IS NULL
              AND aw2.article_id = @DelArticleId AND aw2.sort_order > @DelSortOrder
        )
        BEGIN
            RAISERROR('Baris ini sudah dipakai sebagai dasar step berikutnya, tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            delete_reason = @DeleteReason
        WHERE workflow_log_id = @Id AND deleted_at IS NULL;
    END
    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO

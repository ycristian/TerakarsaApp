-- Prompt 50: restrukturisasi workflow artikel SETELAH sudah ada article_workflow_logs --
-- menyisipkan step baru (INSERT_STEP) atau menonaktifkan step (DEACTIVATE_STEP) tanpa
-- memutus rantai serah-terima dan tanpa menghilangkan riwayat produksi. Lihat komentar
-- besar di claude prompt/prompt_50_workflow_restructure.md untuk latar belakang lengkap
-- (kategori A/B/C, kenapa target_division_id perlu di-redirect/backfill).
--
-- Isolasi terpisah dari SIS_ArticleWorkflow_Manage (pola sama dengan SIS_SuperAdmin_Manage)
-- -- guard SAVE yang menolak penghapusan step ber-log TETAP dipertahankan apa adanya di sana,
-- SP ini adalah jalur terpisah.
--
-- Applock: memakai resource 'article_workflow_restructure_' + ArticleId, SAMA PERSIS dengan
-- yang sekarang JUGA diambil oleh SIS_WorkflowLog_Manage (aksi CREATE/UPDATE/RECEIVE/
-- UNRECEIVE/REVISE_HANDOVER/ADJUST) dan SIS_Bundle_Manage (aksi CREATE) -- supaya station
-- device tidak bisa submit log baru di tengah restrukturisasi artikel yang sama.
--
-- Predecessor untuk redirect/backfill INSERT_STEP TIDAK SELALU sama dengan @AfterWorkflowId:
-- kalau step baru (RequiresBundle = 1) disisipkan tepat di titik step Bundling implisit
-- reposisi diri (yaitu step baru jadi step ber-bundle PERTAMA yang bukan Bundling), predecessor
-- sebenarnya adalah step Bundling itu sendiri (Bundling selalu tepat sebelum step ber-bundle
-- pertama, lihat SIS_ArticleWorkflow_Manage) -- BUKAN @AfterWorkflowId (yang di kasus ini
-- adalah step non-bundle terakhir, atau NULL). Predecessor/next dihitung dari topologi
-- SEKARANG (sebelum step baru disisipkan) -- valid dipakai baik oleh PREVIEW (tidak menulis
-- apa pun) maupun eksekusi (dihitung sebelum perubahan struktur), karena menyisipkan satu baris
-- di antara dua baris yang sudah bertetangga tidak mengubah baris LAIN mana yang bertetangga.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_ArticleWorkflow_Restructure
    @Action            VARCHAR(20),   -- 'PREVIEW_INSERT' | 'INSERT_STEP' | 'PREVIEW_DEACTIVATE' | 'DEACTIVATE_STEP'
    @ArticleId         INT,
    @StepName          VARCHAR(150) = NULL,
    @DivisionId        INT = NULL,
    @RequiresBundle    BIT = NULL,
    @AutoReceive       BIT = 0,
    @AfterWorkflowId   INT = NULL,
    @ArticleWorkflowId INT = NULL,
    @Backfill          BIT = 1,
    @UserId            INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LockResource VARCHAR(60) = 'article_workflow_restructure_' + CAST(@ArticleId AS VARCHAR(20));

    IF @Action IN ('PREVIEW_INSERT', 'INSERT_STEP')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Artikel ini belum memiliki workflow.', 16, 1);
            RETURN;
        END

        IF @DivisionId IS NULL OR NOT EXISTS (SELECT 1 FROM divisions WHERE division_id = @DivisionId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Divisi tidak valid.', 16, 1);
            RETURN;
        END

        IF @StepName IS NULL OR LTRIM(RTRIM(@StepName)) = ''
        BEGIN
            RAISERROR('Nama step wajib diisi.', 16, 1);
            RETURN;
        END

        IF @RequiresBundle IS NULL
        BEGIN
            RAISERROR('RequiresBundle wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @AfterSortOrder INT = NULL, @AfterRequiresBundle BIT = NULL;
        IF @AfterWorkflowId IS NOT NULL
        BEGIN
            SELECT @AfterSortOrder = sort_order, @AfterRequiresBundle = requires_bundle
            FROM article_workflows
            WHERE article_workflow_id = @AfterWorkflowId AND article_id = @ArticleId
              AND deleted_at IS NULL AND inactive_at IS NULL;

            IF @AfterSortOrder IS NULL
            BEGIN
                RAISERROR('Step acuan sisip tidak ditemukan atau sudah nonaktif.', 16, 1);
                RETURN;
            END
        END

        -- Aturan urutan: semua step non-bundle harus mendahului semua step ber-bundle
        -- (hanya dibandingkan terhadap step hidup-AKTIF -- step nonaktif tidak lagi jadi batas).
        DECLARE @FirstLiveBundleSort INT, @LastLiveNonBundleSort INT;
        SELECT @FirstLiveBundleSort = MIN(sort_order)
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 1;

        SELECT @LastLiveNonBundleSort = MAX(sort_order)
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 0;

        IF @RequiresBundle = 0
        BEGIN
            IF @FirstLiveBundleSort IS NOT NULL AND @AfterSortOrder IS NOT NULL AND @AfterSortOrder >= @FirstLiveBundleSort
            BEGIN
                RAISERROR('Step tanpa bundle harus disisipkan sebelum semua step ber-bundle.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            IF @LastLiveNonBundleSort IS NOT NULL AND (@AfterSortOrder IS NULL OR @AfterSortOrder < @LastLiveNonBundleSort)
            BEGIN
                RAISERROR('Step ber-bundle harus disisipkan setelah semua step tanpa bundle.', 16, 1);
                RETURN;
            END
        END

        -- Predecessor sebenarnya untuk redirect/backfill (lihat komentar besar di atas file).
        DECLARE @PredWorkflowId INT = NULL;
        IF @RequiresBundle = 1
        BEGIN
            IF @AfterWorkflowId IS NOT NULL AND @AfterRequiresBundle = 1
                SET @PredWorkflowId = @AfterWorkflowId;
            ELSE
            BEGIN
                SELECT @PredWorkflowId = article_workflow_id
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

                IF @PredWorkflowId IS NULL
                BEGIN
                    RAISERROR('Artikel ini belum memiliki step Bundling. Tambahkan step ber-bundle lewat editor workflow terlebih dahulu.', 16, 1);
                    RETURN;
                END
            END
        END
        ELSE
            SET @PredWorkflowId = @AfterWorkflowId;

        DECLARE @PredSortOrder INT = NULL;
        IF @PredWorkflowId IS NOT NULL
            SELECT @PredSortOrder = sort_order FROM article_workflows WHERE article_workflow_id = @PredWorkflowId;

        DECLARE @NextStepId INT = NULL, @NextDivisionId INT = NULL;
        SELECT TOP 1 @NextStepId = article_workflow_id, @NextDivisionId = division_id
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL
          AND sort_order > ISNULL(@PredSortOrder, 0)
        ORDER BY sort_order ASC;

        -- Klasifikasi (read-only) -- dipakai baik oleh PREVIEW maupun eksekusi.
        DECLARE @PendingLogsToRedirect INT = 0, @BackfillLogsToCreate INT = 0, @ForcedBackfillCount INT = 0;
        IF @PredWorkflowId IS NOT NULL
        BEGIN
            SELECT @PendingLogsToRedirect = COUNT(*)
            FROM article_workflow_logs
            WHERE article_workflow_id = @PredWorkflowId AND deleted_at IS NULL AND received_at IS NULL;

            SELECT @BackfillLogsToCreate = COUNT(*)
            FROM article_workflow_logs src
            WHERE src.article_workflow_id = @PredWorkflowId AND src.deleted_at IS NULL AND src.received_at IS NOT NULL;

            SELECT @ForcedBackfillCount = COUNT(*)
            FROM article_workflow_logs src
            WHERE src.article_workflow_id = @PredWorkflowId AND src.deleted_at IS NULL AND src.received_at IS NOT NULL
              AND NOT EXISTS (
                    SELECT 1 FROM article_workflow_logs ex
                    WHERE ex.deleted_at IS NULL AND ex.article_workflow_id = @NextStepId
                      AND (
                            (src.bundle_id IS NOT NULL AND ex.bundle_id = src.bundle_id)
                         OR (src.bundle_id IS NULL AND ex.article_size_id = src.article_size_id AND ex.bundle_id IS NULL)
                          )
                  );
        END

        IF @Action = 'PREVIEW_INSERT'
        BEGIN
            SELECT
                @PendingLogsToRedirect AS PendingLogsToRedirect,
                CAST(0 AS INT) AS ReceivedLogsToRedirect,
                @BackfillLogsToCreate AS BackfillLogsToCreate,
                @ForcedBackfillCount AS ForcedBackfillCount,
                CAST(0 AS INT) AS StepsResequenced,
                CAST(NULL AS VARCHAR(255)) AS WarningMessage;

            SELECT
                b.bundle_id AS BundleId, b.serial AS Serial, b.bundle_no AS BundleNo,
                CASE WHEN src.bundle_id IS NULL THEN src.article_size_id ELSE NULL END AS ArticleSizeId,
                spd.size_name AS SizeName,
                CASE WHEN src.received_at IS NULL THEN 'B' ELSE 'C' END AS Category,
                pw.step_name AS LastStepName
            FROM article_workflow_logs src
            INNER JOIN article_workflows pw ON pw.article_workflow_id = src.article_workflow_id
            LEFT JOIN bundles b ON b.bundle_id = src.bundle_id
            LEFT JOIN article_sizes asz ON asz.article_size_id = src.article_size_id
            LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
            WHERE @PredWorkflowId IS NOT NULL AND src.article_workflow_id = @PredWorkflowId AND src.deleted_at IS NULL
            ORDER BY src.received_at DESC;

            RETURN;
        END

        -- === INSERT_STEP: eksekusi ===
        BEGIN TRAN;
        BEGIN TRY
            DECLARE @LockResult INT;
            EXEC @LockResult = sp_getapplock
                @Resource = @LockResource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                RAISERROR('Gagal mengunci artikel untuk restrukturisasi. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            DECLARE @TargetSortOrder INT = ISNULL(@AfterSortOrder, 0) + 1;

            UPDATE article_workflows
            SET sort_order = sort_order + 1
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order >= @TargetSortOrder;

            INSERT INTO article_workflows (
                article_id, workflow_template_id, step_name, division_id, sort_order,
                requires_bundle, auto_receive, is_bundling, created_at, created_by
            )
            VALUES (
                @ArticleId, NULL, @StepName, @DivisionId, @TargetSortOrder,
                @RequiresBundle, ISNULL(@AutoReceive, 0), 0, SYSDATETIME(), @UserId
            );

            DECLARE @NewStepId INT = CAST(SCOPE_IDENTITY() AS INT);

            -- Reposisi step Bundling (kalau ada) supaya tetap tepat sebelum step hidup-aktif
            -- ber-bundle pertama, lalu resequence seluruh step hidup dari 1 (pola sama dengan
            -- SIS_ArticleWorkflow_Manage SAVE).
            DECLARE @BundlingId INT;
            SELECT @BundlingId = article_workflow_id FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

            IF @BundlingId IS NOT NULL
            BEGIN
                DECLARE @MinStationBundleSort INT;
                SELECT @MinStationBundleSort = MIN(sort_order)
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 0 AND requires_bundle = 1 AND inactive_at IS NULL;

                IF @MinStationBundleSort IS NOT NULL
                    UPDATE article_workflows SET sort_order = @MinStationBundleSort WHERE article_workflow_id = @BundlingId;
            END

            DECLARE @StepsResequenced INT;
            ;WITH Ordered AS (
                SELECT article_workflow_id, sort_order AS OldSortOrder,
                       ROW_NUMBER() OVER (
                           ORDER BY sort_order ASC,
                                    CASE WHEN is_bundling = 1 THEN 0 ELSE 1 END ASC,
                                    article_workflow_id ASC
                       ) AS rn
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL
            )
            SELECT @StepsResequenced = COUNT(*) FROM Ordered WHERE OldSortOrder <> rn;

            ;WITH Ordered2 AS (
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
            INNER JOIN Ordered2 o ON o.article_workflow_id = aw.article_workflow_id;

            -- Redirect kategori B (baris pending di predecessor).
            IF @PredWorkflowId IS NOT NULL
            BEGIN
                UPDATE article_workflow_logs
                SET target_division_id = @DivisionId,
                    target_division_id_original = ISNULL(target_division_id_original, target_division_id),
                    updated_at = SYSDATETIME(), updated_by = @UserId
                WHERE article_workflow_id = @PredWorkflowId AND deleted_at IS NULL AND received_at IS NULL;

                -- Backfill kategori C (satu baris baru per baris log sumber received).
                INSERT INTO article_workflow_logs (
                    article_workflow_id, bundle_id, article_size_id, division_id, resource_id,
                    qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_reject_rework, qty_lost,
                    log_type, remark, target_division_id, created_at, received_at, received_by_resource_id,
                    created_by, updated_by
                )
                SELECT
                    @NewStepId, src.bundle_id, src.article_size_id, @DivisionId, src.resource_id,
                    src.qty_ok, src.qty_reject_print, src.qty_reject_fabric, src.qty_reject_sewing, src.qty_reject_rework, src.qty_lost,
                    src.log_type, '[Backfill Prompt 50]', @NextDivisionId, src.received_at, src.received_at, src.received_by_resource_id,
                    @UserId, @UserId
                FROM article_workflow_logs src
                WHERE src.article_workflow_id = @PredWorkflowId AND src.deleted_at IS NULL AND src.received_at IS NOT NULL
                  AND (
                        @Backfill = 1
                        OR NOT EXISTS (
                            SELECT 1 FROM article_workflow_logs ex
                            WHERE ex.deleted_at IS NULL AND ex.article_workflow_id = @NextStepId
                              AND (
                                    (src.bundle_id IS NOT NULL AND ex.bundle_id = src.bundle_id)
                                 OR (src.bundle_id IS NULL AND ex.article_size_id = src.article_size_id AND ex.bundle_id IS NULL)
                                  )
                        )
                      );
            END

            COMMIT TRAN;

            SELECT @NewStepId AS NewArticleWorkflowId, @PendingLogsToRedirect AS PendingLogsToRedirect,
                   @BackfillLogsToCreate AS BackfillLogsToCreate, ISNULL(@StepsResequenced, 0) AS StepsResequenced;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action IN ('PREVIEW_DEACTIVATE', 'DEACTIVATE_STEP')
    BEGIN
        DECLARE @DeactDivisionId INT, @DeactSortOrder INT, @DeactIsBundling BIT, @DeactDeletedAt DATETIME2, @DeactInactiveAt DATETIME2;
        SELECT @DeactDivisionId = division_id, @DeactSortOrder = sort_order, @DeactIsBundling = is_bundling,
               @DeactDeletedAt = deleted_at, @DeactInactiveAt = inactive_at
        FROM article_workflows
        WHERE article_workflow_id = @ArticleWorkflowId AND article_id = @ArticleId;

        IF @DeactDivisionId IS NULL OR @DeactDeletedAt IS NOT NULL
        BEGIN
            RAISERROR('Step tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @DeactInactiveAt IS NOT NULL
        BEGIN
            RAISERROR('Step ini sudah nonaktif.', 16, 1);
            RETURN;
        END

        IF @DeactIsBundling = 1
        BEGIN
            RAISERROR('Step Bundling dikelola otomatis, tidak bisa dinonaktifkan manual.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL
              AND article_workflow_id <> @ArticleWorkflowId
        )
        BEGIN
            RAISERROR('Tidak bisa menonaktifkan satu-satunya step aktif artikel ini.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM article_workflow_logs
            WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL AND received_at IS NULL
        )
        BEGIN
            RAISERROR('Step ini punya log yang masih menunggu diterima. Selesaikan atau koreksi dulu lewat Super Admin.', 16, 1);
            RETURN;
        END

        DECLARE @DeactRedirectDivisionId INT;
        SELECT TOP 1 @DeactRedirectDivisionId = division_id
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND sort_order > @DeactSortOrder
        ORDER BY sort_order ASC;

        -- Cakupan redirect: baris hidup mana pun (di divisi @ArticleId ini) yang target_division_id
        -- = divisi step yang dinonaktifkan, DAN unitnya (bundle_id/article_size_id) belum punya log
        -- di step aktif MANA PUN setelah step ini (masih berjalan).
        DECLARE @DeactPendingCount INT, @DeactReceivedCount INT;
        SELECT
            @DeactPendingCount = SUM(CASE WHEN awl.received_at IS NULL THEN 1 ELSE 0 END),
            @DeactReceivedCount = SUM(CASE WHEN awl.received_at IS NOT NULL THEN 1 ELSE 0 END)
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE aw.article_id = @ArticleId AND awl.deleted_at IS NULL AND awl.target_division_id = @DeactDivisionId
          AND NOT EXISTS (
                SELECT 1
                FROM article_workflow_logs later
                INNER JOIN article_workflows lawf ON lawf.article_workflow_id = later.article_workflow_id
                WHERE later.deleted_at IS NULL AND lawf.article_id = @ArticleId
                  AND lawf.sort_order > @DeactSortOrder AND lawf.inactive_at IS NULL
                  AND (
                        (awl.bundle_id IS NOT NULL AND later.bundle_id = awl.bundle_id)
                     OR (awl.bundle_id IS NULL AND later.article_size_id = awl.article_size_id AND later.bundle_id IS NULL)
                      )
              );
        SET @DeactPendingCount = ISNULL(@DeactPendingCount, 0);
        SET @DeactReceivedCount = ISNULL(@DeactReceivedCount, 0);

        IF @Action = 'PREVIEW_DEACTIVATE'
        BEGIN
            SELECT
                @DeactPendingCount AS PendingLogsToRedirect,
                @DeactReceivedCount AS ReceivedLogsToRedirect,
                CAST(0 AS INT) AS BackfillLogsToCreate,
                CAST(0 AS INT) AS ForcedBackfillCount,
                CAST(0 AS INT) AS StepsResequenced,
                CASE WHEN @DeactReceivedCount > 0
                     THEN 'Riwayat serahan pada log yang sudah diterima akan berubah -- bundle lama akan menampilkan divisi tujuan yang berbeda dari kenyataan saat itu.'
                     ELSE NULL END AS WarningMessage;

            SELECT
                b.bundle_id AS BundleId, b.serial AS Serial, b.bundle_no AS BundleNo,
                CASE WHEN awl.bundle_id IS NULL THEN awl.article_size_id ELSE NULL END AS ArticleSizeId,
                spd.size_name AS SizeName,
                CASE WHEN awl.received_at IS NULL THEN 'B' ELSE 'C' END AS Category,
                aw.step_name AS LastStepName
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
            LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
            LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
            WHERE aw.article_id = @ArticleId AND awl.deleted_at IS NULL AND awl.target_division_id = @DeactDivisionId
              AND NOT EXISTS (
                    SELECT 1
                    FROM article_workflow_logs later
                    INNER JOIN article_workflows lawf ON lawf.article_workflow_id = later.article_workflow_id
                    WHERE later.deleted_at IS NULL AND lawf.article_id = @ArticleId
                      AND lawf.sort_order > @DeactSortOrder AND lawf.inactive_at IS NULL
                      AND (
                            (awl.bundle_id IS NOT NULL AND later.bundle_id = awl.bundle_id)
                         OR (awl.bundle_id IS NULL AND later.article_size_id = awl.article_size_id AND later.bundle_id IS NULL)
                          )
                  )
            ORDER BY awl.received_at DESC;

            RETURN;
        END

        -- === DEACTIVATE_STEP: eksekusi ===
        BEGIN TRAN;
        BEGIN TRY
            DECLARE @LockResult2 INT;
            EXEC @LockResult2 = sp_getapplock
                @Resource = @LockResource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;

            IF @LockResult2 < 0
            BEGIN
                RAISERROR('Gagal mengunci artikel untuk restrukturisasi. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            UPDATE article_workflows
            SET inactive_at = SYSDATETIME(), inactive_by = @UserId
            WHERE article_workflow_id = @ArticleWorkflowId;

            DECLARE @DeactBundlingId INT;
            SELECT @DeactBundlingId = article_workflow_id FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

            IF @DeactBundlingId IS NOT NULL
            BEGIN
                DECLARE @DeactMinStationBundleSort INT;
                SELECT @DeactMinStationBundleSort = MIN(sort_order)
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 0 AND requires_bundle = 1 AND inactive_at IS NULL;

                IF @DeactMinStationBundleSort IS NOT NULL
                    UPDATE article_workflows SET sort_order = @DeactMinStationBundleSort WHERE article_workflow_id = @DeactBundlingId;
            END

            DECLARE @DeactStepsResequenced INT;
            ;WITH Ordered AS (
                SELECT article_workflow_id, sort_order AS OldSortOrder,
                       ROW_NUMBER() OVER (
                           ORDER BY sort_order ASC,
                                    CASE WHEN is_bundling = 1 THEN 0 ELSE 1 END ASC,
                                    article_workflow_id ASC
                       ) AS rn
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL
            )
            SELECT @DeactStepsResequenced = COUNT(*) FROM Ordered WHERE OldSortOrder <> rn;

            ;WITH Ordered2 AS (
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
            INNER JOIN Ordered2 o ON o.article_workflow_id = aw.article_workflow_id;

            UPDATE awl
            SET awl.target_division_id = @DeactRedirectDivisionId,
                awl.target_division_id_original = ISNULL(awl.target_division_id_original, awl.target_division_id),
                awl.updated_at = SYSDATETIME(), awl.updated_by = @UserId
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE aw.article_id = @ArticleId AND awl.deleted_at IS NULL AND awl.target_division_id = @DeactDivisionId
              AND NOT EXISTS (
                    SELECT 1
                    FROM article_workflow_logs later
                    INNER JOIN article_workflows lawf ON lawf.article_workflow_id = later.article_workflow_id
                    WHERE later.deleted_at IS NULL AND lawf.article_id = @ArticleId
                      AND lawf.sort_order > @DeactSortOrder AND lawf.inactive_at IS NULL
                      AND (
                            (awl.bundle_id IS NOT NULL AND later.bundle_id = awl.bundle_id)
                         OR (awl.bundle_id IS NULL AND later.article_size_id = awl.article_size_id AND later.bundle_id IS NULL)
                          )
                  );

            COMMIT TRAN;

            SELECT @DeactPendingCount AS PendingLogsToRedirect, @DeactReceivedCount AS ReceivedLogsToRedirect,
                   ISNULL(@DeactStepsResequenced, 0) AS StepsResequenced;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END
    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO

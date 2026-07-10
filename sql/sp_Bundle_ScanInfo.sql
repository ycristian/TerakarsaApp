-- Alur "scan QR bundle" (Prompt 12, disesuaikan model 1-baris di Prompt 12b) — pintu
-- masuk universal dari /station (scan panel) dan halaman publik /b/{serial}.
-- Mengembalikan TIGA result set sekaligus supaya satu kali scan cukup satu round-trip:
--   1. Info bundle + posisi ringkas (step & divisi terakhir yang menyentuhnya).
--   2. Timeline: HANYA log milik bundle ini (bundle_id = @BundleId), urut sort_order
--      lalu created_at. Log level artikel (bundle_id NULL, mis. Cutting) SENGAJA tidak
--      ikut digabung lagi -- step itu tidak spesifik ke bundle manapun (bisa mencakup
--      banyak bundle atau seluruh artikel), jadi menampilkannya di timeline satu bundle
--      tertentu menyesatkan (lihat riwayat lengkap per step di /articles/{id}/edit alih-
--      alih di sini). Tiap baris membawa DUA stempel: selesai (created_at + resource yang
--      mengerjakan) dan diterima (received_at + received_by_resource_id + received_remark)
--      bila sudah diterima.
--   3. Aksi yang diperbolehkan untuk @DivisionId + @ResourceId pemanggil ini (operator
--      stasiun):
--        - 'RECEIVE' kalau ada baris bundle ini yang target_division_id = @DivisionId
--          dan received_at masih NULL (menunggu diterima divisiku).
--        - 'COMPLETE' kalau tidak ada yang menunggu diterima, DAN step ber-bundle
--          berikutnya yang kuotanya belum habis (Prompt 14b -- boleh sudah punya baris
--          susulan, lihat sisa qty) untuk bundle ini adalah milik @DivisionId -- untuk step
--          ber-bundle PERTAMA tanpa prasyarat (kecuali cocok resource bila bundle
--          ditugaskan ke line tertentu); untuk step SELANJUTNYA disyaratkan step
--          sebelumnya (bundle sama) sudah received_at + target_division_id = divisi ini.
--        - Selain itu 'NONE' + pesan posisi (kalau @DivisionId NULL/pengunjung publik,
--          selalu NONE tanpa pesan negatif).
--      Aksi juga membawa NextDivisionId/NextDivisionName -- divisi tujuan yang akan
--      dikunci otomatis oleh SIS_WorkflowLog_Manage kalau COMPLETE ini dikirim (dipakai
--      client hanya untuk ditampilkan sebagai default terkunci, bukan pilihan bebas).
--
-- Aturan kepemilikan ikut sp_WorkflowLog_Manage.sql (SIS_WorkflowLog_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Bundle_ScanInfo
    @Serial     VARCHAR(50),
    @DivisionId INT = NULL,
    @ResourceId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BundleId INT, @ArticleId INT;
    SELECT @BundleId = bundle_id, @ArticleId = article_id
    FROM bundles WHERE serial = @Serial AND deleted_at IS NULL;

    IF @BundleId IS NULL
    BEGIN
        RAISERROR('Bundle tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- Timeline khusus bundle ini (bukan digabung level artikel lagi) dipakai ulang untuk
    -- result set 1 & 2.
    DECLARE @Timeline TABLE (
        ArticleWorkflowId INT, StepName VARCHAR(255), SortOrder INT,
        SizeName VARCHAR(255) NULL,
        DivisionName VARCHAR(255) NULL,
        ResourceName VARCHAR(255) NULL,
        QtyOk INT, QtyRejectPrint INT, QtyRejectFabric INT, QtyRejectSewing INT,
        TargetDivisionName VARCHAR(255) NULL,
        CreatedAt DATETIME2,
        ReceivedAt DATETIME2 NULL, ReceivedByResourceName VARCHAR(255) NULL, ReceivedRemark VARCHAR(500) NULL
    );

    INSERT INTO @Timeline
    SELECT aw.article_workflow_id, aw.step_name, aw.sort_order,
           spd.size_name,
           d.division_name,
           r.resource_name,
           awl.qty_ok, awl.qty_reject_print, awl.qty_reject_fabric, awl.qty_reject_sewing,
           td.division_name,
           awl.created_at,
           awl.received_at, rr.resource_name, awl.received_remark
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    LEFT JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    LEFT JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN resources rr ON rr.resource_id = awl.received_by_resource_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE awl.deleted_at IS NULL
      AND awl.bundle_id = @BundleId;

    -- 1. Info bundle
    DECLARE @LastStepName VARCHAR(255), @LastDivisionName VARCHAR(255), @LastReceivedAt DATETIME2;
    SELECT TOP 1 @LastStepName = StepName, @LastDivisionName = DivisionName, @LastReceivedAt = ReceivedAt
    FROM @Timeline
    ORDER BY SortOrder DESC, CreatedAt DESC;

    SELECT
        b.bundle_id AS BundleId,
        b.bundle_no AS BundleNo,
        b.serial AS Serial,
        b.qty AS Qty,
        spd.size_name AS SizeName,
        a.article_id AS ArticleId,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        p.project_name AS ProjectName,
        ISNULL(r.resource_name, b.resource_person_name) AS Line,
        @LastStepName AS LastStepName,
        CASE WHEN @LastStepName IS NULL THEN NULL
             WHEN @LastReceivedAt IS NOT NULL THEN 'Diterima'
             ELSE 'Selesai' END AS LastStatus,
        @LastDivisionName AS LastDivisionName
    FROM bundles b
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN resources r ON r.resource_id = b.resource_id
    WHERE b.bundle_id = @BundleId;

    -- 2. Timeline lengkap
    SELECT StepName, SortOrder, SizeName, DivisionName, ResourceName,
           QtyOk, QtyRejectPrint, QtyRejectFabric, QtyRejectSewing,
           TargetDivisionName, CreatedAt, ReceivedAt, ReceivedByResourceName, ReceivedRemark
    FROM @Timeline
    ORDER BY SortOrder ASC, CreatedAt ASC;

    -- 3. Aksi
    DECLARE @AllowedAction VARCHAR(20) = 'NONE';
    DECLARE @ActionArticleWorkflowId INT = NULL;
    DECLARE @ActionWorkflowLogId INT = NULL;
    DECLARE @Message VARCHAR(255) = NULL;
    DECLARE @IsLastStep BIT = 0;
    -- Divisi tujuan terkunci sesuai urutan workflow (sama seperti dihitung otomatis di
    -- SIS_WorkflowLog_Manage) -- hanya untuk ditampilkan di kartu scan, tidak dikirim balik
    -- saat submit (server yang menghitung ulang & mengunci nilai final saat CREATE).
    DECLARE @NextDivisionId INT = NULL;
    DECLARE @NextDivisionName VARCHAR(255) = NULL;
    -- Isi hanya kalau AllowedAction = 'EDIT' -- nilai baris yang mau direvisi, dipakai
    -- client untuk mengisi awal form popup edit (sama field yang dikirim balik ke
    -- PUT api/station/logs/{id}, lihat SIS_WorkflowLog_Manage @Action = 'UPDATE').
    DECLARE @ActionQtyOk INT = NULL;
    DECLARE @ActionQtyRejectPrint INT = NULL;
    DECLARE @ActionQtyRejectFabric INT = NULL;
    DECLARE @ActionQtyRejectSewing INT = NULL;
    DECLARE @ActionRemark VARCHAR(500) = NULL;

    DECLARE @MaxArticleSort INT = (
        SELECT MAX(sort_order) FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL
    );
    DECLARE @FirstBundleSort INT = (
        SELECT MIN(sort_order) FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1
    );

    IF @FirstBundleSort IS NULL
    BEGIN
        SET @Message = 'Artikel ini tidak memiliki step ber-bundle.';
    END
    ELSE IF @DivisionId IS NULL
    BEGIN
        SET @Message = NULL; -- pengunjung publik: tanpa aksi, tanpa pesan negatif
    END
    ELSE
    BEGIN
        DECLARE @PendingReceiveWorkflowLogId INT, @PendingReceiveStepId INT;
        SELECT TOP 1 @PendingReceiveWorkflowLogId = awl.workflow_log_id, @PendingReceiveStepId = aw.article_workflow_id
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
          AND awl.target_division_id = @DivisionId AND awl.received_at IS NULL;

        IF @PendingReceiveWorkflowLogId IS NOT NULL
        BEGIN
            SET @AllowedAction = 'RECEIVE';
            SET @ActionArticleWorkflowId = @PendingReceiveStepId;
            SET @ActionWorkflowLogId = @PendingReceiveWorkflowLogId;
        END
        ELSE
        BEGIN
            -- Baris yang AKU (divisi ini) buat untuk bundle ini, sudah punya tujuan serah,
            -- tapi belum diterima divisi tujuan -- masih boleh direvisi (mirror tab
            -- "Menunggu Diserahkan" di /station, lihat SIS_Station_PendingHandover). Dicek
            -- SEBELUM cari step berikutnya supaya tidak nyasar ke pesan "menunggu di step X".
            DECLARE @EditWorkflowLogId INT, @EditStepId INT;
            SELECT TOP 1 @EditWorkflowLogId = awl.workflow_log_id, @EditStepId = aw.article_workflow_id,
                         @ActionQtyOk = awl.qty_ok, @ActionQtyRejectPrint = awl.qty_reject_print,
                         @ActionQtyRejectFabric = awl.qty_reject_fabric, @ActionQtyRejectSewing = awl.qty_reject_sewing,
                         @ActionRemark = awl.remark
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
              AND awl.division_id = @DivisionId AND awl.target_division_id IS NOT NULL AND awl.received_at IS NULL;

            IF @EditWorkflowLogId IS NOT NULL
            BEGIN
                SET @AllowedAction = 'EDIT';
                SET @ActionArticleWorkflowId = @EditStepId;
                SET @ActionWorkflowLogId = @EditWorkflowLogId;
            END
            ELSE
            BEGIN
                -- Prompt 14b: "step berikutnya yang harus dikerjakan" (frontier) tidak lagi
                -- sekadar "step tanpa baris sama sekali" -- satu step ber-bundle boleh sudah
                -- punya baris (susulan) selama kuotanya belum habis. Hitung QtyMasuk/QtySudah
                -- tiap step ber-bundle artikel ini (logika sama dengan Prompt 14 di
                -- sp_WorkflowLog_Manage.sql), lalu ambil step PERTAMA (sort_order terkecil)
                -- yang sisanya masih > 0.
                DECLARE @StepQuota TABLE (
                    ArticleWorkflowId INT, StepName VARCHAR(255), SortOrder INT, DivisionId INT,
                    QtyMasuk INT, QtySudah INT
                );

                ;WITH BundleSteps AS (
                    SELECT aw.article_workflow_id, aw.step_name, aw.sort_order, aw.division_id,
                           LAG(aw.article_workflow_id) OVER (ORDER BY aw.sort_order) AS PrevArticleWorkflowId
                    FROM article_workflows aw
                    WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL AND aw.requires_bundle = 1
                )
                INSERT INTO @StepQuota (ArticleWorkflowId, StepName, SortOrder, DivisionId, QtyMasuk, QtySudah)
                SELECT bs.article_workflow_id, bs.step_name, bs.sort_order, bs.division_id,
                    CASE WHEN bs.PrevArticleWorkflowId IS NULL
                         THEN ISNULL((SELECT qty FROM bundles WHERE bundle_id = @BundleId), 0)
                         ELSE ISNULL((
                             SELECT SUM(qty_ok) FROM article_workflow_logs
                             WHERE article_workflow_id = bs.PrevArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL
                         ), 0)
                    END,
                    ISNULL((
                        SELECT SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing)
                        FROM article_workflow_logs
                        WHERE article_workflow_id = bs.article_workflow_id AND bundle_id = @BundleId AND deleted_at IS NULL
                    ), 0)
                FROM BundleSteps bs;

                DECLARE @CurStepId INT, @CurStepName VARCHAR(255), @CurSort INT, @CurDivisionId INT;
                SELECT TOP 1 @CurStepId = ArticleWorkflowId, @CurStepName = StepName,
                             @CurSort = SortOrder, @CurDivisionId = DivisionId
                FROM @StepQuota
                WHERE (QtyMasuk - QtySudah) > 0
                ORDER BY SortOrder ASC;

                IF @CurStepId IS NULL
                BEGIN
                    SET @Message = 'Seluruh proses per-bundle untuk bundle ini sudah selesai.';
                END
                ELSE
                BEGIN
                    DECLARE @CurDivisionName VARCHAR(255);
                    SELECT @CurDivisionName = division_name FROM divisions WHERE division_id = @CurDivisionId;

                    SELECT TOP 1 @NextDivisionId = division_id
                    FROM article_workflows
                    WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order > @CurSort
                    ORDER BY sort_order ASC;
                    SELECT @NextDivisionName = division_name FROM divisions WHERE division_id = @NextDivisionId;

                    IF @DivisionId <> @CurDivisionId
                    BEGIN
                        -- Divisi ini mungkin sudah mengerjakan step-nya sendiri untuk bundle
                        -- ini sampai kuota habis (Sisa = 0) -- lebih relevan bilang "step kamu
                        -- sudah lengkap" daripada "menunggu di step lain" yang membingungkan.
                        DECLARE @OwnStepDone VARCHAR(255);
                        SELECT TOP 1 @OwnStepDone = StepName
                        FROM @StepQuota
                        WHERE DivisionId = @DivisionId AND QtySudah > 0 AND (QtyMasuk - QtySudah) <= 0
                        ORDER BY SortOrder DESC;

                        IF @OwnStepDone IS NOT NULL
                            SET @Message = 'Step ini sudah lengkap.';
                        ELSE
                            SET @Message = 'Bundle sedang menunggu di step ' + @CurStepName + ' (' + ISNULL(@CurDivisionName, '-') + ').';
                    END
                    ELSE IF @CurSort = @FirstBundleSort
                    BEGIN
                        DECLARE @BundleResourceId INT, @LineName VARCHAR(255);
                        SELECT @BundleResourceId = resource_id FROM bundles WHERE bundle_id = @BundleId;

                        IF @BundleResourceId IS NOT NULL AND (@ResourceId IS NULL OR @BundleResourceId <> @ResourceId)
                        BEGIN
                            SELECT @LineName = resource_name FROM resources WHERE resource_id = @BundleResourceId;
                            SET @Message = 'Bundle ini ditugaskan ke ' + ISNULL(@LineName, 'line lain') + '.';
                        END
                        ELSE
                        BEGIN
                            SET @AllowedAction = 'COMPLETE';
                            SET @ActionArticleWorkflowId = @CurStepId;
                            SET @IsLastStep = CASE WHEN @CurSort = @MaxArticleSort THEN 1 ELSE 0 END;
                        END
                    END
                    ELSE
                    BEGIN
                        DECLARE @PrevStepId INT;
                        SELECT TOP 1 @PrevStepId = article_workflow_id
                        FROM article_workflows
                        WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1 AND sort_order < @CurSort
                        ORDER BY sort_order DESC;

                        IF @PrevStepId IS NOT NULL AND EXISTS (
                            SELECT 1 FROM article_workflow_logs
                            WHERE article_workflow_id = @PrevStepId AND bundle_id = @BundleId AND deleted_at IS NULL
                              AND received_at IS NOT NULL AND target_division_id = @CurDivisionId
                        )
                        BEGIN
                            SET @AllowedAction = 'COMPLETE';
                            SET @ActionArticleWorkflowId = @CurStepId;
                            SET @IsLastStep = CASE WHEN @CurSort = @MaxArticleSort THEN 1 ELSE 0 END;
                        END
                        ELSE
                        BEGIN
                            SET @Message = 'Bundle belum diterima di divisi ini untuk step ' + @CurStepName + '.';
                        END
                    END
                END
            END
        END
    END

    SELECT @AllowedAction AS AllowedAction, @ActionArticleWorkflowId AS ActionArticleWorkflowId,
           @ActionWorkflowLogId AS ActionWorkflowLogId, @Message AS Message, @IsLastStep AS IsLastStep,
           @NextDivisionId AS NextDivisionId, @NextDivisionName AS NextDivisionName,
           @ActionQtyOk AS ActionQtyOk, @ActionQtyRejectPrint AS ActionQtyRejectPrint,
           @ActionQtyRejectFabric AS ActionQtyRejectFabric, @ActionQtyRejectSewing AS ActionQtyRejectSewing,
           @ActionRemark AS ActionRemark;
END;
GO

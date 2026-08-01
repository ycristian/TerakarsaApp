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
--        - 'EDIT' (Prompt 23) kalau baris log TERAKHIR bundle ini adalah step terakhir
--          artikel (target_division_id NULL, tidak ada serah lanjutan sehingga tidak pernah
--          "diterima"), dibuat oleh @DivisionId sendiri, DAN masih dalam jendela H+1 (hari
--          dibuat + 1 hari kalender) -- dipakai supaya divisi terakhir (mis. Packing) bisa
--          membetulkan salah input tanpa lewat supervisor. IsLastStep = 1 menandai kasus ini
--          (beda pesan di client dari EDIT baris pending-handover biasa).
--        - Selain itu 'NONE' + pesan posisi (kalau @DivisionId NULL/pengunjung publik,
--          selalu NONE tanpa pesan negatif).
--      Aksi juga membawa NextDivisionId/NextDivisionName -- divisi tujuan yang akan
--      dikunci otomatis oleh SIS_WorkflowLog_Manage kalau COMPLETE ini dikirim (dipakai
--      client hanya untuk ditampilkan sebagai default terkunci, bukan pilihan bebas).
--
-- Prompt 39: SuggestedResourceId (result set 1) -- awalnya sekadar counterpart_resource_id
-- dari bundles.resource_id (line asal bundle). Prompt 40 MENGGANTIKAN logika ini dengan
-- kaskade 4 sumber (LINE_BUNDLE/PENERIMA/COUNTERPART/RIWAYAT) -- lihat blok komentar di
-- bawah, dekat perhitungannya.
--
-- Prompt 40 -- perbaikan penerima auto-terima (Prompt 34/39 salah atribusi divisi):
--   A. Result set 3 (Aksi) kini juga membawa info penerima untuk form "Kirim Hasil" saat
--      AllowedAction = 'COMPLETE': NextAutoReceive, NextCounterpartResourceId/Name (counterpart
--      dari resource yang akan mencatat baris ini, yaitu @ResourceId operator sesi, valid
--      terhadap NextDivisionId), dan ReceiverPickerRequired (1 hanya kalau NextAutoReceive = 1
--      DAN counterpart NULL -- client WAJIB tampilkan dropdown penerima manual).
--   B. Result set 1 kini membawa SuggestedResourceId/Name/Source -- saran AUTO-LOGIN operator
--      sesi stasiun (BUKAN cuma nilai awal form "Pelaksana" seperti Prompt 39), kaskade
--      LINE_BUNDLE > PENERIMA > COUNTERPART > RIWAYAT (lihat definisi di blok komentar bawah).
--   @DivisionId NULL (halaman publik /b/{serial}) -> semua kolom baru di atas NULL.
--
-- Prompt 40 SS7 -- "penerima mengikat pelaksana": kalau bundle ini di @DivisionId sudah
-- attribusikan received_by_resource_id (baris masuk dari step sebelumnya) ke resource TERTENTU
-- dan itu beda dari @ResourceId pemanggil, AllowedAction dipaksa 'NONE' + @Message pengarah --
-- penegakan SEBENARNYA (menolak submit) ada di SIS_WorkflowLog_Manage, ini murni supaya kartu
-- scan tidak menampilkan tombol aksi yang pasti ditolak.
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
    -- Prompt 36: Id (workflow_log_id) ditambahkan supaya client bisa memicu modal "Edit"
    -- per baris timeline (fitur Super Admin, /b/{serial}) -- kolom murni tambahan, tidak
    -- mengubah urutan/isi kolom lain.
    -- Prompt 40: ResourceId/DivisionId/TargetDivisionId/ReceivedByResourceId (numerik, selain
    -- nama yang sudah ada) ditambahkan -- dipakai kaskade SuggestedResourceId di bawah, TIDAK
    -- ikut result set 2 (SELECT eksplisit menyebut kolom, kolom tambahan ini tidak terpilih).
    DECLARE @Timeline TABLE (
        Id INT,
        ArticleWorkflowId INT, StepName VARCHAR(255), SortOrder INT,
        SizeName VARCHAR(255) NULL,
        DivisionId INT NULL,
        DivisionName VARCHAR(255) NULL,
        ResourceId INT NULL,
        ResourceName VARCHAR(255) NULL,
        QtyOk INT, QtyRejectPrint INT, QtyRejectFabric INT, QtyRejectSewing INT,
        QtyRejectRework INT, QtyLost INT, LogType VARCHAR(15),
        TargetDivisionId INT NULL,
        TargetDivisionName VARCHAR(255) NULL,
        CreatedAt DATETIME2,
        ReceivedAt DATETIME2 NULL, ReceivedByResourceId INT NULL, ReceivedByResourceName VARCHAR(255) NULL, ReceivedRemark VARCHAR(500) NULL
    );

    INSERT INTO @Timeline
    SELECT awl.workflow_log_id, aw.article_workflow_id, aw.step_name, aw.sort_order,
           spd.size_name,
           awl.division_id, d.division_name,
           awl.resource_id, r.resource_name,
           awl.qty_ok, awl.qty_reject_print, awl.qty_reject_fabric, awl.qty_reject_sewing,
           awl.qty_reject_rework, awl.qty_lost, awl.log_type,
           awl.target_division_id, td.division_name,
           awl.created_at,
           awl.received_at, awl.received_by_resource_id, rr.resource_name, awl.received_remark
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

    DECLARE @MaxArticleSort INT = (
        SELECT MAX(sort_order) FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL
    );
    DECLARE @FirstBundleSort INT = (
        SELECT MIN(sort_order) FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1
    );

    -- 3. Aksi (dihitung SEBELUM result set 1 supaya SuggestedResourceId/receiver info di
    -- bawah bisa memakai hasilnya -- SELECT emisi hasil tetap di posisi aslinya, ini murni
    -- perhitungan variabel).
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
    -- Prompt 40: step ber-bundid berikutnya (article_workflow_id-nya, bukan cuma divisinya)
    -- -- dipakai lookup auto_receive tanpa ambigu kalau divisi dipakai lebih dari satu step.
    DECLARE @NextArticleWorkflowId INT = NULL;
    -- Isi hanya kalau AllowedAction = 'EDIT' -- nilai baris yang mau direvisi, dipakai
    -- client untuk mengisi awal form popup edit (sama field yang dikirim balik ke
    -- PUT api/station/logs/{id}, lihat SIS_WorkflowLog_Manage @Action = 'UPDATE').
    DECLARE @ActionQtyOk INT = NULL;
    DECLARE @ActionQtyRejectPrint INT = NULL;
    DECLARE @ActionQtyRejectFabric INT = NULL;
    DECLARE @ActionQtyRejectSewing INT = NULL;
    DECLARE @ActionQtyRejectRework INT = NULL;
    DECLARE @ActionQtyLost INT = NULL;
    DECLARE @ActionRemark VARCHAR(500) = NULL;

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
          -- Prompt 28: baris qty_ok = 0 tidak pernah butuh diterima.
          AND awl.target_division_id = @DivisionId AND awl.received_at IS NULL AND awl.qty_ok > 0;

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
                         @ActionQtyRejectRework = awl.qty_reject_rework, @ActionQtyLost = awl.qty_lost,
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
                -- Fix: kalau baris log TERAKHIR (hidup) bundle ini sudah diterima di divisi
                -- ini -- definisi WIP yang SAMA dipakai SIS_Station_InProgress -- bundle ini
                -- nyata-nyata sedang dikerjakan di sini, TERLEPAS dari step SEBELUMNYA masih
                -- ada sisa kuota atau tidak (mis. sisa qty short/susulan yang belum
                -- diselesaikan pengirim). Tanpa ini, frontier @StepQuota di bawah bisa nyasar
                -- balik ke step sebelumnya (lihat komentar Prompt 14b) dan bilang "menunggu
                -- di step X" padahal bundle sudah WIP di divisi ini -- membingungkan karena
                -- /station (tab WIP) sudah benar menampilkannya di sini.
                DECLARE @LastLogId INT, @LastLogArticleWorkflowId INT, @LastLogSort INT,
                        @LastLogReceivedAt DATETIME2, @LastLogTargetDivisionId INT,
                        @LastLogDivisionId INT, @LastLogCreatedAt DATETIME2;
                SELECT TOP 1 @LastLogId = awl.workflow_log_id, @LastLogArticleWorkflowId = awl.article_workflow_id,
                             @LastLogSort = aw.sort_order, @LastLogReceivedAt = awl.received_at,
                             @LastLogTargetDivisionId = awl.target_division_id,
                             @LastLogDivisionId = awl.division_id, @LastLogCreatedAt = awl.created_at
                FROM article_workflow_logs awl
                INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
                WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
                ORDER BY aw.sort_order DESC, awl.created_at DESC;

                IF @LastLogReceivedAt IS NOT NULL AND @LastLogTargetDivisionId = @DivisionId
                BEGIN
                    DECLARE @WipStepId INT, @WipStepSort INT;
                    SELECT TOP 1 @WipStepId = aw.article_workflow_id, @WipStepSort = aw.sort_order
                    FROM article_workflows aw
                    WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL AND aw.requires_bundle = 1
                      AND aw.sort_order > @LastLogSort
                    ORDER BY aw.sort_order ASC;

                    IF @WipStepId IS NULL
                    BEGIN
                        SET @Message = 'Seluruh proses per-bundle untuk bundle ini sudah selesai.';
                    END
                    ELSE
                    BEGIN
                        SET @AllowedAction = 'COMPLETE';
                        SET @ActionArticleWorkflowId = @WipStepId;
                        SET @IsLastStep = CASE WHEN @WipStepSort = @MaxArticleSort THEN 1 ELSE 0 END;

                        SELECT TOP 1 @NextArticleWorkflowId = article_workflow_id, @NextDivisionId = division_id
                        FROM article_workflows
                        WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order > @WipStepSort
                        ORDER BY sort_order ASC;
                        SELECT @NextDivisionName = division_name FROM divisions WHERE division_id = @NextDivisionId;
                    END
                END
                -- Prompt 23: step terakhir (target_division_id NULL, mis. Packing) tidak
                -- pernah "diterima" -- tanpa ini baris ini terkunci permanen begitu dibuat.
                -- Beri jendela revisi H+1 (hari dibuat + 1 hari kalender) ke divisi pembuatnya
                -- sendiri supaya salah input bisa diperbaiki tanpa lewat supervisor. Guard
                -- waktu yang sama ditegakkan ulang di SIS_WorkflowLog_Manage (Action UPDATE)
                -- supaya tidak bisa dilewati lewat panggilan API langsung.
                ELSE IF @LastLogTargetDivisionId IS NULL AND @LastLogDivisionId = @DivisionId
                     AND CAST(SYSDATETIME() AS DATE) <= CAST(DATEADD(DAY, 1, @LastLogCreatedAt) AS DATE)
                BEGIN
                    SET @AllowedAction = 'EDIT';
                    SET @ActionArticleWorkflowId = @LastLogArticleWorkflowId;
                    SET @ActionWorkflowLogId = @LastLogId;
                    SET @IsLastStep = 1;

                    SELECT @ActionQtyOk = qty_ok, @ActionQtyRejectPrint = qty_reject_print,
                           @ActionQtyRejectFabric = qty_reject_fabric, @ActionQtyRejectSewing = qty_reject_sewing,
                           @ActionQtyRejectRework = qty_reject_rework, @ActionQtyLost = qty_lost,
                           @ActionRemark = remark
                    FROM article_workflow_logs
                    WHERE workflow_log_id = @LastLogId;
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
                        SELECT SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost)
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

                    SELECT TOP 1 @NextArticleWorkflowId = article_workflow_id, @NextDivisionId = division_id
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
                              -- Prompt 28: hanya baris qty_ok > 0 yang relevan (baris qty_ok = 0
                              -- tidak pernah benar-benar "diterima" divisi ini).
                              AND received_at IS NOT NULL AND target_division_id = @CurDivisionId AND qty_ok > 0
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
    END

    -- Prompt 40 SS7: "penerima mengikat pelaksana" -- kalau bundle ini sudah punya penerima
    -- tertentu di @DivisionId (baris masuk dari step sebelumnya, target_division_id =
    -- @DivisionId, received_at terisi) dan itu beda dari @ResourceId pemanggil, kartu scan
    -- TIDAK menampilkan aksi apa pun (NONE) -- pesan mengarahkan ke UNRECEIVE. Dicek di sini
    -- (setelah @AllowedAction ditentukan) supaya menimpa RECEIVE/EDIT/COMPLETE manapun yang
    -- sudah dihitung -- penegakan sebenarnya (menolak submit) tetap di SIS_WorkflowLog_Manage.
    IF @DivisionId IS NOT NULL AND @ResourceId IS NOT NULL AND @AllowedAction = 'COMPLETE'
    BEGIN
        DECLARE @BoundReceiverResourceId INT, @BoundReceiverName VARCHAR(255);
        SELECT TOP 1 @BoundReceiverResourceId = t.ReceivedByResourceId, @BoundReceiverName = t.ReceivedByResourceName
        FROM @Timeline t
        WHERE t.TargetDivisionId = @DivisionId AND t.ReceivedAt IS NOT NULL AND t.ReceivedByResourceId IS NOT NULL
        ORDER BY t.CreatedAt DESC;

        IF @BoundReceiverResourceId IS NOT NULL AND @BoundReceiverResourceId <> @ResourceId
        BEGIN
            SET @AllowedAction = 'NONE';
            SET @ActionArticleWorkflowId = NULL;
            SET @ActionWorkflowLogId = NULL;
            SET @IsLastStep = 0;
            SET @Message = 'Bundle ini atas nama ' + ISNULL(@BoundReceiverName, '-') + '. Batalkan penerimaan dulu bila salah orang.';
        END
    END

    -- Prompt 40 SS4A: info penerima untuk form "Kirim Hasil" (hanya relevan kalau aksi yang
    -- akhirnya berlaku = COMPLETE dan ada step tujuan).
    DECLARE @NextAutoReceive BIT = NULL;
    DECLARE @NextCounterpartResourceId INT = NULL;
    DECLARE @NextCounterpartResourceName VARCHAR(255) = NULL;
    DECLARE @ReceiverPickerRequired BIT = NULL;

    IF @DivisionId IS NOT NULL AND @AllowedAction = 'COMPLETE' AND @NextArticleWorkflowId IS NOT NULL
    BEGIN
        SELECT @NextAutoReceive = ISNULL(auto_receive, 0)
        FROM article_workflows
        WHERE article_workflow_id = @NextArticleWorkflowId;

        IF @NextAutoReceive = 1
        BEGIN
            -- Counterpart dari resource yang AKAN mencatat baris ini -- operator sesi
            -- (@ResourceId) -- murni pratinjau, nilai final dihitung ulang di
            -- SIS_WorkflowLog_Manage saat submit (operator/Pelaksana bisa saja diganti dulu
            -- di form sebelum submit).
            IF @ResourceId IS NOT NULL
            BEGIN
                SELECT @NextCounterpartResourceId = cp.resource_id, @NextCounterpartResourceName = cp.resource_name
                FROM resources r
                INNER JOIN resources cp ON cp.resource_id = r.counterpart_resource_id
                WHERE r.resource_id = @ResourceId AND cp.deleted_at IS NULL AND cp.is_active = 1
                  AND cp.division_id = @NextDivisionId;
            END

            SET @ReceiverPickerRequired = CASE WHEN @NextCounterpartResourceId IS NULL THEN 1 ELSE 0 END;
        END
        ELSE
            SET @ReceiverPickerRequired = 0;
    END

    -- Prompt 40 SS4B: saran AUTO-LOGIN operator sesi stasiun -- kaskade 4 sumber, kandidat
    -- WAJIB resource hidup + aktif + division_id = @DivisionId. Kandidat pertama yang lolos
    -- dipakai (LINE_BUNDLE didahulukan pada kasusnya karena SIS_WorkflowLog_Manage memang
    -- menolak resource selain bundles.resource_id di step ber-bundle pertama).
    DECLARE @SuggestedResourceId INT = NULL, @SuggestedResourceName VARCHAR(255) = NULL, @SuggestedResourceSource VARCHAR(20) = NULL;

    IF @DivisionId IS NOT NULL
    BEGIN
        DECLARE @ActionSortOrder INT = NULL;
        IF @ActionArticleWorkflowId IS NOT NULL
            SELECT @ActionSortOrder = sort_order FROM article_workflows WHERE article_workflow_id = @ActionArticleWorkflowId;

        -- 1. LINE_BUNDLE -- hanya aksi COMPLETE pada step ber-bundle PERTAMA.
        IF @AllowedAction = 'COMPLETE' AND @ActionSortOrder = @FirstBundleSort
        BEGIN
            SELECT @SuggestedResourceId = b.resource_id, @SuggestedResourceName = r.resource_name
            FROM bundles b
            INNER JOIN resources r ON r.resource_id = b.resource_id
            WHERE b.bundle_id = @BundleId AND r.deleted_at IS NULL AND r.is_active = 1 AND r.division_id = @DivisionId;

            IF @SuggestedResourceId IS NOT NULL
                SET @SuggestedResourceSource = 'LINE_BUNDLE';
        END

        -- 2. PENERIMA -- received_by_resource_id baris bundle ini yang target_division_id
        -- = @DivisionId dan received_at terisi (baris terbaru).
        IF @SuggestedResourceId IS NULL
        BEGIN
            SELECT TOP 1 @SuggestedResourceId = t.ReceivedByResourceId, @SuggestedResourceName = r.resource_name
            FROM @Timeline t
            INNER JOIN resources r ON r.resource_id = t.ReceivedByResourceId
            WHERE t.TargetDivisionId = @DivisionId AND t.ReceivedAt IS NOT NULL AND t.ReceivedByResourceId IS NOT NULL
              AND r.deleted_at IS NULL AND r.is_active = 1 AND r.division_id = @DivisionId
            ORDER BY t.CreatedAt DESC;

            IF @SuggestedResourceId IS NOT NULL
                SET @SuggestedResourceSource = 'PENERIMA';
        END

        -- 3. COUNTERPART -- counterpart dari resource_id baris masuk yang target_division_id
        -- = @DivisionId dan received_at IS NULL (belum diterima).
        IF @SuggestedResourceId IS NULL
        BEGIN
            SELECT TOP 1 @SuggestedResourceId = cp.resource_id, @SuggestedResourceName = cp.resource_name
            FROM @Timeline t
            INNER JOIN resources sender ON sender.resource_id = t.ResourceId
            INNER JOIN resources cp ON cp.resource_id = sender.counterpart_resource_id
            WHERE t.TargetDivisionId = @DivisionId AND t.ReceivedAt IS NULL
              AND cp.deleted_at IS NULL AND cp.is_active = 1 AND cp.division_id = @DivisionId
            ORDER BY t.CreatedAt DESC;

            IF @SuggestedResourceId IS NOT NULL
                SET @SuggestedResourceSource = 'COUNTERPART';
        END

        -- 4. RIWAYAT -- resource_id baris hidup terakhir bundle ini yang division_id = @DivisionId.
        IF @SuggestedResourceId IS NULL
        BEGIN
            SELECT TOP 1 @SuggestedResourceId = t.ResourceId, @SuggestedResourceName = r.resource_name
            FROM @Timeline t
            INNER JOIN resources r ON r.resource_id = t.ResourceId
            WHERE t.DivisionId = @DivisionId AND r.deleted_at IS NULL AND r.is_active = 1
            ORDER BY t.CreatedAt DESC;

            IF @SuggestedResourceId IS NOT NULL
                SET @SuggestedResourceSource = 'RIWAYAT';
        END
    END

    -- 1. Info bundle
    DECLARE @LastStepName VARCHAR(255), @LastDivisionName VARCHAR(255), @LastReceivedAt DATETIME2;
    SELECT TOP 1 @LastStepName = StepName, @LastDivisionName = DivisionName, @LastReceivedAt = ReceivedAt
    FROM @Timeline
    ORDER BY SortOrder DESC, CreatedAt DESC;

    SELECT
        b.bundle_id AS BundleId,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        b.serial AS Serial,
        b.qty AS Qty,
        spd.size_name AS SizeName,
        a.article_id AS ArticleId,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        p.project_name AS ProjectName,
        r.resource_name AS Line,
        @LastStepName AS LastStepName,
        CASE WHEN @LastStepName IS NULL THEN NULL
             WHEN @LastReceivedAt IS NOT NULL THEN 'Diterima'
             ELSE 'Selesai' END AS LastStatus,
        @LastDivisionName AS LastDivisionName,
        emp.employee_name AS EmployeeName,
        @SuggestedResourceId AS SuggestedResourceId,
        @SuggestedResourceName AS SuggestedResourceName,
        @SuggestedResourceSource AS SuggestedResourceSource
    FROM bundles b
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN resources r ON r.resource_id = b.resource_id
    LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
    WHERE b.bundle_id = @BundleId;

    -- 2. Timeline lengkap
    SELECT Id, StepName, SortOrder, SizeName, DivisionName, ResourceName,
           QtyOk, QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost, LogType,
           TargetDivisionName, CreatedAt, ReceivedAt, ReceivedByResourceName, ReceivedRemark
    FROM @Timeline
    ORDER BY SortOrder ASC, CreatedAt ASC;

    -- Prompt 28: allowed_adjust + saldo per step ber-bundle milik @DivisionId (untuk tombol +
    -- prefill panel Penyesuaian di BundleScanCard) -- dihitung terpisah dari @AllowedAction di
    -- atas (independen: bisa saja AllowedAction = 'NONE'/'COMPLETE' tapi divisi ini tetap punya
    -- saldo reject/hilang tersisa dari step yang sudah lewat).
    DECLARE @AdjustSteps TABLE (
        ArticleWorkflowId INT, StepName VARCHAR(255), SortOrder INT,
        SaldoRejectPrint INT, SaldoRejectFabric INT, SaldoRejectSewing INT,
        SaldoRejectRework INT, SaldoLost INT,
        NextDivisionId INT NULL, NextDivisionName VARCHAR(255) NULL
    );

    IF @DivisionId IS NOT NULL
    BEGIN
        INSERT INTO @AdjustSteps (ArticleWorkflowId, StepName, SortOrder,
            SaldoRejectPrint, SaldoRejectFabric, SaldoRejectSewing, SaldoRejectRework, SaldoLost)
        SELECT aw.article_workflow_id, aw.step_name, aw.sort_order,
               ISNULL(SUM(awl.qty_reject_print), 0), ISNULL(SUM(awl.qty_reject_fabric), 0),
               ISNULL(SUM(awl.qty_reject_sewing), 0), ISNULL(SUM(awl.qty_reject_rework), 0),
               ISNULL(SUM(awl.qty_lost), 0)
        FROM article_workflows aw
        LEFT JOIN article_workflow_logs awl ON awl.article_workflow_id = aw.article_workflow_id
            AND awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
        WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL AND aw.requires_bundle = 1
          AND aw.is_bundling = 0 AND aw.division_id = @DivisionId
        GROUP BY aw.article_workflow_id, aw.step_name, aw.sort_order
        HAVING ISNULL(SUM(awl.qty_reject_print), 0) + ISNULL(SUM(awl.qty_reject_fabric), 0)
             + ISNULL(SUM(awl.qty_reject_sewing), 0) + ISNULL(SUM(awl.qty_reject_rework), 0)
             + ISNULL(SUM(awl.qty_lost), 0) > 0;

        -- Divisi tujuan terkunci (step ber-bundle berikutnya) -- hanya relevan kalau nanti
        -- Qty OK diisi > 0 (client menyembunyikannya kalau tidak), NULL kalau step ini step
        -- ber-bundle terakhir artikel (sama seperti @NextDivisionId di @AllowedAction atas).
        UPDATE ads
        SET NextDivisionId = nd.division_id, NextDivisionName = nd2.division_name
        FROM @AdjustSteps ads
        OUTER APPLY (
            SELECT TOP 1 division_id
            FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order > ads.SortOrder
            ORDER BY sort_order ASC
        ) nd
        LEFT JOIN divisions nd2 ON nd2.division_id = nd.division_id;
    END

    DECLARE @AllowedAdjust BIT = CASE WHEN EXISTS (SELECT 1 FROM @AdjustSteps) THEN 1 ELSE 0 END;

    -- 3. Aksi (emisi hasil -- perhitungan sudah dilakukan di atas, sebelum result set 1)
    SELECT @AllowedAction AS AllowedAction, @ActionArticleWorkflowId AS ActionArticleWorkflowId,
           @ActionWorkflowLogId AS ActionWorkflowLogId, @Message AS Message, @IsLastStep AS IsLastStep,
           @NextDivisionId AS NextDivisionId, @NextDivisionName AS NextDivisionName,
           @ActionQtyOk AS ActionQtyOk, @ActionQtyRejectPrint AS ActionQtyRejectPrint,
           @ActionQtyRejectFabric AS ActionQtyRejectFabric, @ActionQtyRejectSewing AS ActionQtyRejectSewing,
           @ActionQtyRejectRework AS ActionQtyRejectRework, @ActionQtyLost AS ActionQtyLost,
           @ActionRemark AS ActionRemark, @AllowedAdjust AS AllowedAdjust,
           @NextAutoReceive AS NextAutoReceive,
           @NextCounterpartResourceId AS NextCounterpartResourceId, @NextCounterpartResourceName AS NextCounterpartResourceName,
           @ReceiverPickerRequired AS ReceiverPickerRequired;

    -- 4. Saldo per step ber-bundle milik @DivisionId yang bisa disesuaikan (kosong kalau
    -- AllowedAdjust = 0).
    SELECT ArticleWorkflowId, StepName, SortOrder,
           SaldoRejectPrint, SaldoRejectFabric, SaldoRejectSewing, SaldoRejectRework, SaldoLost,
           NextDivisionId, NextDivisionName
    FROM @AdjustSteps
    ORDER BY SortOrder ASC;
END;
GO

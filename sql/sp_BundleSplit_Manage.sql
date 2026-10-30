-- ============================================================================
-- Prompt 82 -- Pemecahan bundle (Kirim Hasil model baru) + Barang ketemu.
--
-- PRINSIP (lihat claude prompt/prompt-82-bundle-anak-selisih.md):
--   1. Barcode hanya lahir untuk barang yang NYATA ADA. Hilang bukan bundle.
--   2. Satu bundle satu status (OK/Perbaikan/Reject/TidakLengkap). Campur = pecah.
--   3. Pernyataan Kirim Hasil boleh diedit selama baris log Kirim-nya belum di-lock,
--      dan hanya ADITIF: anak yang sudah lahir tidak bisa diubah/dihapus, qty OK hanya
--      boleh TURUN (sisanya jadi anak baru atau menambah hilang).
--   4. Induk setelah dipecah hanya menyatakan qty OK dan selisih.
--   5. bundles.qty TIDAK PERNAH diisi dari form -- cermin qty_after baris log terakhir.
--   6. Satu pcs hidup di satu bundle dan dicatat sekali.
--
-- @Action = 'SPLIT' -- submit modal "Kirim Hasil" (sekaligus jalur EDIT-nya).
--   Satu transaksi:
--     1. bundle_splits kind = 'split', source_qty_before = Masuk
--     2. Induk: qty = @QtyOk, status = 'OK', missing_qty += Sisa.
--        Satu baris log log_kind = 'Kirim' (qty_delta = @QtyOk - qty sebelum,
--        qty_after = @QtyOk, split_id). Sisa > 0 -> satu baris log_kind = 'Hilang'.
--     3. Tiap baris masalah -> bundle ANAK di root yang sama, sequence_no berikutnya,
--        + baris log log_kind = 'Creation' di anak + bundle_split_results.
--     4. Hanya induk OK yang pindah ke divisi tujuan. Anak Perbaikan dikembalikan ke
--        step ber-bundle sebelumnya (mis. Sewing), anak Reject/TidakLengkap tetap di
--        station ini.
--     5. Cetak ulang stiker induk + stiker tiap anak; needs_reprint = 1.
--
--   EDIT memakai action yang SAMA: kalau step+bundle ini SUDAH punya baris Kirim hidup,
--   @Masuk tidak diambil dari bundles.qty lagi tapi dari MIN(source_qty_before) split
--   sebelumnya -- jadi invarian "OK + Sigma anak + hilang = Masuk" tetap berlaku lintas edit.
--   Split & log lama TIDAK disentuh (aditif).
--
--   Lock otomatis: begitu bundle ini punya baris log Kirim/Creation di step dengan
--   sort_order LEBIH BESAR, edit ditolak ('Kiriman ini sudah diproses station berikutnya.').
--   Baris yang sudah di-lock ditolak dengan prefix 'LOCKED|'.
--
-- @Action = 'FOUND' -- submit modal "Barang ketemu" (dibuka dari angka Hilang kartu artikel).
--   Per bundle tujuan hasil alokasi (LIFO otomatis atau @AllocationJson manual):
--     1. bundle_splits kind = 'found', source = bundle tujuan
--     2. Bundle tujuan: missing_qty -= qty teralokasi (boleh jadi NEGATIF = Lebih).
--        Baris log log_kind = 'Ketemu', qty_delta 0, reason, split_id.
--     3. Bundle ANAK baru di root bundle tujuan, status/kategori dari @Condition,
--        division = divisi station saat ini + baris log 'Creation' di anak.
--     4. Cetak stiker anak. Anak OK masuk WIP station ini dan mengalir normal.
--
-- Prefix pesan error yang dikenali UI: 'LOCKED|'.
-- ============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_BundleSplit_Manage
    @Action                    VARCHAR(20),
    -- ---- SPLIT ----
    @BundleId                  INT = NULL,
    @ArticleWorkflowId         INT = NULL,       -- step yang hasilnya dikirim
    @QtyOk                     INT = NULL,
    -- [{"Category":"RejectJahit","Reason":"benang lepas","Qty":3}, ...]
    @ResultsJson               NVARCHAR(MAX) = NULL,
    @AutoReceiveResourceId     INT = NULL,       -- Prompt 40: penerima manual di divisi tujuan
    -- ---- FOUND ----
    @ArticleSizeId             INT = NULL,
    @QtyFound                  INT = NULL,
    @Condition                 VARCHAR(20) = NULL,   -- OK|Perbaikan|RejectBahan|RejectJahit|RejectPrint
    @Reason                    VARCHAR(500) = NULL,
    -- [{"BundleId":123,"Qty":2}, ...] -- NULL = pakai alokasi LIFO otomatis
    @AllocationJson            NVARCHAR(MAX) = NULL,
    -- ---- umum ----
    @ResourceId                INT = NULL,       -- pelaksana (operator sesi stasiun)
    @ActingDivisionId          INT = NULL,
    @ActingAllowResourceChange BIT = NULL,
    @PublicBaseUrl             VARCHAR(255) = NULL,
    @UserId                    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Kategori masalah yang dikenali (hardcode enum, tidak perlu tabel master).
    DECLARE @Categories TABLE (Category VARCHAR(20) PRIMARY KEY, BundleStatus VARCHAR(15));
    INSERT INTO @Categories (Category, BundleStatus) VALUES
        ('RejectBahan',  'Reject'),
        ('RejectJahit',  'Reject'),
        ('RejectPrint',  'Reject'),
        ('Perbaikan',    'Perbaikan'),
        ('TidakLengkap', 'TidakLengkap');

    IF @Action = 'SPLIT'
    BEGIN
        ------------------------------------------------------------------
        -- 1. Muat bundle sumber + step
        ------------------------------------------------------------------
        DECLARE @SrcArticleId INT, @SrcQty INT, @SrcRootId INT, @SrcSizeId INT,
                @SrcSerial VARCHAR(20), @SrcBundleNo INT, @SrcResourceId INT, @SrcEmployeeId INT;
        SELECT @SrcArticleId = article_id, @SrcQty = qty, @SrcRootId = root_bundle_id,
               @SrcSizeId = article_size_id, @SrcSerial = serial, @SrcBundleNo = bundle_no,
               @SrcResourceId = resource_id, @SrcEmployeeId = employee_id
        FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL;

        IF @SrcArticleId IS NULL
        BEGIN
            RAISERROR('Bundle tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @DivisionId INT, @RequiresBundle BIT, @StepArticleId INT, @SortOrder INT, @IsBundling BIT;
        SELECT @DivisionId = division_id, @RequiresBundle = requires_bundle,
               @StepArticleId = article_id, @SortOrder = sort_order, @IsBundling = is_bundling
        FROM article_workflows
        WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL AND inactive_at IS NULL;

        IF @DivisionId IS NULL
        BEGIN
            RAISERROR('Step workflow tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @RequiresBundle = 0 OR @IsBundling = 1
        BEGIN
            RAISERROR('Kirim Hasil pemecahan hanya untuk step ber-bundle (bukan step Bundling).', 16, 1);
            RETURN;
        END

        IF @StepArticleId <> @SrcArticleId
        BEGIN
            RAISERROR('Bundle tidak sesuai dengan artikel step ini.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @DivisionId
        BEGIN
            RAISERROR('Step ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        -- Project terkunci manual (Prompt 18).
        DECLARE @LockStatus VARCHAR(20), @LockReason VARCHAR(255);
        SELECT @LockStatus = p.manual_status, @LockReason = p.status_reason
        FROM projects p INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @SrcArticleId;

        IF @LockStatus IS NOT NULL
        BEGIN
            DECLARE @LockLabel VARCHAR(30) = CASE @LockStatus
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus END;
            DECLARE @LockSuffix VARCHAR(300) = CASE WHEN LTRIM(RTRIM(ISNULL(@LockReason, ''))) <> ''
                THEN ' (Alasan: ' + @LockReason + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel, @LockSuffix);
            RETURN;
        END

        ------------------------------------------------------------------
        -- 2. Prasyarat: bundle sudah diterima divisi ini di step sebelumnya
        --    (aturan sama dengan SIS_WorkflowLog_Manage @Action = 'CREATE')
        ------------------------------------------------------------------
        DECLARE @PrevStepId INT, @PrevStepDivisionId INT;
        SELECT TOP 1 @PrevStepId = article_workflow_id, @PrevStepDivisionId = division_id
        FROM article_workflows
        WHERE article_id = @SrcArticleId AND deleted_at IS NULL AND inactive_at IS NULL
          AND requires_bundle = 1 AND sort_order < @SortOrder
        ORDER BY sort_order DESC;

        IF @PrevStepId IS NULL OR NOT EXISTS (
            SELECT 1 FROM article_workflow_logs
            WHERE article_workflow_id = @PrevStepId AND bundle_id = @BundleId
              AND received_at IS NOT NULL AND target_division_id = @DivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Bundle belum diterima divisi ini.', 16, 1);
            RETURN;
        END

        -- Prompt 40 SS7: penerima mengikat pelaksana.
        DECLARE @IncomingResourceId INT, @IncomingResourceName VARCHAR(255);
        SELECT TOP 1 @IncomingResourceId = awl.received_by_resource_id, @IncomingResourceName = r.resource_name
        FROM article_workflow_logs awl
        LEFT JOIN resources r ON r.resource_id = awl.received_by_resource_id
        WHERE awl.article_workflow_id = @PrevStepId AND awl.bundle_id = @BundleId
          AND awl.received_at IS NOT NULL AND awl.target_division_id = @DivisionId
          AND awl.deleted_at IS NULL AND awl.received_by_resource_id IS NOT NULL
        ORDER BY awl.created_at DESC;

        IF @IncomingResourceId IS NOT NULL AND (@ResourceId IS NULL OR @IncomingResourceId <> @ResourceId)
        BEGIN
            RAISERROR('Bundle ini atas nama %s. Batalkan penerimaan dulu bila salah orang.', 16, 1, @IncomingResourceName);
            RETURN;
        END

        -- Bundle ditugaskan ke line lain (hanya step station PERTAMA, stasiun terkunci).
        DECLARE @FirstStationSort INT = (
            SELECT MIN(sort_order) FROM article_workflows
            WHERE article_id = @SrcArticleId AND deleted_at IS NULL AND inactive_at IS NULL
              AND requires_bundle = 1 AND is_bundling = 0
        );
        IF @SortOrder = @FirstStationSort AND ISNULL(@ActingAllowResourceChange, 0) = 0
           AND @SrcResourceId IS NOT NULL AND (@ResourceId IS NULL OR @SrcResourceId <> @ResourceId)
        BEGIN
            RAISERROR('Bundle ini ditugaskan ke line lain.', 16, 1);
            RETURN;
        END

        ------------------------------------------------------------------
        -- 3. Jalur EDIT: sudah ada baris Kirim hidup di step ini?
        ------------------------------------------------------------------
        DECLARE @IsEdit BIT = 0;
        IF EXISTS (
            SELECT 1 FROM article_workflow_logs
            WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId
              AND deleted_at IS NULL AND log_kind = 'Kirim'
        )
            SET @IsEdit = 1;

        IF @IsEdit = 1
        BEGIN
            -- Baris sudah di-lock = beku di semua jalur (Prompt 55).
            IF EXISTS (
                SELECT 1 FROM article_workflow_logs
                WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId
                  AND deleted_at IS NULL AND log_kind = 'Kirim' AND lock_id IS NOT NULL
            )
            BEGIN
                RAISERROR('LOCKED|Data sudah di-lock. Ajukan unlock untuk mengubah.', 16, 1);
                RETURN;
            END

            -- Lock otomatis: station berikutnya sudah mencatat hasil bundle ini.
            IF EXISTS (
                SELECT 1
                FROM article_workflow_logs awl
                INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl.article_workflow_id
                WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
                  AND awl.log_kind IN ('Kirim', 'Creation')
                  AND aw2.sort_order > @SortOrder
            )
            BEGIN
                RAISERROR('Kiriman ini sudah diproses station berikutnya, tidak bisa diedit lagi.', 16, 1);
                RETURN;
            END
        END

        ------------------------------------------------------------------
        -- 4. Masuk / anak yang sudah lahir / Sisa
        ------------------------------------------------------------------
        -- @Masuk = qty bundle SEBELUM pemecahan pertama di step ini. Untuk Kirim Hasil
        -- pertama itu sama dengan bundles.qty; untuk EDIT diambil dari split terdahulu
        -- supaya invarian "OK + Sigma anak + hilang = Masuk" tetap utuh lintas edit.
        DECLARE @Masuk INT = ISNULL((
            SELECT MIN(s.source_qty_before)
            FROM bundle_splits s
            WHERE s.source_bundle_id = @BundleId AND s.kind = 'split'
              AND EXISTS (
                  SELECT 1 FROM article_workflow_logs l
                  WHERE l.split_id = s.split_id AND l.bundle_id = @BundleId
                    AND l.article_workflow_id = @ArticleWorkflowId AND l.deleted_at IS NULL
              )
        ), @SrcQty);

        -- Anak yang SUDAH lahir dari pemecahan di step ini (tidak bisa diubah/dihapus).
        DECLARE @ExistingChildQty INT = ISNULL((
            SELECT SUM(sr.qty)
            FROM bundle_split_results sr
            INNER JOIN bundle_splits s ON s.split_id = sr.split_id
            WHERE s.source_bundle_id = @BundleId AND s.kind = 'split'
              AND EXISTS (
                  SELECT 1 FROM article_workflow_logs l
                  WHERE l.split_id = s.split_id AND l.bundle_id = @BundleId
                    AND l.article_workflow_id = @ArticleWorkflowId AND l.deleted_at IS NULL
              )
        ), 0);

        -- Hilang yang sudah dicatat di step ini = sisa invarian.
        DECLARE @ExistingMissing INT = @Masuk - @SrcQty - @ExistingChildQty;

        IF @QtyOk IS NULL OR @QtyOk < 0
        BEGIN
            RAISERROR('Qty OK tidak boleh negatif.', 16, 1);
            RETURN;
        END

        IF @IsEdit = 1 AND @QtyOk > @SrcQty
        BEGIN
            RAISERROR('Qty OK hanya boleh turun saat mengedit kiriman (sekarang %d).', 16, 1, @SrcQty);
            RETURN;
        END

        -- Baris masalah baru.
        DECLARE @Rows TABLE (
            RowNo INT IDENTITY(1,1),
            Category VARCHAR(20),
            Reason VARCHAR(500),
            Qty INT
        );

        IF @ResultsJson IS NOT NULL AND LTRIM(RTRIM(@ResultsJson)) NOT IN ('', '[]')
        BEGIN
            INSERT INTO @Rows (Category, Reason, Qty)
            SELECT j.Category, NULLIF(LTRIM(RTRIM(j.Reason)), ''), j.Qty
            FROM OPENJSON(@ResultsJson)
            WITH (
                Category VARCHAR(20) '$.Category',
                Reason   VARCHAR(500) '$.Reason',
                Qty      INT          '$.Qty'
            ) j;
        END

        IF EXISTS (SELECT 1 FROM @Rows WHERE Qty IS NULL OR Qty <= 0)
        BEGIN
            RAISERROR('Qty baris masalah harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @Rows r WHERE r.Category NOT IN (SELECT Category FROM @Categories))
        BEGIN
            RAISERROR('Kategori masalah tidak dikenal.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @Rows WHERE Reason IS NULL)
        BEGIN
            RAISERROR('Alasan wajib diisi untuk setiap baris masalah.', 16, 1);
            RETURN;
        END

        DECLARE @NewRowQty INT = ISNULL((SELECT SUM(Qty) FROM @Rows), 0);
        DECLARE @Sisa INT = @Masuk - @QtyOk - @ExistingChildQty - @NewRowQty;

        IF @Sisa < 0
        BEGIN
            RAISERROR('Melebihi qty masuk (masuk %d pcs).', 16, 1, @Masuk);
            RETURN;
        END

        DECLARE @MissingDelta INT = @Sisa - @ExistingMissing;

        ------------------------------------------------------------------
        -- 5. Divisi tujuan + auto-terima (pola sama SIS_WorkflowLog_Manage CREATE)
        ------------------------------------------------------------------
        DECLARE @TargetDivisionId INT = NULL, @TargetStepId INT = NULL, @TargetAutoReceive BIT = 0;
        SELECT TOP 1 @TargetStepId = article_workflow_id, @TargetDivisionId = division_id,
                     @TargetAutoReceive = auto_receive
        FROM article_workflows
        WHERE article_id = @SrcArticleId AND deleted_at IS NULL AND inactive_at IS NULL
          AND sort_order > @SortOrder
        ORDER BY sort_order ASC;

        -- Induk kosong (qty OK = 0) TIDAK diserahkan ke mana pun: tidak ada barang yang
        -- pindah. Isinya hidup di bundle anak, masing-masing dengan barcode sendiri.
        IF @QtyOk = 0 SET @TargetDivisionId = NULL;

        DECLARE @AutoReceivedAt DATETIME2 = NULL, @AutoReceivedByResourceId INT = NULL,
                @AutoReceivedRemark VARCHAR(500) = NULL;

        IF @TargetDivisionId IS NOT NULL AND ISNULL(@TargetAutoReceive, 0) = 1
        BEGIN
            SET @AutoReceivedAt = SYSDATETIME();
            SET @AutoReceivedRemark = 'Otomatis: auto-terima';

            DECLARE @CounterpartResourceId INT = NULL;
            IF @ResourceId IS NOT NULL
                SELECT @CounterpartResourceId = cp.resource_id
                FROM resources r
                INNER JOIN resources cp ON cp.resource_id = r.counterpart_resource_id
                WHERE r.resource_id = @ResourceId AND cp.deleted_at IS NULL AND cp.is_active = 1
                  AND cp.division_id = @TargetDivisionId;

            IF @CounterpartResourceId IS NOT NULL
                SET @AutoReceivedByResourceId = @CounterpartResourceId;
            ELSE IF @AutoReceiveResourceId IS NULL
            BEGIN
                RAISERROR('Penerima wajib dipilih karena step tujuan menerima otomatis.', 16, 1);
                RETURN;
            END
            ELSE
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM resources
                    WHERE resource_id = @AutoReceiveResourceId AND deleted_at IS NULL AND is_active = 1
                      AND division_id = @TargetDivisionId
                )
                BEGIN
                    RAISERROR('Penerima bukan resource aktif di divisi tujuan.', 16, 1);
                    RETURN;
                END
                SET @AutoReceivedByResourceId = @AutoReceiveResourceId;
            END
        END

        ------------------------------------------------------------------
        -- 6. Step tujuan tiap kategori anak
        ------------------------------------------------------------------
        -- Reject* / TidakLengkap : tetap di station ini (step yang sama).
        -- Perbaikan              : dikembalikan ke step ber-bundle sebelumnya yang BUKAN
        --                          Bundling (mis. Sewing); kalau tidak ada, tetap di sini.
        DECLARE @PerbaikanStepId INT;
        SELECT TOP 1 @PerbaikanStepId = article_workflow_id
        FROM article_workflows
        WHERE article_id = @SrcArticleId AND deleted_at IS NULL AND inactive_at IS NULL
          AND requires_bundle = 1 AND is_bundling = 0 AND sort_order < @SortOrder
        ORDER BY sort_order DESC;

        IF @PerbaikanStepId IS NULL SET @PerbaikanStepId = @ArticleWorkflowId;

        ------------------------------------------------------------------
        -- 7. Tulis
        ------------------------------------------------------------------
        DECLARE @LockResource VARCHAR(60) = 'article_workflow_restructure_' + CAST(@SrcArticleId AS VARCHAR(20));
        DECLARE @Children TABLE (
            BundleId INT, Serial VARCHAR(20), SequenceNo INT, Qty INT,
            BundleStatus VARCHAR(15), Category VARCHAR(20), DisplayCode VARCHAR(40)
        );

        BEGIN TRAN;
        BEGIN TRY
            DECLARE @LockResult INT;
            EXEC @LockResult = sp_getapplock
                @Resource = @LockResource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
            IF @LockResult < 0
            BEGIN
                RAISERROR('Gagal mengunci artikel. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            -- (1) pernyataan pemecahan
            INSERT INTO bundle_splits (source_bundle_id, source_qty_before, kind, division_id, resource_id, created_at, created_by)
            VALUES (@BundleId, @Masuk, 'split', @DivisionId, @ResourceId, SYSDATETIME(), @UserId);

            DECLARE @SplitId INT = CAST(SCOPE_IDENTITY() AS INT);

            -- (2) baris log Kirim induk + update induk
            INSERT INTO article_workflow_logs (
                article_workflow_id, bundle_id, article_size_id, division_id, resource_id,
                qty_ok, log_type, qty_delta, qty_after, log_kind, split_id,
                target_division_id, received_at, received_by_resource_id, received_remark,
                created_at, created_by
            )
            VALUES (
                @ArticleWorkflowId, @BundleId, NULL, @DivisionId, @ResourceId,
                @QtyOk, 'NORMAL', @QtyOk - @SrcQty, @QtyOk, 'Kirim', @SplitId,
                @TargetDivisionId, @AutoReceivedAt, @AutoReceivedByResourceId, @AutoReceivedRemark,
                SYSDATETIME(), @UserId
            );

            UPDATE bundles
            SET qty = @QtyOk,
                [status] = 'OK',
                missing_qty = missing_qty + @MissingDelta,
                needs_reprint = 1,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE bundle_id = @BundleId;

            -- (2b) selisih yang tidak ditemukan -- barcode TIDAK lahir untuknya.
            IF @MissingDelta <> 0
            BEGIN
                DECLARE @MissingReason VARCHAR(500) =
                    CASE WHEN @MissingDelta > 0
                         THEN CAST(@MissingDelta AS VARCHAR(10)) + ' pcs tidak ditemukan saat Kirim Hasil'
                         ELSE CAST(ABS(@MissingDelta) AS VARCHAR(10)) + ' pcs selisih dikoreksi saat edit Kirim Hasil' END;

                INSERT INTO article_workflow_logs (
                    article_workflow_id, bundle_id, article_size_id, division_id, resource_id,
                    qty_ok, log_type, qty_delta, qty_after, log_kind, split_id, reason,
                    target_division_id, received_at, received_remark, created_at, created_by
                )
                VALUES (
                    @ArticleWorkflowId, @BundleId, NULL, @DivisionId, @ResourceId,
                    0, 'NORMAL', 0, @QtyOk, 'Hilang', @SplitId, @MissingReason,
                    NULL, SYSDATETIME(), NULL, SYSDATETIME(), @UserId
                );
            END

            -- (3) bundle anak per baris masalah
            DECLARE @RowNo INT = 1, @MaxRowNo INT = ISNULL((SELECT MAX(RowNo) FROM @Rows), 0);
            WHILE @RowNo <= @MaxRowNo
            BEGIN
                DECLARE @RCategory VARCHAR(20), @RReason VARCHAR(500), @RQty INT;
                SELECT @RCategory = Category, @RReason = Reason, @RQty = Qty FROM @Rows WHERE RowNo = @RowNo;

                DECLARE @RStatus VARCHAR(15) = (SELECT BundleStatus FROM @Categories WHERE Category = @RCategory);

                -- sequence_no berikutnya diambil dari ROOT (anak-dari-anak tetap datar)
                DECLARE @NextSeq INT = ISNULL((
                    SELECT MAX(sequence_no) FROM bundles WHERE root_bundle_id = @SrcRootId AND deleted_at IS NULL
                ), 0) + 1;

                DECLARE @RootSerial VARCHAR(20) = (SELECT serial FROM bundles WHERE bundle_id = @SrcRootId);
                DECLARE @ChildSerial VARCHAR(20) = @RootSerial + '-' + CAST(@NextSeq AS VARCHAR(10));
                DECLARE @RootBundleNo INT = (SELECT bundle_no FROM bundles WHERE bundle_id = @SrcRootId);

                DECLARE @ChildSort INT = ISNULL((
                    SELECT MAX(sort_order) FROM bundles WHERE article_size_id = @SrcSizeId AND deleted_at IS NULL
                ), 0) + 1;

                INSERT INTO bundles (
                    article_id, article_size_id, serial, bundle_no, qty, sort_order,
                    resource_id, employee_id, remarks, created_at, created_by,
                    source, needs_reprint,
                    parent_bundle_id, root_bundle_id, sequence_no, [status], reject_category, reject_reason, missing_qty
                )
                VALUES (
                    @SrcArticleId, @SrcSizeId, @ChildSerial, @RootBundleNo, @RQty, @ChildSort,
                    @SrcResourceId, @SrcEmployeeId, NULL, SYSDATETIME(), @UserId,
                    'MANUAL', 1,
                    @BundleId, @SrcRootId, @NextSeq, @RStatus, @RCategory, @RReason, 0
                );

                DECLARE @ChildId INT = CAST(SCOPE_IDENTITY() AS INT);

                -- Step tujuan anak + step tempat baris Creation-nya diletakkan: baris
                -- Creation harus berada di step TEPAT SEBELUM step tujuan, dengan
                -- target_division_id = divisi step tujuan dan received_at terisi, supaya
                -- anak langsung muncul sebagai WIP di station yang harus menanganinya
                -- (definisi WIP = ada baris masuk yang sudah diterima, lihat
                --  SIS_Station_InProgress).
                DECLARE @ChildTargetStepId INT = CASE WHEN @RStatus = 'Perbaikan' THEN @PerbaikanStepId ELSE @ArticleWorkflowId END;
                DECLARE @ChildTargetDivisionId INT, @ChildTargetSort INT;
                SELECT @ChildTargetDivisionId = division_id, @ChildTargetSort = sort_order
                FROM article_workflows WHERE article_workflow_id = @ChildTargetStepId;

                DECLARE @ChildCreationStepId INT, @ChildCreationDivisionId INT;
                SELECT TOP 1 @ChildCreationStepId = article_workflow_id, @ChildCreationDivisionId = division_id
                FROM article_workflows
                WHERE article_id = @SrcArticleId AND deleted_at IS NULL AND inactive_at IS NULL
                  AND requires_bundle = 1 AND sort_order < @ChildTargetSort
                ORDER BY sort_order DESC;

                IF @ChildCreationStepId IS NULL
                BEGIN
                    -- Tidak ada step sebelum step tujuan (artikel tanpa Bundling) -- taruh
                    -- baris Creation di step tujuan itu sendiri tanpa serah lanjutan.
                    SET @ChildCreationStepId = @ChildTargetStepId;
                    SET @ChildCreationDivisionId = @ChildTargetDivisionId;
                    SET @ChildTargetDivisionId = NULL;
                END

                INSERT INTO article_workflow_logs (
                    article_workflow_id, bundle_id, article_size_id, division_id, resource_id,
                    qty_ok, log_type, qty_delta, qty_after, log_kind, split_id, reason,
                    target_division_id, received_at, received_by_resource_id, received_remark,
                    created_at, created_by
                )
                VALUES (
                    @ChildCreationStepId, @ChildId, NULL, @ChildCreationDivisionId, @ResourceId,
                    0, 'NORMAL', @RQty, @RQty, 'Creation', @SplitId, @RReason,
                    @ChildTargetDivisionId,
                    CASE WHEN @ChildTargetDivisionId IS NULL THEN NULL ELSE SYSDATETIME() END,
                    NULL,
                    CASE WHEN @ChildTargetDivisionId IS NULL THEN NULL ELSE 'Otomatis: bundle anak hasil pemecahan' END,
                    SYSDATETIME(), @UserId
                );

                INSERT INTO bundle_split_results (split_id, bundle_id, qty, [status], reject_category, reject_reason, is_system_choice)
                VALUES (@SplitId, @ChildId, @RQty, @RStatus, @RCategory, @RReason, 0);

                INSERT INTO @Children (BundleId, Serial, SequenceNo, Qty, BundleStatus, Category, DisplayCode)
                VALUES (@ChildId, @ChildSerial, @NextSeq, @RQty, @RStatus, @RCategory, NULL);

                SET @RowNo += 1;
            END

            -- (5) cetak ulang stiker induk + stiker tiap anak
            IF @QtyOk > 0
                EXEC SIS_BundleSplit_PrintLabel @BundleId = @BundleId, @PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId;

            DECLARE @PrintChildId INT;
            DECLARE child_cur CURSOR LOCAL FAST_FORWARD FOR SELECT BundleId FROM @Children;
            OPEN child_cur;
            FETCH NEXT FROM child_cur INTO @PrintChildId;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC SIS_BundleSplit_PrintLabel @BundleId = @PrintChildId, @PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId;
                FETCH NEXT FROM child_cur INTO @PrintChildId;
            END
            CLOSE child_cur;
            DEALLOCATE child_cur;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH

        SELECT c.BundleId, c.Serial, c.SequenceNo, c.Qty, c.BundleStatus AS [Status], c.Category,
               CAST(ISNULL(pr.bundle_letter + '-', '') + CAST(b.bundle_no AS VARCHAR(10))
                    + '-' + CAST(c.SequenceNo AS VARCHAR(10)) AS VARCHAR(40)) AS DisplayCode
        FROM @Children c
        INNER JOIN bundles b ON b.bundle_id = c.BundleId
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects pr ON pr.project_id = a.project_id
        ORDER BY c.SequenceNo;
    END

    ELSE IF @Action = 'FOUND'
    BEGIN
        ------------------------------------------------------------------
        -- Barang ketemu: selisih induk ditutup, anak baru lahir.
        ------------------------------------------------------------------
        IF @QtyFound IS NULL OR @QtyFound <= 0
        BEGIN
            RAISERROR('Qty ketemu harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF @Condition IS NULL OR (@Condition <> 'OK' AND @Condition NOT IN (SELECT Category FROM @Categories))
            OR @Condition = 'TidakLengkap'
        BEGIN
            RAISERROR('Kondisi barang ketemu tidak dikenal.', 16, 1);
            RETURN;
        END

        IF @Condition <> 'OK' AND LTRIM(RTRIM(ISNULL(@Reason, ''))) = ''
        BEGIN
            RAISERROR('Alasan wajib diisi kalau kondisi bukan OK.', 16, 1);
            RETURN;
        END

        DECLARE @FoundStatus VARCHAR(15) = CASE WHEN @Condition = 'OK' THEN 'OK'
            ELSE (SELECT BundleStatus FROM @Categories WHERE Category = @Condition) END;
        DECLARE @FoundCategory VARCHAR(20) = CASE WHEN @Condition = 'OK' THEN NULL ELSE @Condition END;

        DECLARE @FoundDivisionId INT = @ActingDivisionId;
        IF @FoundDivisionId IS NULL
        BEGIN
            RAISERROR('Divisi station wajib diketahui untuk mencatat barang ketemu.', 16, 1);
            RETURN;
        END

        -- Step ber-bundle milik divisi ini untuk artikel size tsb -- dipakai sebagai step
        -- tujuan anak yang lahir (anak OK langsung masuk WIP station ini).
        DECLARE @FoundArticleId INT = (
            SELECT article_id FROM article_sizes WHERE article_size_id = @ArticleSizeId AND deleted_at IS NULL
        );
        IF @FoundArticleId IS NULL
        BEGIN
            RAISERROR('Ukuran tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @FoundStepId INT, @FoundStepSort INT;
        SELECT TOP 1 @FoundStepId = article_workflow_id, @FoundStepSort = sort_order
        FROM article_workflows
        WHERE article_id = @FoundArticleId AND deleted_at IS NULL AND inactive_at IS NULL
          AND requires_bundle = 1 AND is_bundling = 0 AND division_id = @FoundDivisionId
        ORDER BY sort_order ASC;

        IF @FoundStepId IS NULL
        BEGIN
            RAISERROR('Divisi ini tidak punya step ber-bundle untuk artikel tersebut.', 16, 1);
            RETURN;
        END

        DECLARE @FoundCreationStepId INT, @FoundCreationDivisionId INT;
        SELECT TOP 1 @FoundCreationStepId = article_workflow_id, @FoundCreationDivisionId = division_id
        FROM article_workflows
        WHERE article_id = @FoundArticleId AND deleted_at IS NULL AND inactive_at IS NULL
          AND requires_bundle = 1 AND sort_order < @FoundStepSort
        ORDER BY sort_order DESC;

        ------------------------------------------------------------------
        -- Alokasi: manual (@AllocationJson) atau LIFO otomatis.
        -- LIFO = induk ber-missing_qty > 0 di size itu, urut created_at baris log Hilang
        -- TERAKHIR desc ("yang paling baru hilang diisi lebih dulu").
        -- Qty boleh MELEBIHI total selisih -- kelebihan ditempel ke bundle LIFO terakhir
        -- (missing_qty jadi negatif = Lebih), tidak lahir anak terpisah.
        ------------------------------------------------------------------
        DECLARE @Alloc TABLE (RowNo INT IDENTITY(1,1), BundleId INT, Qty INT);
        DECLARE @IsSystemChoice BIT = 1;

        IF @AllocationJson IS NOT NULL AND LTRIM(RTRIM(@AllocationJson)) NOT IN ('', '[]')
        BEGIN
            SET @IsSystemChoice = 0;
            INSERT INTO @Alloc (BundleId, Qty)
            SELECT j.BundleId, j.Qty
            FROM OPENJSON(@AllocationJson)
            WITH (BundleId INT '$.BundleId', Qty INT '$.Qty') j
            WHERE j.Qty > 0;

            IF ISNULL((SELECT SUM(Qty) FROM @Alloc), 0) <> @QtyFound
            BEGIN
                RAISERROR('Total alokasi harus sama dengan qty ketemu (%d).', 16, 1, @QtyFound);
                RETURN;
            END

            IF EXISTS (
                SELECT 1 FROM @Alloc al
                LEFT JOIN bundles b ON b.bundle_id = al.BundleId AND b.deleted_at IS NULL
                WHERE b.bundle_id IS NULL OR b.article_size_id <> @ArticleSizeId OR b.sequence_no <> 0
            )
            BEGIN
                RAISERROR('Bundle tujuan alokasi tidak valid untuk ukuran ini.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            ;WITH Candidates AS (
                SELECT b.bundle_id, b.missing_qty,
                       ISNULL((
                           SELECT MAX(l.created_at) FROM article_workflow_logs l
                           WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
                       ), b.created_at) AS LastMissingAt
                FROM bundles b
                WHERE b.deleted_at IS NULL AND b.sequence_no = 0
                  AND b.article_size_id = @ArticleSizeId AND b.missing_qty > 0
            ),
            Ordered AS (
                SELECT bundle_id, missing_qty,
                       SUM(missing_qty) OVER (ORDER BY LastMissingAt DESC, bundle_id DESC ROWS UNBOUNDED PRECEDING) AS CumQty,
                       ROW_NUMBER() OVER (ORDER BY LastMissingAt DESC, bundle_id DESC) AS rn
                FROM Candidates
            )
            INSERT INTO @Alloc (BundleId, Qty)
            SELECT bundle_id,
                   CASE WHEN CumQty <= @QtyFound THEN missing_qty
                        ELSE @QtyFound - (CumQty - missing_qty) END
            FROM Ordered
            WHERE (CumQty - missing_qty) < @QtyFound
            ORDER BY rn;

            DECLARE @Allocated INT = ISNULL((SELECT SUM(Qty) FROM @Alloc), 0);

            IF @Allocated < @QtyFound
            BEGIN
                -- Kelebihan di atas total selisih ditempel ke bundle LIFO TERAKHIR yang
                -- teralokasi (dicatat sebagai Lebih di bundle itu, tidak lahir anak lain).
                DECLARE @LastAllocRow INT = (SELECT MAX(RowNo) FROM @Alloc);

                IF @LastAllocRow IS NULL
                BEGIN
                    -- Tidak ada selisih terbuka sama sekali: tempel ke induk TERBARU size ini.
                    DECLARE @FallbackBundleId INT;
                    SELECT TOP 1 @FallbackBundleId = bundle_id
                    FROM bundles
                    WHERE deleted_at IS NULL AND sequence_no = 0 AND article_size_id = @ArticleSizeId
                    ORDER BY created_at DESC, bundle_id DESC;

                    IF @FallbackBundleId IS NULL
                    BEGIN
                        RAISERROR('Tidak ada bundle induk untuk ukuran ini.', 16, 1);
                        RETURN;
                    END

                    INSERT INTO @Alloc (BundleId, Qty) VALUES (@FallbackBundleId, @QtyFound);
                END
                ELSE
                    UPDATE @Alloc SET Qty = Qty + (@QtyFound - @Allocated) WHERE RowNo = @LastAllocRow;
            END
        END

        DECLARE @FoundChildren TABLE (BundleId INT, Serial VARCHAR(20), SequenceNo INT, Qty INT);

        BEGIN TRAN;
        BEGIN TRY
            DECLARE @FoundLockResource VARCHAR(60) = 'article_workflow_restructure_' + CAST(@FoundArticleId AS VARCHAR(20));
            DECLARE @FoundLockResult INT;
            EXEC @FoundLockResult = sp_getapplock
                @Resource = @FoundLockResource, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
            IF @FoundLockResult < 0
            BEGIN
                RAISERROR('Gagal mengunci artikel. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            DECLARE @ARow INT = 1, @AMaxRow INT = ISNULL((SELECT MAX(RowNo) FROM @Alloc), 0);
            WHILE @ARow <= @AMaxRow
            BEGIN
                DECLARE @TgtBundleId INT, @TgtQty INT;
                SELECT @TgtBundleId = BundleId, @TgtQty = Qty FROM @Alloc WHERE RowNo = @ARow;

                DECLARE @TgtQtyBefore INT, @TgtRootId INT, @TgtResourceId INT, @TgtEmployeeId INT;
                SELECT @TgtQtyBefore = qty, @TgtRootId = root_bundle_id,
                       @TgtResourceId = resource_id, @TgtEmployeeId = employee_id
                FROM bundles WHERE bundle_id = @TgtBundleId;

                -- (1) pernyataan penemuan
                INSERT INTO bundle_splits (source_bundle_id, source_qty_before, kind, division_id, resource_id, created_at, created_by)
                VALUES (@TgtBundleId, @TgtQtyBefore, 'found', @FoundDivisionId, @ResourceId, SYSDATETIME(), @UserId);

                DECLARE @FoundSplitId INT = CAST(SCOPE_IDENTITY() AS INT);

                -- (2) selisih induk berkurang (boleh jadi negatif = Lebih) + baris log Ketemu
                UPDATE bundles
                SET missing_qty = missing_qty - @TgtQty,
                    updated_at = SYSDATETIME(),
                    updated_by = @UserId
                WHERE bundle_id = @TgtBundleId;

                INSERT INTO article_workflow_logs (
                    article_workflow_id, bundle_id, article_size_id, division_id, resource_id,
                    qty_ok, log_type, qty_delta, qty_after, log_kind, split_id, reason,
                    target_division_id, received_at, created_at, created_by
                )
                VALUES (
                    @FoundStepId, @TgtBundleId, NULL, @FoundDivisionId, @ResourceId,
                    0, 'NORMAL', 0, @TgtQtyBefore, 'Ketemu', @FoundSplitId,
                    CAST(@TgtQty AS VARCHAR(10)) + ' pcs ketemu (' + @Condition + ')'
                        + CASE WHEN LTRIM(RTRIM(ISNULL(@Reason, ''))) = '' THEN '' ELSE ' - ' + @Reason END,
                    NULL, SYSDATETIME(), SYSDATETIME(), @UserId
                );

                -- (3) bundle anak baru di root bundle tujuan
                DECLARE @FNextSeq INT = ISNULL((
                    SELECT MAX(sequence_no) FROM bundles WHERE root_bundle_id = @TgtRootId AND deleted_at IS NULL
                ), 0) + 1;
                DECLARE @FRootSerial VARCHAR(20) = (SELECT serial FROM bundles WHERE bundle_id = @TgtRootId);
                DECLARE @FRootBundleNo INT = (SELECT bundle_no FROM bundles WHERE bundle_id = @TgtRootId);
                DECLARE @FChildSerial VARCHAR(20) = @FRootSerial + '-' + CAST(@FNextSeq AS VARCHAR(10));
                DECLARE @FChildSort INT = ISNULL((
                    SELECT MAX(sort_order) FROM bundles WHERE article_size_id = @ArticleSizeId AND deleted_at IS NULL
                ), 0) + 1;

                INSERT INTO bundles (
                    article_id, article_size_id, serial, bundle_no, qty, sort_order,
                    resource_id, employee_id, remarks, created_at, created_by,
                    source, needs_reprint,
                    parent_bundle_id, root_bundle_id, sequence_no, [status], reject_category, reject_reason, missing_qty
                )
                VALUES (
                    @FoundArticleId, @ArticleSizeId, @FChildSerial, @FRootBundleNo, @TgtQty, @FChildSort,
                    @TgtResourceId, @TgtEmployeeId, NULL, SYSDATETIME(), @UserId,
                    'MANUAL', 1,
                    @TgtBundleId, @TgtRootId, @FNextSeq, @FoundStatus, @FoundCategory,
                    NULLIF(LTRIM(RTRIM(ISNULL(@Reason, ''))), ''), 0
                );

                DECLARE @FChildId INT = CAST(SCOPE_IDENTITY() AS INT);

                INSERT INTO article_workflow_logs (
                    article_workflow_id, bundle_id, article_size_id, division_id, resource_id,
                    qty_ok, log_type, qty_delta, qty_after, log_kind, split_id, reason,
                    target_division_id, received_at, received_by_resource_id, received_remark,
                    created_at, created_by
                )
                VALUES (
                    ISNULL(@FoundCreationStepId, @FoundStepId), @FChildId, NULL,
                    ISNULL(@FoundCreationDivisionId, @FoundDivisionId), @ResourceId,
                    0, 'NORMAL', @TgtQty, @TgtQty, 'Creation', @FoundSplitId, @Reason,
                    CASE WHEN @FoundCreationStepId IS NULL THEN NULL ELSE @FoundDivisionId END,
                    CASE WHEN @FoundCreationStepId IS NULL THEN NULL ELSE SYSDATETIME() END,
                    NULL,
                    CASE WHEN @FoundCreationStepId IS NULL THEN NULL ELSE 'Otomatis: barang ketemu' END,
                    SYSDATETIME(), @UserId
                );

                INSERT INTO bundle_split_results (split_id, bundle_id, qty, [status], reject_category, reject_reason, is_system_choice)
                VALUES (@FoundSplitId, @FChildId, @TgtQty, @FoundStatus, @FoundCategory,
                        NULLIF(LTRIM(RTRIM(ISNULL(@Reason, ''))), ''), @IsSystemChoice);

                INSERT INTO @FoundChildren (BundleId, Serial, SequenceNo, Qty)
                VALUES (@FChildId, @FChildSerial, @FNextSeq, @TgtQty);

                EXEC SIS_BundleSplit_PrintLabel @BundleId = @FChildId, @PublicBaseUrl = @PublicBaseUrl, @UserId = @UserId;

                SET @ARow += 1;
            END

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH

        SELECT c.BundleId, c.Serial, c.SequenceNo, c.Qty,
               CAST(ISNULL(pr.bundle_letter + '-', '') + CAST(b.bundle_no AS VARCHAR(10))
                    + '-' + CAST(c.SequenceNo AS VARCHAR(10)) AS VARCHAR(40)) AS DisplayCode
        FROM @FoundChildren c
        INNER JOIN bundles b ON b.bundle_id = c.BundleId
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects pr ON pr.project_id = a.project_id
        ORDER BY c.SequenceNo;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak dikenal.', 16, 1);
        RETURN;
    END
END;
GO

-- ---------------------------------------------------------------------------
-- Stiker bundle (induk maupun anak). Sama template BUNDLE_LABEL yang sudah ada;
-- bedanya payload membawa sequence_no (supaya nomor tercetak 'K-49-1') dan
-- remark berisi STATUS + KATEGORI bundle. Stiker anak TIDAK mencantumkan asal.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_BundleSplit_PrintLabel
    @BundleId      INT,
    @PublicBaseUrl VARCHAR(255) = NULL,
    @Copies        INT = 1,
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Serial VARCHAR(20), @Status VARCHAR(15), @Category VARCHAR(20), @RejectReason VARCHAR(500);
    SELECT @Serial = serial, @Status = [status], @Category = reject_category, @RejectReason = reject_reason
    FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL;

    IF @Serial IS NULL RETURN;

    DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/b/' + @Serial;

    -- Teks remark stiker: 'REJECT JAHIT - benang lepas' / 'OK'. Dipakai supaya status &
    -- kategori terbaca tanpa mengubah template TSPL (field remark sudah dicetak).
    DECLARE @LabelRemark VARCHAR(255) =
        CASE WHEN @Status = 'OK' THEN 'OK'
             ELSE UPPER(ISNULL(@Category, @Status))
                  + CASE WHEN LTRIM(RTRIM(ISNULL(@RejectReason, ''))) = '' THEN '' ELSE ' - ' + @RejectReason END
        END;

    DECLARE @Payload NVARCHAR(MAX) = (
        SELECT
            b.serial AS serial,
            b.bundle_no AS bundle_no,
            p.bundle_letter AS bundle_letter,
            b.sequence_no AS sequence_no,
            b.[status] AS bundle_status,
            b.reject_category AS reject_category,
            @QrContent AS qr_content,
            p.project_name AS project_name,
            p.no_po AS no_po,
            p.material_name AS material_name,
            a.article_name AS article_name,
            b.remarks AS bundle_remarks,
            a.style AS style,
            a.color AS color,
            spk.size_pack_name AS size_pack_name,
            spd.size_name AS size_name,
            b.qty AS qty,
            res.resource_name AS resource_name,
            emp.employee_name AS employee_name,
            b.created_at AS started_at,
            @LabelRemark AS remark
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN size_packs spk ON spk.size_pack_id = a.size_pack_id
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources res ON res.resource_id = b.resource_id
        LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
        WHERE b.bundle_id = @BundleId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    DECLARE @Copy INT = 0;
    WHILE @Copy < ISNULL(@Copies, 1)
    BEGIN
        INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
        VALUES ('BUNDLE_LABEL', @BundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);
        SET @Copy += 1;
    END
END;
GO

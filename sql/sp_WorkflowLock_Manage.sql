-- Prompt 55: SP lock baris article_workflow_logs (dipakai tombol Lock di stasiun, UI Prompt 56).
--
-- Lock hanya menyangkut SISI PENGIRIM: baris OUT milik divisi pembuat (division_id). Sisi
-- penerima (RECEIVE/UNRECEIVE, kolom received_*) TIDAK pernah dikunci -- divisi tujuan tetap
-- bisa menerima/membatalkan penerimaan baris yang sudah di-lock.
--
-- Tidak ada @Action = 'UNLOCK' di sini dan memang TIDAK BOLEH ada -- pelepasan lock satu-
-- satunya jalur adalah SIS_UnlockRequest_Manage APPROVE (sql/sp_UnlockRequest_Manage.sql).
--
-- Guard "lock_id IS NOT NULL -> tolak" ada di SIS_WorkflowLog_Manage (UPDATE/REVISE_HANDOVER/
-- CANCEL_HANDOVER/DELETE), SIS_Bundle_Manage (UPDATE/DELETE), SIS_ManualOutput_Manage
-- (UPDATE/DELETE) dan SIS_SuperAdmin_Manage (LOG_UPDATE/LOG_DELETE/EDIT_LOG/BUNDLE_UPDATE/
-- EDIT_BUNDLE) -- pesan seragam berprefix 'LOCKED|' supaya UI bisa mengenalinya.
--
-- ---------------------------------------------------------------------------------
-- Prompt 83 -- satu lock menampung DUA sumber baris:
--   source='LOG'    -> article_workflow_logs (@WorkflowLogIds)
--   source='MANUAL' -> manual_outputs        (@ManualOutputIds)
-- Keduanya opsional satu per satu, tapi minimal salah satu harus berisi. Baris manual
-- divalidasi dengan aturan yang SAMA: milik @DivisionId dan lock_id masih NULL.
--
-- Prompt 83 juga MEMBEKUKAN HARGA di sini: workflow_lock_items.unit_price diisi dari
-- master tarif article_workflows.unit_price lewat dbo.SIS_fn_StepUnitPrice /
-- dbo.SIS_fn_ManualStepUnitPrice (sql/sp_ManualOutput_Manage.sql). Tarif yang tidak
-- ketemu ditulis NULL, BUKAN 0 -- 0 adalah harga yang sah untuk step Bundling. Baris
-- NULL itulah yang disorot di Rekap Gajian dan memblokir finalisasi periode.
-- Setelah di-lock, harga TIDAK PERNAH ikut berubah kalau master tarif diubah; koreksi
-- hanya lewat SIS_LockItem_UpdatePrice.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowLock_Manage
    @Action           VARCHAR(20),
    @WorkflowLogIds   VARCHAR(MAX) = NULL,   -- CSV, pola STRING_SPLIT seperti SP lain
    @ManualOutputIds  VARCHAR(MAX) = NULL,   -- Prompt 83: CSV id manual_outputs
    @DivisionId       INT = NULL,
    @StationId        INT = NULL,
    @ResourceId       INT = NULL,
    @PayrollPeriodId  INT = NULL,
    @UserId           INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'LOCK'
    BEGIN
        IF @UserId IS NULL
        BEGIN
            RAISERROR('User pencatat tidak dikenal.', 16, 1);
            RETURN;
        END

        IF @DivisionId IS NULL
        BEGIN
            RAISERROR('Divisi tidak dikenal.', 16, 1);
            RETURN;
        END

        -- Daftar ID yang diminta (dedup, buang entri kosong).
        DECLARE @Ids TABLE (workflow_log_id INT PRIMARY KEY);
        INSERT INTO @Ids (workflow_log_id)
        SELECT DISTINCT CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(ISNULL(@WorkflowLogIds, ''), ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        -- Prompt 83: daftar id manual_outputs, pola yang sama.
        DECLARE @ManualIds TABLE (manual_output_id INT PRIMARY KEY);
        INSERT INTO @ManualIds (manual_output_id)
        SELECT DISTINCT CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(ISNULL(@ManualOutputIds, ''), ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        IF NOT EXISTS (SELECT 1 FROM @Ids) AND NOT EXISTS (SELECT 1 FROM @ManualIds)
        BEGIN
            RAISERROR('Pilih minimal satu baris untuk di-lock.', 16, 1);
            RETURN;
        END

        -- Semua baris divalidasi sekaligus -- satu gagal, seluruhnya ditolak (sebut ID-nya).
        DECLARE @BadIds VARCHAR(500);

        SELECT @BadIds = STUFF((
            SELECT ', ' + CAST(i.workflow_log_id AS VARCHAR(20))
            FROM @Ids i
            WHERE NOT EXISTS (
                SELECT 1 FROM article_workflow_logs awl
                WHERE awl.workflow_log_id = i.workflow_log_id AND awl.deleted_at IS NULL
                  AND awl.division_id = @DivisionId
            )
            ORDER BY i.workflow_log_id
            FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, '');

        IF @BadIds IS NOT NULL
        BEGIN
            RAISERROR('Sebagian baris tidak ditemukan atau bukan milik divisi ini (ID: %s).', 16, 1, @BadIds);
            RETURN;
        END

        SELECT @BadIds = STUFF((
            SELECT ', ' + CAST(awl.workflow_log_id AS VARCHAR(20))
            FROM article_workflow_logs awl
            INNER JOIN @Ids i ON i.workflow_log_id = awl.workflow_log_id
            WHERE awl.lock_id IS NOT NULL
            ORDER BY awl.workflow_log_id
            FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, '');

        IF @BadIds IS NOT NULL
        BEGIN
            RAISERROR('Sebagian baris sudah di-lock, muat ulang data (ID: %s).', 16, 1, @BadIds);
            RETURN;
        END

        -- ----- Prompt 83: validasi baris MANUAL, aturan sama dengan baris log -----
        SELECT @BadIds = STUFF((
            SELECT ', ' + CAST(mi.manual_output_id AS VARCHAR(20))
            FROM @ManualIds mi
            WHERE NOT EXISTS (
                SELECT 1 FROM manual_outputs mo
                WHERE mo.manual_output_id = mi.manual_output_id AND mo.deleted_at IS NULL
                  AND mo.division_id = @DivisionId
            )
            ORDER BY mi.manual_output_id
            FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, '');

        IF @BadIds IS NOT NULL
        BEGIN
            RAISERROR('Sebagian output manual tidak ditemukan atau bukan milik divisi ini (ID: %s).', 16, 1, @BadIds);
            RETURN;
        END

        SELECT @BadIds = STUFF((
            SELECT ', ' + CAST(mo.manual_output_id AS VARCHAR(20))
            FROM manual_outputs mo
            INNER JOIN @ManualIds mi ON mi.manual_output_id = mo.manual_output_id
            WHERE mo.lock_id IS NOT NULL
            ORDER BY mo.manual_output_id
            FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, '');

        IF @BadIds IS NOT NULL
        BEGIN
            RAISERROR('Sebagian output manual sudah di-lock, muat ulang data (ID: %s).', 16, 1, @BadIds);
            RETURN;
        END

        -- Operator sesi stasiun wajib -- lock adalah pernyataan "data periode ini sudah final
        -- dari sisi saya", jadi harus ada yang bertanda tangan.
        IF @ResourceId IS NULL OR NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @ResourceId AND division_id = @DivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Operator wajib dipilih.', 16, 1);
            RETURN;
        END

        IF @StationId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM stations WHERE station_id = @StationId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Stasiun tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @PeriodStart DATETIME2, @PeriodFinalizedAt DATETIME2;
        SELECT @PeriodStart = period_start, @PeriodFinalizedAt = finalized_at
        FROM payroll_periods
        WHERE payroll_period_id = @PayrollPeriodId AND deleted_at IS NULL;

        IF @PeriodStart IS NULL
        BEGIN
            RAISERROR('Periode gajian tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @PeriodFinalizedAt IS NOT NULL
        BEGIN
            RAISERROR('Periode gajian sudah final.', 16, 1);
            RETURN;
        END

        -- Batas ke DEPAN saja: paling jauh satu periode setelah periode berjalan (period_start
        -- periode pilihan <= period_end periode berjalan). Periode LAMPAU yang belum final tetap
        -- boleh -- input susulan untuk minggu kemarin itu normal, salah pilih ke masa depan tidak.
        DECLARE @CurrentPeriodId INT = dbo.SIS_fn_PayrollPeriodIdAt(SYSDATETIME());

        IF @CurrentPeriodId IS NULL
        BEGIN
            RAISERROR('Periode gajian untuk tanggal hari ini belum di-generate. Jalankan SIS_PayrollPeriod_Manage GENERATE_YEAR terlebih dahulu.', 16, 1);
            RETURN;
        END

        DECLARE @CurrentPeriodEnd DATETIME2 = (SELECT period_end FROM payroll_periods WHERE payroll_period_id = @CurrentPeriodId);

        IF @PeriodStart > @CurrentPeriodEnd
        BEGIN
            RAISERROR('Periode gajian terlalu jauh ke depan.', 16, 1);
            RETURN;
        END

        DECLARE @NewLockId INT, @LockedCount INT, @ManualLockedCount INT = 0;

        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO workflow_locks (
                division_id, station_id, payroll_period_id, locked_by_resource_id, locked_by_name,
                locked_at, created_at, created_by
            )
            VALUES (
                @DivisionId, @StationId, @PayrollPeriodId, @ResourceId, NULL,
                SYSDATETIME(), SYSDATETIME(), @UserId
            );

            SET @NewLockId = CAST(SCOPE_IDENTITY() AS INT);

            -- Prompt 83: source='LOG' ditulis eksplisit (tidak mengandalkan DEFAULT) dan
            -- unit_price dibekukan dari master tarif step artikel baris itu.
            INSERT INTO workflow_lock_items (
                lock_id, workflow_log_id, source, manual_output_id, unit_price,
                snap_qty_ok, snap_qty_reject_print, snap_qty_reject_fabric, snap_qty_reject_sewing,
                snap_qty_reject_rework, snap_qty_lost,
                snap_article_size_id, snap_resource_id, snap_target_division_id,
                created_at, created_by
            )
            SELECT @NewLockId, awl.workflow_log_id, 'LOG', NULL,
                   dbo.SIS_fn_StepUnitPrice(awl.article_workflow_id),
                   awl.qty_ok, awl.qty_reject_print, awl.qty_reject_fabric, awl.qty_reject_sewing,
                   awl.qty_reject_rework, awl.qty_lost,
                   awl.article_size_id, awl.resource_id, awl.target_division_id,
                   SYSDATETIME(), @UserId
            FROM article_workflow_logs awl
            INNER JOIN @Ids i ON i.workflow_log_id = awl.workflow_log_id
            WHERE awl.deleted_at IS NULL AND awl.lock_id IS NULL;

            SET @LockedCount = @@ROWCOUNT;

            UPDATE awl
            SET awl.lock_id = @NewLockId
            FROM article_workflow_logs awl
            INNER JOIN @Ids i ON i.workflow_log_id = awl.workflow_log_id
            WHERE awl.deleted_at IS NULL AND awl.lock_id IS NULL;

            -- ----- Prompt 83: baris MANUAL -----
            -- Kolom snap_* diisi dari manual_outputs sebisanya: snap_qty_ok = qty (boleh
            -- minus -- itu catatan potongan) dan snap_resource_id = pemilik upah. Kolom
            -- snap reject per kategori TIDAK dipakai di sini: output manual hanya punya
            -- satu angka reject tanpa kategori, dan memaksanya masuk salah satu kategori
            -- akan mengotori laporan reject per kategori. reject_qty baris manual dibaca
            -- langsung dari manual_outputs oleh rekap.
            INSERT INTO workflow_lock_items (
                lock_id, workflow_log_id, source, manual_output_id, unit_price,
                snap_qty_ok, snap_qty_reject_print, snap_qty_reject_fabric, snap_qty_reject_sewing,
                snap_qty_reject_rework, snap_qty_lost,
                snap_article_size_id, snap_resource_id, snap_target_division_id,
                created_at, created_by
            )
            SELECT @NewLockId, NULL, 'MANUAL', mo.manual_output_id,
                   dbo.SIS_fn_ManualStepUnitPrice(mo.article_id, mo.division_id),
                   mo.qty, 0, 0, 0,
                   0, 0,
                   NULL, mo.resource_id, NULL,
                   SYSDATETIME(), @UserId
            FROM manual_outputs mo
            INNER JOIN @ManualIds mi ON mi.manual_output_id = mo.manual_output_id
            WHERE mo.deleted_at IS NULL AND mo.lock_id IS NULL;

            SET @ManualLockedCount = @@ROWCOUNT;

            UPDATE mo
            SET mo.lock_id = @NewLockId
            FROM manual_outputs mo
            INNER JOIN @ManualIds mi ON mi.manual_output_id = mo.manual_output_id
            WHERE mo.deleted_at IS NULL AND mo.lock_id IS NULL;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH

        -- LockedCount tetap berarti "jumlah baris log" supaya pemanggil lama tidak berubah
        -- artinya; jumlah baris manual datang di kolom BARU di sebelahnya.
        SELECT @NewLockId AS NewLockId, @LockedCount AS LockedCount,
               @ManualLockedCount AS ManualLockedCount;
    END
    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO

-- Prompt 55 -- verifikasi lock + periode gajian. DIJALANKAN MANUAL, seluruhnya di dalam
-- satu transaksi yang di-ROLLBACK di akhir -- tidak ada perubahan yang tertinggal di DB.
--
-- Cara baca hasil: tiap uji mencetak baris 'OK: ...' atau 'GAGAL: ...'. Uji yang datanya
-- tidak tersedia di DB ini mencetak 'LEWAT: ...' (bukan kegagalan) -- uji 2..8 butuh baris
-- log hidup yang belum di-lock dengan bentuk tertentu.
--
-- CATATAN: RAISERROR severity 16 di dalam SP TMOS terjadi SEBELUM BEGIN TRAN masing-masing,
-- jadi ditangkap TRY/CATCH di sini tanpa membatalkan transaksi luar. Jangan menambah uji yang
-- memicu error DI DALAM transaksi internal SP -- ROLLBACK di CATCH SP akan ikut membatalkan
-- transaksi luar script ini.
--
-- Prasyarat: sql/alter_55_workflow_lock.sql, sql/fn_55_workflow_saldo.sql,
-- sql/sp_PayrollPeriod_Manage.sql, sql/sp_WorkflowLock_Manage.sql,
-- sql/sp_UnlockRequest_Manage.sql, dan SP yang diubah (WorkflowLog/Bundle/SuperAdmin).

SET NOCOUNT ON;

DECLARE @Err NVARCHAR(2000);
DECLARE @AdminUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);

BEGIN TRAN;

-- =====================================================================
-- 1. Periode gajian 2026/2027
-- =====================================================================
PRINT '--- Uji 1: periode gajian ---';

EXEC SIS_PayrollPeriod_Manage @Action = 'GENERATE_YEAR', @Year = 2026, @UserId = @AdminUserId;
EXEC SIS_PayrollPeriod_Manage @Action = 'GENERATE_YEAR', @Year = 2027, @UserId = @AdminUserId;

IF (SELECT COUNT(*) FROM payroll_periods WHERE period_year = 2026 AND deleted_at IS NULL) = 52
    PRINT 'OK: 2026 punya 52 periode.';
ELSE
    PRINT 'GAGAL: jumlah periode 2026 bukan 52.';

-- Format period_code: 'YY-wNN' (lihat sql/alter_payroll_period_code_format.sql) -- dulu
-- '2026-P01'. Kode di bawah SENGAJA literal, bukan dihitung ulang dari period_year/period_no,
-- supaya tes ini ikut menjaga formatnya tidak berubah diam-diam.
IF EXISTS (SELECT 1 FROM payroll_periods WHERE period_code = '26-w01' AND deleted_at IS NULL
           AND period_start = '2025-12-27T10:00:00' AND period_end = '2026-01-03T10:00:00')
    PRINT 'OK: 26-w01 = 27 Des 2025 10:00 -> 3 Jan 2026 10:00.';
ELSE
    PRINT 'GAGAL: rentang/kode 26-w01 salah.';

IF EXISTS (SELECT 1 FROM payroll_periods WHERE period_code = '26-w40' AND deleted_at IS NULL
           AND period_start = '2026-09-26T10:00:00' AND period_end = '2026-10-03T10:00:00')
    PRINT 'OK: 26-w40 = 26 Sep 2026 10:00 -> 3 Okt 2026 10:00.';
ELSE
    PRINT 'GAGAL: rentang/kode 26-w40 salah.';

IF EXISTS (SELECT 1 FROM payroll_periods WHERE period_code = '26-w52' AND deleted_at IS NULL
           AND period_start = '2026-12-19T10:00:00' AND period_end = '2026-12-26T10:00:00')
    PRINT 'OK: 26-w52 = 19 Des -> 26 Des 2026 10:00.';
ELSE
    PRINT 'GAGAL: rentang/kode 26-w52 salah.';

IF (SELECT period_code FROM payroll_periods WHERE payroll_period_id = dbo.SIS_fn_PayrollPeriodIdAt('2026-12-26T11:00:00')) = '27-w01'
    PRINT 'OK: log 26 Des 2026 jam 11:00 jatuh ke 27-w01.';
ELSE
    PRINT 'GAGAL: SIS_fn_PayrollPeriodIdAt(2026-12-26 11:00) bukan 27-w01.';

IF NOT EXISTS (
    SELECT 1
    FROM payroll_periods pp
    CROSS APPLY (
        SELECT TOP 1 p2.period_end
        FROM payroll_periods p2
        WHERE p2.deleted_at IS NULL AND p2.period_end <= pp.period_start
        ORDER BY p2.period_end DESC
    ) prev
    WHERE pp.deleted_at IS NULL AND prev.period_end <> pp.period_start
)
    PRINT 'OK: tidak ada celah/tumpang tindih antar periode.';
ELSE
    PRINT 'GAGAL: ada celah atau tumpang tindih antar periode.';

-- =====================================================================
-- Cari data uji: 2 baris log hidup, belum di-lock, satu divisi yang sama,
-- yang punya resource hidup di divisi itu.
--
-- Kolom BisaUjiTerima menandai baris yang BISA dipakai uji 4 (RECEIVE lalu UNRECEIVE):
-- belum diterima, punya tujuan serah, divisi tujuannya punya resource hidup, project-nya
-- tidak terkunci (Prompt 18), dan -- untuk baris ber-bundle -- belum ada hasil di step
-- setelahnya (guard UNRECEIVE). Divisi & @LogId1 dipilih dengan MENGUTAMAKAN baris seperti
-- itu supaya uji 4 benar-benar jalan, bukan 'LEWAT'. Kalau memang tidak ada di DB ini,
-- pemilihan jatuh balik ke baris apa pun dan uji 4 tetap 'LEWAT' (bukan kegagalan).
-- =====================================================================
DECLARE @DivisionId INT, @ResourceId INT, @LogId1 INT, @LogId2 INT, @PeriodId INT;

IF OBJECT_ID('tempdb..#kandidat') IS NOT NULL DROP TABLE #kandidat;

SELECT awl.workflow_log_id, awl.division_id,
       CAST(CASE WHEN awl.received_at IS NULL
                  AND awl.target_division_id IS NOT NULL
                  AND p.manual_status IS NULL
                  AND EXISTS (SELECT 1 FROM resources rt
                              WHERE rt.division_id = awl.target_division_id AND rt.deleted_at IS NULL)
                  AND NOT EXISTS (SELECT 1
                                  FROM article_workflow_logs awl2
                                  INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
                                  WHERE awl2.bundle_id = awl.bundle_id AND awl.bundle_id IS NOT NULL
                                    AND awl2.deleted_at IS NULL
                                    AND aw2.article_id = aw.article_id AND aw2.sort_order > aw.sort_order)
             THEN 1 ELSE 0 END AS TINYINT) AS BisaUjiTerima
INTO #kandidat
FROM article_workflow_logs awl
INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
INNER JOIN articles a ON a.article_id = aw.article_id
INNER JOIN projects p ON p.project_id = a.project_id
WHERE awl.deleted_at IS NULL AND awl.lock_id IS NULL
  AND EXISTS (SELECT 1 FROM resources r WHERE r.division_id = awl.division_id AND r.deleted_at IS NULL);

SELECT TOP 1 @DivisionId = division_id
FROM #kandidat
GROUP BY division_id
HAVING COUNT(*) >= 2
ORDER BY MAX(BisaUjiTerima) DESC, COUNT(*) DESC;

SELECT TOP 1 @ResourceId = resource_id FROM resources WHERE division_id = @DivisionId AND deleted_at IS NULL ORDER BY resource_id;

SELECT TOP 1 @LogId1 = workflow_log_id FROM #kandidat
WHERE division_id = @DivisionId
ORDER BY BisaUjiTerima DESC, workflow_log_id DESC;

SELECT TOP 1 @LogId2 = workflow_log_id FROM #kandidat
WHERE division_id = @DivisionId AND workflow_log_id <> @LogId1
ORDER BY BisaUjiTerima DESC, workflow_log_id DESC;

SET @PeriodId = dbo.SIS_fn_PayrollPeriodIdAt(SYSDATETIME());

IF @LogId2 IS NULL OR @PeriodId IS NULL
BEGIN
    PRINT 'LEWAT: uji 2..8 butuh 2 baris log hidup belum di-lock di satu divisi + periode berjalan sudah di-generate.';
END
ELSE
BEGIN
    -- =================================================================
    -- 2. LOCK 2 baris
    -- =================================================================
    PRINT '--- Uji 2: LOCK 2 baris ---';

    DECLARE @Csv VARCHAR(100) = CAST(@LogId1 AS VARCHAR(20)) + ',' + CAST(@LogId2 AS VARCHAR(20));
    DECLARE @LockId INT;

    EXEC SIS_WorkflowLock_Manage @Action = 'LOCK', @WorkflowLogIds = @Csv, @DivisionId = @DivisionId,
         @StationId = NULL, @ResourceId = @ResourceId, @PayrollPeriodId = @PeriodId, @UserId = @AdminUserId;

    SELECT @LockId = lock_id FROM article_workflow_logs WHERE workflow_log_id = @LogId1;

    IF @LockId IS NOT NULL
       AND (SELECT lock_id FROM article_workflow_logs WHERE workflow_log_id = @LogId2) = @LockId
       AND (SELECT COUNT(*) FROM workflow_lock_items WHERE lock_id = @LockId) = 2
        PRINT 'OK: kedua baris terkunci oleh satu lock, 2 item dibuat.';
    ELSE
        PRINT 'GAGAL: lock_id / jumlah item tidak sesuai.';

    IF NOT EXISTS (
        SELECT 1 FROM workflow_lock_items wli
        INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = wli.workflow_log_id
        WHERE wli.lock_id = @LockId
          AND (wli.snap_qty_ok <> awl.qty_ok OR wli.snap_qty_reject_print <> awl.qty_reject_print
               OR wli.snap_qty_reject_fabric <> awl.qty_reject_fabric OR wli.snap_qty_reject_sewing <> awl.qty_reject_sewing
               OR wli.snap_qty_reject_rework <> awl.qty_reject_rework OR wli.snap_qty_lost <> awl.qty_lost
               OR ISNULL(wli.snap_article_size_id, -1) <> ISNULL(awl.article_size_id, -1)
               OR ISNULL(wli.snap_resource_id, -1) <> ISNULL(awl.resource_id, -1)
               OR ISNULL(wli.snap_target_division_id, -1) <> ISNULL(awl.target_division_id, -1))
    )
        PRINT 'OK: snapshot item sama dengan nilai baris.';
    ELSE
        PRINT 'GAGAL: snapshot item tidak cocok dengan baris log.';

    -- =================================================================
    -- 3. UPDATE / DELETE / CANCEL_HANDOVER baris terkunci -> LOCKED|
    -- =================================================================
    PRINT '--- Uji 3: mutasi baris terkunci ditolak ---';

    SET @Err = NULL;
    BEGIN TRY
        EXEC SIS_WorkflowLog_Manage @Action = 'UPDATE', @Id = @LogId1, @QtyOk = 1, @UserId = @AdminUserId;
    END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH
    IF @Err LIKE 'LOCKED|%' PRINT 'OK: UPDATE ditolak LOCKED|.' ELSE PRINT 'GAGAL: UPDATE tidak menolak dengan LOCKED| (' + ISNULL(@Err, '<tanpa error>') + ')';

    SET @Err = NULL;
    BEGIN TRY
        EXEC SIS_WorkflowLog_Manage @Action = 'DELETE', @Id = @LogId1, @DeleteReason = 'uji', @UserId = @AdminUserId;
    END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH
    IF @Err LIKE 'LOCKED|%' PRINT 'OK: DELETE ditolak LOCKED|.' ELSE PRINT 'GAGAL: DELETE tidak menolak dengan LOCKED| (' + ISNULL(@Err, '<tanpa error>') + ')';

    SET @Err = NULL;
    BEGIN TRY
        EXEC SIS_WorkflowLog_Manage @Action = 'CANCEL_HANDOVER', @Id = @LogId1, @UserId = @AdminUserId;
    END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH
    IF @Err LIKE 'LOCKED|%' PRINT 'OK: CANCEL_HANDOVER ditolak LOCKED|.' ELSE PRINT 'GAGAL: CANCEL_HANDOVER tidak menolak dengan LOCKED| (' + ISNULL(@Err, '<tanpa error>') + ')';

    -- Super Admin juga tidak punya jalan pintas.
    SET @Err = NULL;
    BEGIN TRY
        EXEC SIS_SuperAdmin_Manage @Action = 'LOG_DELETE', @WorkflowLogId = @LogId1, @DeleteReason = 'uji', @UserId = @AdminUserId;
    END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH
    IF @Err LIKE 'LOCKED|%' PRINT 'OK: SuperAdmin LOG_DELETE ditolak LOCKED|.' ELSE PRINT 'GAGAL: SuperAdmin LOG_DELETE tidak menolak dengan LOCKED| (' + ISNULL(@Err, '<tanpa error>') + ')';

    -- =================================================================
    -- 4. RECEIVE / UNRECEIVE baris terkunci -> tetap boleh
    -- =================================================================
    PRINT '--- Uji 4: RECEIVE/UNRECEIVE baris terkunci tetap jalan ---';

    -- Cari baris terkunci yang punya tujuan serah & belum diterima, kalau ada.
    DECLARE @RecId INT, @RecTargetDivisionId INT, @RecResourceId INT;
    SELECT TOP 1 @RecId = awl.workflow_log_id, @RecTargetDivisionId = awl.target_division_id
    FROM article_workflow_logs awl
    WHERE awl.lock_id = @LockId AND awl.target_division_id IS NOT NULL AND awl.received_at IS NULL AND awl.deleted_at IS NULL;

    IF @RecId IS NULL
        PRINT 'LEWAT: tidak ada baris terkunci yang belum diterima & punya tujuan serah.';
    ELSE
    BEGIN
        SELECT TOP 1 @RecResourceId = resource_id FROM resources WHERE division_id = @RecTargetDivisionId AND deleted_at IS NULL;

        SET @Err = NULL;
        BEGIN TRY
            EXEC SIS_WorkflowLog_Manage @Action = 'RECEIVE', @Id = @RecId, @ReceivedByResourceId = @RecResourceId, @UserId = @AdminUserId;
        END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH

        IF @Err IS NULL AND (SELECT received_at FROM article_workflow_logs WHERE workflow_log_id = @RecId) IS NOT NULL
            PRINT 'OK: RECEIVE baris terkunci berhasil.';
        ELSE
            PRINT 'GAGAL: RECEIVE baris terkunci ditolak (' + ISNULL(@Err, '<received_at tetap NULL>') + ')';

        SET @Err = NULL;
        BEGIN TRY
            EXEC SIS_WorkflowLog_Manage @Action = 'UNRECEIVE', @Id = @RecId, @UpdatedByResourceId = @RecResourceId, @UserId = @AdminUserId;
        END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH

        IF @Err IS NULL AND (SELECT received_at FROM article_workflow_logs WHERE workflow_log_id = @RecId) IS NULL
            PRINT 'OK: UNRECEIVE baris terkunci berhasil.';
        ELSE
            PRINT 'GAGAL: UNRECEIVE baris terkunci ditolak (' + ISNULL(@Err, '<received_at masih terisi>') + ')';
    END

    -- =================================================================
    -- 7. CREATE request -> APPROVE -> baris bebas lagi -> LOCK ulang
    -- =================================================================
    PRINT '--- Uji 7: request unlock -> approve -> lock ulang ---';

    -- SENGAJA tidak memakai INSERT ... EXEC (SP ini mengubah state transaksi di dalamnya) --
    -- request_id diambil dari tabel setelah pemanggilan.
    DECLARE @RequestId INT;
    DECLARE @Csv1 VARCHAR(20) = CAST(@LogId1 AS VARCHAR(20));

    EXEC SIS_UnlockRequest_Manage @Action = 'CREATE', @WorkflowLogIds = @Csv1,
         @Reason = 'Salah input qty, perlu koreksi', @DivisionId = @DivisionId,
         @StationId = NULL, @ResourceId = @ResourceId, @UserId = @AdminUserId;

    SELECT TOP 1 @RequestId = uri.request_id
    FROM unlock_request_items uri
    INNER JOIN unlock_requests ur ON ur.request_id = uri.request_id
    WHERE uri.workflow_log_id = @LogId1
      AND ur.approved_at IS NULL AND ur.rejected_at IS NULL AND ur.deleted_at IS NULL
    ORDER BY uri.request_id DESC;

    IF @RequestId IS NULL
        PRINT 'GAGAL: request unlock tidak terbentuk.';
    ELSE
    BEGIN
        -- =============================================================
        -- 8. Request kedua untuk baris yang sama -> ditolak
        -- =============================================================
        SET @Err = NULL;
        BEGIN TRY
            EXEC SIS_UnlockRequest_Manage @Action = 'CREATE', @WorkflowLogIds = @Csv1,
                 @Reason = 'Pengajuan kedua', @DivisionId = @DivisionId,
                 @StationId = NULL, @ResourceId = @ResourceId, @UserId = @AdminUserId;
        END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH
        IF @Err LIKE '%menunggu approval%' PRINT 'OK (uji 8): request kedua ditolak.' ELSE PRINT 'GAGAL (uji 8): request kedua tidak ditolak (' + ISNULL(@Err, '<tanpa error>') + ')';

        DECLARE @OldLockItemId INT = (SELECT lock_item_id FROM unlock_request_items WHERE request_id = @RequestId);

        EXEC SIS_UnlockRequest_Manage @Action = 'APPROVE', @Id = @RequestId, @UserId = @AdminUserId;

        IF (SELECT lock_id FROM article_workflow_logs WHERE workflow_log_id = @LogId1) IS NULL
           AND (SELECT released_at FROM workflow_lock_items WHERE lock_item_id = @OldLockItemId) IS NOT NULL
           AND (SELECT released_by_request_id FROM workflow_lock_items WHERE lock_item_id = @OldLockItemId) = @RequestId
            PRINT 'OK: APPROVE mengosongkan lock_id dan menandai item lama released.';
        ELSE
            PRINT 'GAGAL: APPROVE tidak melepas lock dengan benar.';

        -- Baris kini bisa dikunci ulang -> item BARU, item lama tetap tersimpan.
        EXEC SIS_WorkflowLock_Manage @Action = 'LOCK', @WorkflowLogIds = @Csv1, @DivisionId = @DivisionId,
             @StationId = NULL, @ResourceId = @ResourceId, @PayrollPeriodId = @PeriodId, @UserId = @AdminUserId;

        IF (SELECT COUNT(*) FROM workflow_lock_items WHERE workflow_log_id = @LogId1) >= 2
           AND (SELECT COUNT(*) FROM workflow_lock_items WHERE workflow_log_id = @LogId1 AND released_at IS NULL) = 1
            PRINT 'OK: lock ulang membuat item baru, item lama tetap tersimpan.';
        ELSE
            PRINT 'GAGAL: lock ulang tidak menghasilkan satu item aktif + riwayat.';
    END
END

-- =====================================================================
-- 5. UPDATE baris BELUM lock yang SUDAH diterima -> berhasil (dulu ditolak)
-- =====================================================================
PRINT '--- Uji 5: UPDATE baris sudah diterima, belum di-lock ---';

DECLARE @U5Id INT, @U5QtyOk INT, @U5SizeId INT;
SELECT TOP 1 @U5Id = awl.workflow_log_id, @U5QtyOk = awl.qty_ok, @U5SizeId = awl.article_size_id
FROM article_workflow_logs awl
INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
WHERE awl.deleted_at IS NULL AND awl.lock_id IS NULL AND awl.received_at IS NOT NULL
  AND awl.log_type = 'NORMAL' AND aw.is_bundling = 0 AND awl.qty_ok > 0
  -- Tidak ada pemakaian hilir -> naikkan/turunkan qty tidak kena guard saldo.
  AND dbo.SIS_fn_BundleNextStepTotal(awl.article_workflow_id, awl.bundle_id) = 0
ORDER BY awl.workflow_log_id DESC;

IF @U5Id IS NULL
    PRINT 'LEWAT: tidak ada baris hidup, belum di-lock, sudah diterima, tanpa pemakaian step berikutnya.';
ELSE
BEGIN
    SET @Err = NULL;
    BEGIN TRY
        EXEC SIS_WorkflowLog_Manage @Action = 'UPDATE', @Id = @U5Id, @ArticleSizeId = @U5SizeId,
             @QtyOk = @U5QtyOk, @Remark = 'uji prompt 55', @ConfirmExceed = 1, @ConfirmShort = 1, @UserId = @AdminUserId;
    END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH

    IF @Err IS NULL AND (SELECT remark FROM article_workflow_logs WHERE workflow_log_id = @U5Id) = 'uji prompt 55'
        PRINT 'OK: baris yang sudah diterima bisa direvisi selama belum di-lock.';
    ELSE
        PRINT 'GAGAL: UPDATE baris sudah diterima ditolak (' + ISNULL(@Err, '<remark tidak berubah>') + ')';
END

-- =====================================================================
-- 6. Turunkan qty_ok ber-bundle di bawah total step berikutnya -> ditolak;
--    naikkan -> berhasil.
-- =====================================================================
PRINT '--- Uji 6: guard saldo baris ber-bundle ---';

DECLARE @U6Id INT, @U6QtyOk INT, @U6Next INT;
SELECT TOP 1 @U6Id = awl.workflow_log_id, @U6QtyOk = awl.qty_ok,
             @U6Next = dbo.SIS_fn_BundleNextStepTotal(awl.article_workflow_id, awl.bundle_id)
FROM article_workflow_logs awl
WHERE awl.deleted_at IS NULL AND awl.lock_id IS NULL AND awl.bundle_id IS NOT NULL
  AND awl.log_type = 'NORMAL'
  AND dbo.SIS_fn_BundleNextStepTotal(awl.article_workflow_id, awl.bundle_id) > 0
  AND awl.qty_ok >= dbo.SIS_fn_BundleNextStepTotal(awl.article_workflow_id, awl.bundle_id)
  -- Baris tunggal di step+bundle-nya, supaya hitungan saldo di uji ini gamblang.
  AND NOT EXISTS (
      SELECT 1 FROM article_workflow_logs x
      WHERE x.article_workflow_id = awl.article_workflow_id AND x.bundle_id = awl.bundle_id
        AND x.deleted_at IS NULL AND x.workflow_log_id <> awl.workflow_log_id)
ORDER BY awl.workflow_log_id DESC;

IF @U6Id IS NULL
    PRINT 'LEWAT: tidak ada baris ber-bundle (belum di-lock) yang step berikutnya sudah terpakai.';
ELSE
BEGIN
    DECLARE @U6Turun INT = @U6Next - 1;

    SET @Err = NULL;
    BEGIN TRY
        EXEC SIS_WorkflowLog_Manage @Action = 'UPDATE', @Id = @U6Id, @QtyOk = @U6Turun,
             @ConfirmExceed = 1, @ConfirmShort = 1, @UserId = @AdminUserId;
    END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH
    IF @Err LIKE 'Perubahan membuat saldo minus%' PRINT 'OK: penurunan qty di bawah total step berikutnya ditolak.'
    ELSE PRINT 'GAGAL: penurunan qty tidak ditolak guard saldo (' + ISNULL(@Err, '<tanpa error>') + ')';

    DECLARE @U6Naik INT = @U6QtyOk + 1;
    SET @Err = NULL;
    BEGIN TRY
        EXEC SIS_WorkflowLog_Manage @Action = 'UPDATE', @Id = @U6Id, @QtyOk = @U6Naik,
             @ConfirmExceed = 1, @ConfirmShort = 1, @UserId = @AdminUserId;
    END TRY BEGIN CATCH SET @Err = ERROR_MESSAGE(); END CATCH
    IF @Err IS NULL AND (SELECT qty_ok FROM article_workflow_logs WHERE workflow_log_id = @U6Id) = @U6Naik
        PRINT 'OK: kenaikan qty lolos guard saldo.';
    ELSE
        PRINT 'GAGAL: kenaikan qty ditolak (' + ISNULL(@Err, '<qty_ok tidak berubah>') + ')';
END

ROLLBACK TRAN;

IF OBJECT_ID('tempdb..#kandidat') IS NOT NULL DROP TABLE #kandidat;
PRINT '--- Selesai, semua perubahan di-ROLLBACK. ---';

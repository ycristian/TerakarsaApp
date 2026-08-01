-- Prompt 39: pemisahan resource Buang Benang per line + migrasi data lama.
-- Dijalankan manual SETELAH sql/alter_39_resource_counterpart.sql dan setelah SP terkait
-- (sp_Resource_Manage.sql, sp_Resource_Select.sql, sp_WorkflowLog_Manage.sql,
-- sp_Bundle_ScanInfo.sql) sudah di-deploy.
--
-- Idempotent: dijalankan ulang aman (0 baris berubah) -- tiap section memakai guard
-- (NOT EXISTS / filter nilai belum sesuai / filter IN @OldTrimIds yang otomatis kosong
-- begitu migrasi log selesai). Satu transaksi, auto-rollback bila error, mencetak laporan
-- ringkas di akhir.
--
-- Tidak ada ID yang di-hardcode -- semua resource/divisi dicari lewat nama (@TrimDivisionName/
-- @LinePrefix/@TrimPrefix di bawah).

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN;

    -- ===================== 1. Variabel konfigurasi =====================
    DECLARE @TrimDivisionName VARCHAR(150) = 'Buang Benang';
    DECLARE @LinePrefix       VARCHAR(30)  = 'Line ';
    DECLARE @TrimPrefix       VARCHAR(30)  = 'Trim ';
    DECLARE @UserId           INT          = 1;

    DECLARE @TrimDivisionId INT;
    SELECT @TrimDivisionId = division_id FROM divisions
    WHERE division_name = @TrimDivisionName AND deleted_at IS NULL;

    IF @TrimDivisionId IS NULL
    BEGIN
        RAISERROR('Divisi "%s" tidak ditemukan.', 16, 1, @TrimDivisionName);
        RETURN;
    END

    -- ===================== 2. Kumpulkan line sumber =====================
    DECLARE @Lines TABLE (
        LineResourceId   INT PRIMARY KEY,
        LineName         VARCHAR(150),
        TrimName         VARCHAR(150),
        ResourceTypeId   INT,
        LineDivisionId   INT
    );

    INSERT INTO @Lines (LineResourceId, LineName, TrimName, ResourceTypeId, LineDivisionId)
    SELECT resource_id, resource_name,
           @TrimPrefix + SUBSTRING(resource_name, LEN(@LinePrefix) + 1, LEN(resource_name)),
           resource_type_id, division_id
    FROM resources
    WHERE deleted_at IS NULL AND is_active = 1
      AND resource_name LIKE @LinePrefix + '%'
      AND division_id <> @TrimDivisionId;

    IF NOT EXISTS (SELECT 1 FROM @Lines)
        PRINT 'PERINGATAN: tidak ada resource line ("' + @LinePrefix + '%") ditemukan -- cek @LinePrefix.';

    -- ===================== 3. Insert resource trim yang belum ada =====================
    INSERT INTO resources (division_id, resource_type_id, resource_name, is_active, created_at, created_by)
    SELECT @TrimDivisionId, l.ResourceTypeId, l.TrimName, 1, SYSDATETIME(), @UserId
    FROM @Lines l
    WHERE NOT EXISTS (
        SELECT 1 FROM resources r
        WHERE r.division_id = @TrimDivisionId AND r.resource_name = l.TrimName AND r.deleted_at IS NULL
    );

    DECLARE @TrimResourcesCreated INT = @@ROWCOUNT;

    -- ===================== 4. Isi counterpart (line -> trim, satu arah) =====================
    UPDATE line
    SET line.counterpart_resource_id = trim_r.resource_id,
        line.updated_at = SYSDATETIME(),
        line.updated_by = @UserId
    FROM resources line
    INNER JOIN @Lines l ON l.LineResourceId = line.resource_id
    INNER JOIN resources trim_r ON trim_r.division_id = @TrimDivisionId
        AND trim_r.resource_name = l.TrimName AND trim_r.deleted_at IS NULL
    WHERE line.counterpart_resource_id IS NULL OR line.counterpart_resource_id <> trim_r.resource_id;

    DECLARE @CounterpartsSet INT = @@ROWCOUNT;

    -- ===================== 5. Identifikasi resource trim lama =====================
    DECLARE @OldTrimIds TABLE (ResourceId INT PRIMARY KEY, ResourceName VARCHAR(150));

    INSERT INTO @OldTrimIds (ResourceId, ResourceName)
    SELECT resource_id, resource_name
    FROM resources
    WHERE division_id = @TrimDivisionId AND deleted_at IS NULL
      AND resource_name NOT IN (SELECT TrimName FROM @Lines);

    -- ===================== 6. Migrasi log (resource_id / received_by / updated_by) =====================
    -- Baris soft-deleted IKUT dimigrasi (riwayat konsisten). Hanya kolom yang nilainya ada
    -- di @OldTrimIds yang diganti -- kolom lain pada baris yang sama tidak disentuh. Filter
    -- selalu "IN @OldTrimIds" sehingga aman dijalankan berulang (run kedua: nilai sudah jadi
    -- resource trim baru, tidak lagi match @OldTrimIds).
    UPDATE awl
    SET resource_id = CASE WHEN awl.resource_id IN (SELECT ResourceId FROM @OldTrimIds)
                            THEN ln.counterpart_resource_id ELSE awl.resource_id END,
        received_by_resource_id = CASE WHEN awl.received_by_resource_id IN (SELECT ResourceId FROM @OldTrimIds)
                            THEN ln.counterpart_resource_id ELSE awl.received_by_resource_id END,
        updated_by_resource_id = CASE WHEN awl.updated_by_resource_id IN (SELECT ResourceId FROM @OldTrimIds)
                            THEN ln.counterpart_resource_id ELSE awl.updated_by_resource_id END
    FROM article_workflow_logs awl
    INNER JOIN bundles b ON b.bundle_id = awl.bundle_id
    INNER JOIN resources ln ON ln.resource_id = b.resource_id AND ln.counterpart_resource_id IS NOT NULL
    WHERE awl.resource_id IN (SELECT ResourceId FROM @OldTrimIds)
       OR awl.received_by_resource_id IN (SELECT ResourceId FROM @OldTrimIds)
       OR awl.updated_by_resource_id IN (SELECT ResourceId FROM @OldTrimIds);

    DECLARE @LogRowsMigrated INT = @@ROWCOUNT;

    -- ===================== 7. Laporan sisa tidak termapping =====================
    DECLARE @Leftover TABLE (
        WorkflowLogId INT, BundleId INT NULL, BundleNo INT NULL, Serial VARCHAR(50) NULL, Reason VARCHAR(100)
    );

    INSERT INTO @Leftover (WorkflowLogId, BundleId, BundleNo, Serial, Reason)
    SELECT awl.workflow_log_id, awl.bundle_id, b.bundle_no, b.serial,
        CASE
            WHEN awl.bundle_id IS NULL THEN 'Bundle NULL (step non-bundle)'
            WHEN b.resource_id IS NULL THEN 'Bundle tanpa resource_id (line)'
            WHEN ln.counterpart_resource_id IS NULL THEN 'Line tanpa counterpart'
            ELSE 'Lainnya'
        END
    FROM article_workflow_logs awl
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN resources ln ON ln.resource_id = b.resource_id
    WHERE awl.resource_id IN (SELECT ResourceId FROM @OldTrimIds)
       OR awl.received_by_resource_id IN (SELECT ResourceId FROM @OldTrimIds)
       OR awl.updated_by_resource_id IN (SELECT ResourceId FROM @OldTrimIds);

    -- ===================== 8. Nonaktifkan resource trim lama =====================
    UPDATE resources
    SET is_active = 0, updated_at = SYSDATETIME(), updated_by = @UserId
    WHERE resource_id IN (SELECT ResourceId FROM @OldTrimIds) AND is_active = 1;

    DECLARE @OldTrimsDeactivated INT = @@ROWCOUNT;

    -- ===================== 9. Reset station divisi Buang Benang =====================
    UPDATE stations
    SET default_resource_id = NULL, allow_resource_change = 1,
        updated_at = SYSDATETIME(), updated_by = @UserId
    WHERE division_id = @TrimDivisionId AND deleted_at IS NULL
      AND (default_resource_id IS NOT NULL OR allow_resource_change = 0);

    DECLARE @StationsReset INT = @@ROWCOUNT;

    -- ===================== Ringkasan =====================
    -- Fix: PRINT tidak menerima subquery langsung di ekspresinya ("Subqueries are not
    -- allowed in this context") -- tampung dulu ke variabel.
    DECLARE @OldTrimCount INT = (SELECT COUNT(*) FROM @OldTrimIds);
    DECLARE @LeftoverCount INT = (SELECT COUNT(*) FROM @Leftover);

    PRINT 'Divisi Buang Benang: division_id = ' + CAST(@TrimDivisionId AS VARCHAR(10));
    PRINT 'Resource trim baru dibuat: ' + CAST(@TrimResourcesCreated AS VARCHAR(10));
    PRINT 'Counterpart (line -> trim) di-set/update: ' + CAST(@CounterpartsSet AS VARCHAR(10));
    PRINT 'Resource trim lama teridentifikasi: ' + CAST(@OldTrimCount AS VARCHAR(10));
    PRINT 'Baris article_workflow_logs dimigrasi: ' + CAST(@LogRowsMigrated AS VARCHAR(10));
    PRINT 'Sisa baris TIDAK termapping (lihat SELECT laporan di bawah): ' + CAST(@LeftoverCount AS VARCHAR(10));
    PRINT 'Resource trim lama dinonaktifkan: ' + CAST(@OldTrimsDeactivated AS VARCHAR(10));
    PRINT 'Station Buang Benang direset (default_resource_id NULL, allow_resource_change 1): ' + CAST(@StationsReset AS VARCHAR(10));

    -- 7a: ringkasan jumlah sisa tidak termapping per alasan.
    SELECT Reason, COUNT(*) AS JumlahBaris FROM @Leftover GROUP BY Reason;

    -- 7b: daftar detail baris sisa tidak termapping.
    SELECT WorkflowLogId, BundleId, BundleNo, Serial, Reason FROM @Leftover ORDER BY WorkflowLogId;

    COMMIT TRAN;
    PRINT 'Migrasi Prompt 39 selesai & di-COMMIT.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'Migrasi GAGAL, seluruh perubahan di-ROLLBACK. Detail error:';
    THROW;
END CATCH
GO

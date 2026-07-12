-- Mutasi data bundles (CREATE/UPDATE/DELETE) + cetak ulang label (SIS_Bundle_ReprintLabel).
-- Pengambilan data ada di sp_Bundle_Select.sql.
-- Bundle dibuat manual per baris oleh supervisor (privilege PROJECT/ORDER_PROJECT).
-- Aturan:
--   1. article_size harus milik article yang sama dan hidup; qty > 0.
--   2. Serial digenerate di sini, format B{yy}-{nomor urut global 6 digit} (mis. B26-000153).
--      Nomor urut TIDAK reset per tahun (murni global), aman dari race condition lewat
--      sp_getapplock (exclusive, scoped ke transaksi) sebelum menghitung MAX nomor berjalan.
--   3. CREATE otomatis membuat baris print_jobs (job_type BUNDLE_LABEL, ref_id = bundle baru).
--      Payload berisi qr_content = @PublicBaseUrl + '/b/' + serial. @PublicBaseUrl dibaca dari
--      appsettings.json (App:PublicBaseUrl) di layer API dan dikirim sebagai parameter --
--      serial baru diketahui hanya di dalam transaksi ini (sp_getapplock), jadi qr_content
--      lengkap dirakit di sini, bukan di API.
--   4. UPDATE/DELETE ditolak bila bundle sudah punya log hidup di step station (is_bundling =
--      0, artinya sudah disentuh divisi produksi) ATAU log Bundling-nya sudah received_at
--      terisi (sudah diserah-terimakan ke divisi berikutnya) -- selama belum, supervisor masih
--      bisa ganti line/qty/hapus bundle. Perbaikan Prompt 17: pengecekan lama memakai kolom
--      [status] = 'COMPLETED' yang sudah dihapus sejak Prompt 12b (bug, selalu gagal).
--   5. Serial tidak pernah berubah setelah dibuat.
--   6. bundle_no = nomor urut pendek per project (1, 2, 3, ...), naik terus lintas artikel
--      sampai project selesai, dihitung atas SEMUA bundle project ini (termasuk yang
--      soft-deleted) supaya nomor tidak pernah dipakai ulang. Digenerate di sini, di dalam
--      applock yang sama dengan serial (bundle_serial_seq) -- project tidak punya sequence
--      sendiri, jadi cukup satu lock global untuk keduanya.
--   7. Prompt 17: CREATE membuat juga baris article_workflow_logs untuk step Bunding implisit
--      artikel ini (bundle_id = bundle baru, qty_ok = qty bundle, received_at NULL) dan
--      auto-receive semua log non-bundle (mis. Cutting) yang masih pending -- lihat detail di
--      badan procedure. @BundlingResourceId (opsional) = pelaksana yang mengemas bundle ini;
--      UPDATE menyinkronkan qty_ok/resource_id log tsb, DELETE ikut soft-delete log tsb.
--   8. Prompt 18: CREATE/UPDATE/DELETE ditolak kalau project artikel ini berstatus manual
--      (ON_HOLD/COMPLETED/CANCELLED) -- pesan RAISERROR menyertakan alasan bila ada.
--      SIS_Bundle_ReprintLabel TIDAK dikunci (cetak ulang label tetap boleh kapan pun).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Bundle_Manage
    @Action              VARCHAR(20),
    @Id                  INT = NULL,
    @ArticleId           INT = NULL,
    @ArticleSizeId       INT = NULL,
    @Qty                 INT = NULL,
    @ResourceId          INT = NULL,
    @ResourcePersonName  VARCHAR(150) = NULL,
    @PublicBaseUrl       VARCHAR(255) = NULL,
    @BundlingResourceId  INT = NULL,
    @UserId              INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        -- Prompt 18: project terkunci (manual_status) menolak pembuatan bundle.
        DECLARE @LockStatus_Create VARCHAR(20), @LockReason_Create VARCHAR(255);
        SELECT @LockStatus_Create = p.manual_status, @LockReason_Create = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @ArticleId;

        IF @LockStatus_Create IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Create VARCHAR(30) = CASE @LockStatus_Create
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Create END;
            DECLARE @LockSuffix_Create VARCHAR(300) = CASE WHEN @LockReason_Create IS NOT NULL AND LTRIM(RTRIM(@LockReason_Create)) <> ''
                THEN ' (Alasan: ' + @LockReason_Create + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Create, @LockSuffix_Create);
            RETURN;
        END

        IF @Qty IS NULL OR @Qty <= 0
        BEGIN
            RAISERROR('Qty bundle harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM article_sizes
            WHERE article_size_id = @ArticleSizeId AND article_id = @ArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Ukuran tidak ditemukan untuk artikel ini.', 16, 1);
            RETURN;
        END

        -- Prompt 17: step Bundling implisit artikel ini -- wajib ada (disisipkan otomatis
        -- oleh SIS_ArticleWorkflow_Manage APPLY/SAVE) sebelum bundle bisa dibuat.
        DECLARE @BundlingStepId INT, @BundlingDivisionId INT, @BundlingSortOrder INT;
        SELECT @BundlingStepId = article_workflow_id, @BundlingDivisionId = division_id, @BundlingSortOrder = sort_order
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

        IF @BundlingStepId IS NULL
        BEGIN
            RAISERROR('Workflow artikel belum memiliki step Bundling. Terapkan ulang/simpan workflow artikel terlebih dahulu.', 16, 1);
            RETURN;
        END

        IF @BundlingResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @BundlingResourceId AND division_id = @BundlingDivisionId AND is_active = 1 AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pelaksana bundling tidak valid.', 16, 1);
            RETURN;
        END

        DECLARE @BundlingTargetDivisionId INT;
        SELECT TOP 1 @BundlingTargetDivisionId = division_id
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order > @BundlingSortOrder
        ORDER BY sort_order ASC;

        BEGIN TRAN;
        BEGIN TRY
            DECLARE @LockResult INT;
            EXEC @LockResult = sp_getapplock
                @Resource = 'bundle_serial_seq',
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                RAISERROR('Gagal mengunci penomoran serial bundle. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            DECLARE @NextNumber INT;
            SELECT @NextNumber = ISNULL(MAX(CAST(RIGHT(serial, 6) AS INT)), 0) + 1
            FROM bundles;

            DECLARE @Yy VARCHAR(2) = RIGHT(CAST(YEAR(SYSDATETIME()) AS VARCHAR(4)), 2);
            DECLARE @NewSerial VARCHAR(20) = 'B' + @Yy + '-' + RIGHT('000000' + CAST(@NextNumber AS VARCHAR(6)), 6);

            DECLARE @ProjectId INT;
            SELECT @ProjectId = project_id FROM articles WHERE article_id = @ArticleId;

            DECLARE @NewBundleNo INT;
            SELECT @NewBundleNo = ISNULL(MAX(b.bundle_no), 0) + 1
            FROM bundles b
            INNER JOIN articles a ON a.article_id = b.article_id
            WHERE a.project_id = @ProjectId;

            DECLARE @NextSort INT;
            SELECT @NextSort = ISNULL(MAX(sort_order), 0) + 1
            FROM bundles
            WHERE article_size_id = @ArticleSizeId AND deleted_at IS NULL;

            INSERT INTO bundles (
                article_id, article_size_id, serial, bundle_no, qty, sort_order,
                resource_id, resource_person_name, created_at, created_by
            )
            VALUES (
                @ArticleId, @ArticleSizeId, @NewSerial, @NewBundleNo, @Qty, @NextSort,
                @ResourceId, @ResourcePersonName, SYSDATETIME(), @UserId
            );

            DECLARE @NewBundleId INT = CAST(SCOPE_IDENTITY() AS INT);
            DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/b/' + @NewSerial;

            DECLARE @Payload NVARCHAR(MAX) = (
                SELECT
                    @NewSerial AS serial,
                    @NewBundleNo AS bundle_no,
                    @QrContent AS qr_content,
                    p.project_name AS project_name,
                    a.article_name AS article_name,
                    a.style AS style,
                    a.color AS color,
                    spd.size_name AS size_name,
                    @Qty AS qty,
                    res.resource_name AS resource_name,
                    @ResourcePersonName AS resource_person_name
                FROM articles a
                INNER JOIN projects p ON p.project_id = a.project_id
                INNER JOIN article_sizes asz ON asz.article_size_id = @ArticleSizeId
                INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
                LEFT JOIN resources res ON res.resource_id = @ResourceId
                WHERE a.article_id = @ArticleId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
            VALUES ('BUNDLE_LABEL', @NewBundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

            DECLARE @NewPrintJobId INT = CAST(SCOPE_IDENTITY() AS INT);

            -- Prompt 17: catat kegiatan Bundling sebagai log workflow (menunggu diterima
            -- divisi berikutnya) + auto-receive log non-bundle (mis. Cutting) yang masih
            -- pending -- tanggung jawab akurasi qty tetap di divisi non-bundle, sistem
            -- tidak memblokir pembuatan bundle karena ini.
            INSERT INTO article_workflow_logs (
                article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
                qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing,
                remark, target_division_id, created_at, created_by
            )
            VALUES (
                @BundlingStepId, @NewBundleId, NULL, @BundlingDivisionId, @BundlingResourceId, NULL,
                @Qty, 0, 0, 0,
                NULL, @BundlingTargetDivisionId, SYSDATETIME(), @UserId
            );

            UPDATE awl
            SET received_at = SYSDATETIME(),
                received_by_resource_id = @BundlingResourceId,
                received_remark = 'Otomatis: pembuatan bundle'
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE aw.article_id = @ArticleId AND aw.requires_bundle = 0
              AND aw.deleted_at IS NULL AND awl.deleted_at IS NULL
              AND awl.received_at IS NULL AND awl.target_division_id IS NOT NULL;

            COMMIT TRAN;

            SELECT @NewBundleId AS NewId, @NewPrintJobId AS NewPrintJobId, @NewBundleNo AS NewBundleNo;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF @Qty IS NULL OR @Qty <= 0
        BEGIN
            RAISERROR('Qty bundle harus lebih dari 0.', 16, 1);
            RETURN;
        END

        -- Prompt 17: perbaikan bug -- [status] sudah dihapus sejak Prompt 12b. Tolak bila
        -- bundle sudah punya log hidup di step station (sudah dikerjakan) atau log Bundling-
        -- nya sudah diserah-terimakan (received_at terisi).
        DECLARE @UpdArticleId INT, @UpdBundlingDivisionId INT;
        SELECT @UpdArticleId = b.article_id, @UpdBundlingDivisionId = aw.division_id
        FROM bundles b
        LEFT JOIN article_workflows aw ON aw.article_id = b.article_id AND aw.deleted_at IS NULL AND aw.is_bundling = 1
        WHERE b.bundle_id = @Id AND b.deleted_at IS NULL;

        -- Prompt 18: project terkunci (manual_status) menolak perubahan bundle.
        DECLARE @LockStatus_Update VARCHAR(20), @LockReason_Update VARCHAR(255);
        SELECT @LockStatus_Update = p.manual_status, @LockReason_Update = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @UpdArticleId;

        IF @LockStatus_Update IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Update VARCHAR(30) = CASE @LockStatus_Update
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Update END;
            DECLARE @LockSuffix_Update VARCHAR(300) = CASE WHEN @LockReason_Update IS NOT NULL AND LTRIM(RTRIM(@LockReason_Update)) <> ''
                THEN ' (Alasan: ' + @LockReason_Update + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Update, @LockSuffix_Update);
            RETURN;
        END

        IF EXISTS (
            SELECT 1
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 0
        ) OR EXISTS (
            SELECT 1
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1 AND awl.received_at IS NOT NULL
        )
        BEGIN
            RAISERROR('Bundle sudah diproses, tidak bisa diubah.', 16, 1);
            RETURN;
        END

        IF @BundlingResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @BundlingResourceId AND division_id = @UpdBundlingDivisionId AND is_active = 1 AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pelaksana bundling tidak valid.', 16, 1);
            RETURN;
        END

        UPDATE bundles
        SET qty = @Qty,
            resource_id = @ResourceId,
            resource_person_name = @ResourcePersonName,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE bundle_id = @Id AND deleted_at IS NULL;

        UPDATE awl
        SET awl.qty_ok = @Qty,
            awl.resource_id = ISNULL(@BundlingResourceId, awl.resource_id),
            awl.updated_at = SYSDATETIME(),
            awl.updated_by = @UserId
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        DECLARE @DelArticleId INT;
        SELECT @DelArticleId = article_id FROM bundles WHERE bundle_id = @Id AND deleted_at IS NULL;

        -- Prompt 18: project terkunci (manual_status) menolak penghapusan bundle.
        DECLARE @LockStatus_Delete VARCHAR(20), @LockReason_Delete VARCHAR(255);
        SELECT @LockStatus_Delete = p.manual_status, @LockReason_Delete = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @DelArticleId;

        IF @LockStatus_Delete IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Delete VARCHAR(30) = CASE @LockStatus_Delete
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Delete END;
            DECLARE @LockSuffix_Delete VARCHAR(300) = CASE WHEN @LockReason_Delete IS NOT NULL AND LTRIM(RTRIM(@LockReason_Delete)) <> ''
                THEN ' (Alasan: ' + @LockReason_Delete + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Delete, @LockSuffix_Delete);
            RETURN;
        END

        IF EXISTS (
            SELECT 1
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 0
        ) OR EXISTS (
            SELECT 1
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1 AND awl.received_at IS NOT NULL
        )
        BEGIN
            RAISERROR('Bundle sudah diproses, tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        UPDATE bundles
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE bundle_id = @Id AND deleted_at IS NULL;

        UPDATE awl
        SET awl.deleted_at = SYSDATETIME(),
            awl.deleted_by = @UserId,
            awl.delete_reason = 'Bundle dihapus'
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1;
    END
END;
GO

-- Cetak ulang label: insert baris print_jobs baru, payload dirakit ulang dari data terkini
-- (bukan dari job lama, supaya perubahan qty/penjahit ikut terbawa di label baru).
CREATE OR ALTER PROCEDURE SIS_Bundle_ReprintLabel
    @BundleId      INT,
    @PublicBaseUrl VARCHAR(255) = NULL,
    @UserId        INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Bundle tidak ditemukan.', 16, 1);
        RETURN;
    END

    DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/b/' + (SELECT serial FROM bundles WHERE bundle_id = @BundleId);

    DECLARE @Payload NVARCHAR(MAX) = (
        SELECT
            b.serial AS serial,
            b.bundle_no AS bundle_no,
            @QrContent AS qr_content,
            p.project_name AS project_name,
            a.article_name AS article_name,
            a.style AS style,
            a.color AS color,
            spd.size_name AS size_name,
            b.qty AS qty,
            res.resource_name AS resource_name,
            b.resource_person_name AS resource_person_name
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources res ON res.resource_id = b.resource_id
        WHERE b.bundle_id = @BundleId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
    VALUES ('BUNDLE_LABEL', @BundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewPrintJobId;
END;
GO

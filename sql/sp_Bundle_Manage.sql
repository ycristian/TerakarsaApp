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
--   4. UPDATE/DELETE ditolak hanya jika bundle sudah punya log hidup berstatus COMPLETED di
--      article_workflow_logs (artinya sudah selesai dikerjakan) -- log RECEIVED saja masih
--      boleh, supervisor masih bisa ganti line/qty/hapus bundle yang belum selesai dikerjakan.
--   5. Serial tidak pernah berubah setelah dibuat.
--   6. bundle_no = nomor urut pendek per project (1, 2, 3, ...), naik terus lintas artikel
--      sampai project selesai, dihitung atas SEMUA bundle project ini (termasuk yang
--      soft-deleted) supaya nomor tidak pernah dipakai ulang. Digenerate di sini, di dalam
--      applock yang sama dengan serial (bundle_serial_seq) -- project tidak punya sequence
--      sendiri, jadi cukup satu lock global untuk keduanya.

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
    @UserId              INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
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
                    @Qty AS qty
                FROM articles a
                INNER JOIN projects p ON p.project_id = a.project_id
                INNER JOIN article_sizes asz ON asz.article_size_id = @ArticleSizeId
                INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
                WHERE a.article_id = @ArticleId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
            VALUES ('BUNDLE_LABEL', @NewBundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

            DECLARE @NewPrintJobId INT = CAST(SCOPE_IDENTITY() AS INT);

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

        IF EXISTS (
            SELECT 1 FROM article_workflow_logs
            WHERE bundle_id = @Id AND [status] = 'COMPLETED' AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Bundle ini sudah selesai dikerjakan (COMPLETED), tidak bisa diubah.', 16, 1);
            RETURN;
        END

        UPDATE bundles
        SET qty = @Qty,
            resource_id = @ResourceId,
            resource_person_name = @ResourcePersonName,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE bundle_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM article_workflow_logs
            WHERE bundle_id = @Id AND [status] = 'COMPLETED' AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Bundle ini sudah selesai dikerjakan (COMPLETED), tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        UPDATE bundles
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE bundle_id = @Id AND deleted_at IS NULL;
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
            b.qty AS qty
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE b.bundle_id = @BundleId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
    VALUES ('BUNDLE_LABEL', @BundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewPrintJobId;
END;
GO

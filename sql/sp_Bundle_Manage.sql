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
--   4. UPDATE ditolak bila bundle sudah punya log hidup di step station (is_bundling =
--      0, artinya sudah disentuh divisi produksi) ATAU log Bundling-nya sudah received_at
--      terisi (sudah diserah-terimakan ke divisi berikutnya) -- selama belum, supervisor masih
--      bisa ganti line/qty. Perbaikan Prompt 17: pengecekan lama memakai kolom
--      [status] = 'COMPLETED' yang sudah dihapus sejak Prompt 12b (bug, selalu gagal).
--      DELETE memakai aturan waktu, bukan status -- lihat catatan di action DELETE.
--   5. Serial tidak pernah berubah setelah dibuat.
--   6. bundle_no = nomor urut pendek per project (1, 2, 3, ...), naik terus lintas artikel
--      sampai project selesai, dihitung atas SEMUA bundle project ini (termasuk yang
--      soft-deleted) supaya nomor tidak pernah dipakai ulang. Digenerate di sini, di dalam
--      applock yang sama dengan serial (bundle_serial_seq) -- project tidak punya sequence
--      sendiri, jadi cukup satu lock global untuk keduanya.
--   7. Prompt 17: CREATE membuat juga baris article_workflow_logs untuk step Bunding implisit
--      artikel ini (bundle_id = bundle baru, qty_ok = qty bundle, received_at NULL) dan
--      auto-receive log non-bundle (mis. Cutting) yang masih pending -- lihat detail di
--      badan procedure. @BundlingResourceId (opsional) = pelaksana yang mengemas bundle ini;
--      UPDATE menyinkronkan qty_ok/resource_id log tsb, DELETE ikut soft-delete log tsb.
--      Prompt 23: auto-receive DIPERSEMPIT -- hanya baris dari step non-bundle dengan
--      sort_order TERBESAR di antara step requires_bundle = 0 hidup artikel ini (step non-
--      bundle sebelumnya, mis. DTF Print sebelum Cutting, diterima manual oleh divisi
--      berikutnya lewat tab IN stasiun, bukan lagi otomatis di sini).
--   8. Prompt 18: CREATE/UPDATE/DELETE ditolak kalau project artikel ini berstatus manual
--      (ON_HOLD/COMPLETED/CANCELLED) -- pesan RAISERROR menyertakan alasan bila ada.
--      SIS_Bundle_ReprintLabel TIDAK dikunci (cetak ulang label tetap boleh kapan pun).
--   9. Prompt 24: @SkipPrintJob (default 0) -- bila 1, CREATE melewati insert print_jobs
--      (dipakai station saat checkbox "Cetak label otomatis" tidak dicentang). UPDATE guard
--      dipecah jadi 2 pesan terpisah supaya jelas: log step berikutnya (is_bundling = 0) vs
--      log Bundling sendiri sudah diterima (received_at terisi) -- keduanya tetap menolak
--      perubahan, hanya pesannya yang dibedakan.
--   10. Prompt 25: kalau bundle dibuat dengan @ResourceId (penjahit/Line) terisi, log
--      Bundling-nya LANGSUNG dibuat received_at/received_by_resource_id = @ResourceId (auto-
--      diterima oleh Line tujuan) -- Line sudah pasti sejak bundle dibuat, jadi tidak perlu
--      scan/Terima manual lagi di tab IN stasiun tujuan. Konsekuensi: berlaku juga aturan #4 --
--      begitu received_at terisi (langsung setelah CREATE), bundle TIDAK bisa lagi
--      diubah/dihapus lewat SIS_Bundle_Manage (harus direvisi dari sisi divisi tujuan).
--      Tanpa penjahit (@ResourceId NULL), tetap pending seperti semula (perilaku lama).
--      Fix: CREATE sekarang mewajibkan @ResourceId (RAISERROR bila NULL) -- cabang "tanpa
--      penjahit" di atas jadi tidak pernah kejadian lagi dari CREATE, tapi dibiarkan (bukan
--      dihapus) karena UPDATE tidak ikut diwajibkan (bundle lama boleh tetap tanpa penjahit).
--   11. Fix: jendela 1 jam pada DELETE hanya berlaku KALAU log Bundling-nya sudah received_at
--      terisi (auto-diterima Line tujuan saat dibuat) -- selama belum diterima divisi
--      berikutnya, Hapus boleh kapan pun (tidak ada batas waktu). Begitu diterima, Hapus
--      hanya boleh selama masih dalam 1 jam sejak bundles.created_at; lewat itu harus
--      direvisi manual dari divisi tujuan (dipakai tombol "Hapus" tab OUT station Bundling).
--   12. Fix: UPDATE mengikuti aturan jendela 1 jam yang sama dengan DELETE -- begitu log
--      Bundling sudah received_at terisi, UPDATE tetap diizinkan selama masih dalam 1 jam
--      sejak bundles.created_at (dipakai tombol "Edit" di tab OUT station, berdampingan
--      dengan "Hapus"). Lewat 1 jam, harus direvisi manual dari divisi tujuan. Selama belum
--      diterima, UPDATE tidak dibatasi waktu sama sekali.
--   13. Fix: UPDATE bisa ikut mengubah ukuran (@ArticleSizeId, opsional -- NULL berarti tidak
--      diubah, dipakai admin /bundles yang belum mengirim field ini). Kalau ukuran berubah,
--      sort_order dihitung ulang relatif ke grup ukuran baru (pola sama dengan CREATE) supaya
--      urutan tampil tetap konsisten per ukuran.

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
    @SkipPrintJob        BIT = 0,
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

        -- Fix: Penjahit (resource) wajib dipilih saat bundle dibuat -- sebelumnya @ResourceId
        -- NULL diperbolehkan (log Bundling tetap pending, lihat catatan #10), tapi sekarang
        -- UI (station & admin bundle) selalu mewajibkan pilihan penjahit, ditegakkan di sini juga.
        IF @ResourceId IS NULL
        BEGIN
            RAISERROR('Penjahit (resource) wajib dipilih.', 16, 1);
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

            -- Prompt 27: huruf bundle project ini (NULL utk project lama sebelum Prompt 27) --
            -- dipakai payload label + dikembalikan ke client, TIDAK mengubah bundle_no itu sendiri.
            DECLARE @NewBundleLetter CHAR(1);
            SELECT @NewBundleLetter = bundle_letter FROM projects WHERE project_id = @ProjectId;

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

            -- Prompt 24: @SkipPrintJob = 1 (checkbox "Cetak label otomatis" tidak dicentang
            -- di station) -- lewati insert print_jobs, NewPrintJobId dikembalikan NULL.
            DECLARE @NewPrintJobId INT = NULL;
            IF @SkipPrintJob = 0
            BEGIN
                DECLARE @Payload NVARCHAR(MAX) = (
                    SELECT
                        @NewSerial AS serial,
                        @NewBundleNo AS bundle_no,
                        @NewBundleLetter AS bundle_letter,
                        @QrContent AS qr_content,
                        p.project_name AS project_name,
                        p.no_po AS no_po,
                        p.material_name AS material_name,
                        a.article_name AS article_name,
                        a.style AS style,
                        a.color AS color,
                        spk.size_pack_name AS size_pack_name,
                        spd.size_name AS size_name,
                        @Qty AS qty,
                        res.resource_name AS resource_name,
                        @ResourcePersonName AS resource_person_name,
                        (SELECT created_at FROM bundles WHERE bundle_id = @NewBundleId) AS started_at,
                        CAST(NULL AS VARCHAR(255)) AS remark
                    FROM articles a
                    INNER JOIN projects p ON p.project_id = a.project_id
                    INNER JOIN size_packs spk ON spk.size_pack_id = a.size_pack_id
                    INNER JOIN article_sizes asz ON asz.article_size_id = @ArticleSizeId
                    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
                    LEFT JOIN resources res ON res.resource_id = @ResourceId
                    WHERE a.article_id = @ArticleId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
                VALUES ('BUNDLE_LABEL', @NewBundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

                SET @NewPrintJobId = CAST(SCOPE_IDENTITY() AS INT);
            END

            -- Prompt 23: hanya step non-bundle TERAKHIR (sort_order terbesar di antara
            -- requires_bundle = 0 hidup) yang di-auto-receive di sini.
            DECLARE @LastNonBundleStepId INT;
            SELECT TOP 1 @LastNonBundleStepId = article_workflow_id
            FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 0
            ORDER BY sort_order DESC;

            -- Prompt 17: catat kegiatan Bundling sebagai log workflow (menunggu diterima
            -- divisi berikutnya) + auto-receive log non-bundle (mis. Cutting) yang masih
            -- pending -- tanggung jawab akurasi qty tetap di divisi non-bundle, sistem
            -- tidak memblokir pembuatan bundle karena ini.
            -- Prompt 25: kalau bundle langsung ditugaskan ke penjahit/Line (@ResourceId terisi
            -- -- lihat "Penjahit" di modal Buat Bundle), log Bundling ini LANGSUNG dianggap
            -- diterima oleh Line tersebut (received_at/received_by_resource_id terisi saat
            -- INSERT) -- Line tujuan sudah pasti, jadi tidak perlu scan/Terima manual lagi di
            -- tab IN stasiun. Tanpa penjahit (@ResourceId NULL), tetap pending seperti semula.
            INSERT INTO article_workflow_logs (
                article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
                qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing,
                remark, target_division_id, received_at, received_by_resource_id, received_remark,
                created_at, created_by
            )
            VALUES (
                @BundlingStepId, @NewBundleId, NULL, @BundlingDivisionId, @BundlingResourceId, NULL,
                @Qty, 0, 0, 0,
                NULL, @BundlingTargetDivisionId,
                CASE WHEN @ResourceId IS NOT NULL THEN SYSDATETIME() ELSE NULL END,
                @ResourceId,
                CASE WHEN @ResourceId IS NOT NULL THEN 'Otomatis: bundle langsung ditugaskan ke penjahit/Line' ELSE NULL END,
                SYSDATETIME(), @UserId
            );

            UPDATE awl
            SET received_at = SYSDATETIME(),
                received_by_resource_id = @BundlingResourceId,
                received_remark = 'Otomatis: pembuatan bundle'
            FROM article_workflow_logs awl
            WHERE awl.article_workflow_id = @LastNonBundleStepId
              AND awl.deleted_at IS NULL
              AND awl.received_at IS NULL AND awl.target_division_id IS NOT NULL;

            COMMIT TRAN;

            SELECT @NewBundleId AS NewId, @NewPrintJobId AS NewPrintJobId, @NewBundleNo AS NewBundleNo, @NewSerial AS NewSerial, @NewBundleLetter AS NewBundleLetter;
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
        DECLARE @UpdArticleId INT, @UpdBundlingDivisionId INT, @UpdCreatedAt DATETIME2, @UpdCurrentSizeId INT;
        SELECT @UpdArticleId = b.article_id, @UpdBundlingDivisionId = aw.division_id, @UpdCreatedAt = b.created_at, @UpdCurrentSizeId = b.article_size_id
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
        )
        BEGIN
            RAISERROR('Bundle sudah diproses, tidak bisa diubah.', 16, 1);
            RETURN;
        END

        -- Prompt 24: guard terpisah, pesan jelas -- log Bundling bundle ini sendiri sudah
        -- diserah-terimakan ke divisi berikutnya (received_at terisi).
        -- Fix: selama masih dalam jendela 1 jam sejak bundles.created_at (aturan sama dengan
        -- DELETE), UPDATE tetap diizinkan meski received_at sudah terisi -- lihat catatan #12.
        IF EXISTS (
            SELECT 1
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1 AND awl.received_at IS NOT NULL
        )
        BEGIN
            IF @UpdCreatedAt < DATEADD(HOUR, -1, SYSDATETIME())
            BEGIN
                RAISERROR('Bundle sudah diterima divisi berikutnya dan lebih dari 1 jam sejak dibuat, tidak bisa diubah.', 16, 1);
                RETURN;
            END
        END

        IF @BundlingResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @BundlingResourceId AND division_id = @UpdBundlingDivisionId AND is_active = 1 AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pelaksana bundling tidak valid.', 16, 1);
            RETURN;
        END

        -- Fix: ukuran boleh diubah lewat Edit bundle di station -- lihat catatan #13.
        IF @ArticleSizeId IS NOT NULL AND @ArticleSizeId <> @UpdCurrentSizeId AND NOT EXISTS (
            SELECT 1 FROM article_sizes
            WHERE article_size_id = @ArticleSizeId AND article_id = @UpdArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Ukuran tidak ditemukan untuk artikel ini.', 16, 1);
            RETURN;
        END

        DECLARE @UpdNewSizeId INT = ISNULL(@ArticleSizeId, @UpdCurrentSizeId);
        DECLARE @UpdSortOrder INT;
        IF @UpdNewSizeId <> @UpdCurrentSizeId
            SELECT @UpdSortOrder = ISNULL(MAX(sort_order), 0) + 1 FROM bundles WHERE article_size_id = @UpdNewSizeId AND deleted_at IS NULL;
        ELSE
            SELECT @UpdSortOrder = sort_order FROM bundles WHERE bundle_id = @Id;

        UPDATE bundles
        SET qty = @Qty,
            article_size_id = @UpdNewSizeId,
            sort_order = @UpdSortOrder,
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
        DECLARE @DelArticleId INT, @DelCreatedAt DATETIME2;
        SELECT @DelArticleId = article_id, @DelCreatedAt = created_at FROM bundles WHERE bundle_id = @Id AND deleted_at IS NULL;

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
        )
        BEGIN
            RAISERROR('Bundle sudah diproses, tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        -- Fix: jendela 1 jam hanya berlaku kalau log Bundling-nya sudah received_at (mis.
        -- auto-diterima Line tujuan saat dibuat, lihat catatan #10 di atas) -- lihat #11.
        -- Selama belum diterima divisi berikutnya, Hapus boleh kapan pun.
        IF EXISTS (
            SELECT 1
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1 AND awl.received_at IS NOT NULL
        )
        BEGIN
            IF @DelCreatedAt < DATEADD(HOUR, -1, SYSDATETIME())
            BEGIN
                RAISERROR('Bundle sudah diterima divisi berikutnya dan lebih dari 1 jam sejak dibuat, tidak bisa dihapus.', 16, 1);
                RETURN;
            END
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
-- remark payload = article_workflow_logs.remark TERBARU milik bundle ini (dicetak bold di
-- bawah Size Pack, lihat TsplBuilder.BuildBundleLabel), kecuali @RemarkOverride diisi.
-- Prompt: dipakai juga untuk "Print Label Cacat" (BundleScanCard) -- @Copies = jumlah lembar
-- yang diminta user, @RemarkOverride = catatan Kirim Hasil + ringkasan qty cacat (dirakit di
-- BundleService.PrintDefectLabelAsync), supaya beda dari remark log yang sudah tersimpan.
CREATE OR ALTER PROCEDURE SIS_Bundle_ReprintLabel
    @BundleId       INT,
    @PublicBaseUrl  VARCHAR(255) = NULL,
    @Copies         INT = 1,
    @RemarkOverride VARCHAR(255) = NULL,
    @UserId         INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Bundle tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @Copies IS NULL OR @Copies < 1
    BEGIN
        RAISERROR('Jumlah label harus minimal 1.', 16, 1);
        RETURN;
    END

    DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/b/' + (SELECT serial FROM bundles WHERE bundle_id = @BundleId);

    DECLARE @Payload NVARCHAR(MAX) = (
        SELECT
            b.serial AS serial,
            b.bundle_no AS bundle_no,
            p.bundle_letter AS bundle_letter,
            @QrContent AS qr_content,
            p.project_name AS project_name,
            p.no_po AS no_po,
            p.material_name AS material_name,
            a.article_name AS article_name,
            a.style AS style,
            a.color AS color,
            spk.size_pack_name AS size_pack_name,
            spd.size_name AS size_name,
            b.qty AS qty,
            res.resource_name AS resource_name,
            b.resource_person_name AS resource_person_name,
            b.created_at AS started_at,
            ISNULL(@RemarkOverride, (
                SELECT TOP 1 remark FROM article_workflow_logs
                WHERE bundle_id = b.bundle_id AND deleted_at IS NULL
                  AND remark IS NOT NULL AND LTRIM(RTRIM(remark)) <> ''
                ORDER BY created_at DESC
            )) AS remark
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN size_packs spk ON spk.size_pack_id = a.size_pack_id
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources res ON res.resource_id = b.resource_id
        WHERE b.bundle_id = @BundleId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    DECLARE @Copy INT = 0;
    DECLARE @LastPrintJobId INT;
    WHILE @Copy < @Copies
    BEGIN
        INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
        VALUES ('BUNDLE_LABEL', @BundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

        SET @LastPrintJobId = CAST(SCOPE_IDENTITY() AS INT);
        SET @Copy += 1;
    END

    SELECT @LastPrintJobId AS NewPrintJobId;
END;
GO

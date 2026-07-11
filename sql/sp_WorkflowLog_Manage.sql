-- Mutasi data article_workflow_logs (Prompt 12b: model 1-baris-per-serah-terima).
-- Pengambilan data ada di sp_WorkflowLog_Select.sql.
--
-- @Action = 'CREATE' (= pekerjaan step selesai, dulu berstatus 'COMPLETED'):
--   Step non-bundle (requires_bundle = 0, @BundleId harus NULL):
--     - Boleh berkali-kali, tanpa prasyarat apa pun (bukan lagi prasyarat step ber-bundle).
--     - @ArticleSizeId wajib diisi dan harus milik artikel step itu.
--   Step ber-bundle (requires_bundle = 1, @BundleId wajib, milik artikel yang sama):
--     - Boleh berkali-kali per (step, bundle) -- baris susulan (Prompt 14b), lihat kuota
--       di bawah.
--     - Step ber-bundle PERTAMA (MIN sort_order hidup di antara requires_bundle = 1):
--       tanpa prasyarat baris sebelumnya; kalau bundles.resource_id diisi, @ResourceId
--       wajib sama (bundle ditugaskan ke line tertentu).
--     - Step ber-bundle SELANJUTNYA: baris step ber-bundle tepat sebelumnya (bundle
--       sama) harus ada, received_at sudah terisi, dan target_division_id-nya = divisi
--       step ini (baru diserahkan & diterima ke divisi ini).
--     - @ArticleSizeId harus NULL (size sudah melekat di bundle).
--   Umum: qty tidak boleh negatif; @ActingDivisionId (diisi dari token stasiun bila ada)
--   harus sama dengan divisi step, kalau tidak ditolak. target_division_id TIDAK LAGI
--   diterima dari pemanggil -- dihitung otomatis di sini dari urutan workflow (divisi
--   milik step hidup berikutnya, sort_order tepat di atas; NULL kalau ini step terakhir
--   artikel). Ini membuat "divisi tujuan" terkunci sesuai urutan, bukan pilihan bebas.
--
-- Prompt 14 -- validasi kuota qty (hanya step ber-bundle, berlaku utk CREATE & UPDATE):
--   Rantai qty per bundle: keluaran step ini tidak boleh diam-diam melebihi qty yang
--   masuk ke step ini (masuk step pertama = bundles.qty, masuk step selanjutnya =
--   SUM qty_ok log hidup bundle ini di step sebelumnya). Melebihi BOLEH lewat konfirmasi
--   sadar (@ConfirmExceed = 1, mis. menemukan barang dari bundle lain) -- bukan blok keras.
--   Tidak ada validasi qty untuk step non-bundle terhadap apa pun. Pesan format tetap
--   'QTY_EXCEED|...' -- prefix dipakai UI untuk mengenali kasus ini dan menampilkan dialog
--   konfirmasi.
--
-- Prompt 14b -- baris susulan per step + konfirmasi serahan tidak lengkap (step ber-bundle):
--   Satu bundle pada satu step BOLEH punya beberapa baris log (susulan) -- blok "satu baris
--   per bundle per step" DIHAPUS. Serahan yang membuat total step KURANG dari qty masuk
--   tetap boleh, tapi lewat konfirmasi sadar juga (@ConfirmShort = 1), simetris dengan
--   exceed -- pesan format tetap 'QTY_SHORT|...'. Exceed dan short independen, tidak
--   mungkin terjadi bersamaan (satu baris tidak bisa sekaligus > dan < qty masuk).
--
-- @Action = 'UPDATE' (revisi data SEBELUM diterima -- dipakai oleh divisi PEMBUAT baris,
-- bukan divisi tujuan): boleh mengubah qty_*, remark, article_size_id selama baris masih
-- hidup DAN received_at masih NULL (belum diserahkan/diterima). @ActingDivisionId (bila
-- diisi) harus = division_id baris ini (divisi yang membuatnya), bukan target_division_id.
-- Begitu received_at terisi (lewat RECEIVE), baris terkunci -- UPDATE ditolak.
-- Prompt 12d: @UserId WAJIB (pengganti pencatat -- user login yang merevisi; API stasiun
-- mengirim user sistem 'station', halaman login mengirim user JWT). @UpdatedByResourceId
-- opsional (pelaksana/operator sesi aktif saat revisi dari stasiun) -- kalau diisi, resource
-- harus hidup dan milik divisi baris log ini. Mengisi trio updated_at/updated_by/
-- updated_by_resource_id.
--
-- @Action = 'RECEIVE' (pengganti log RECEIVED terpisah pada model lama):
--   UPDATE satu-satunya yang diizinkan pada log: received_at, received_by_resource_id,
--   received_remark pada baris @Id. Baris harus hidup, received_at masih NULL, dan
--   target_division_id tidak NULL (baris tanpa tujuan serah tidak bisa "diterima").
--   @ActingDivisionId (bila diisi) harus = target_division_id baris tsb.
--
-- Prompt 15 -- @Action = 'UNRECEIVE' (pembatalan penerimaan, dipakai stasiun divisi
-- penerima): jendela sempit -- hanya selama divisi penerima BELUM mencatat hasil di step
-- berikutnya untuk bundle yang sama. Set received_at/received_by_resource_id/
-- received_remark kembali ke NULL; trio updated_at/updated_by/updated_by_resource_id
-- (Prompt 12d) dipakai sebagai jejak siapa yang membatalkan. @ActingDivisionId (bila
-- diisi) harus = target_division_id baris (hanya divisi penerima yang boleh membatalkan).
-- @UpdatedByResourceId wajib diisi (operator sesi aktif) dan harus resource hidup milik
-- divisi tsb. Tidak menyentuh alasan/kolom baru -- pembatalan tidak dicatat alasannya.
--
-- @Action = 'DELETE': soft delete + alasan wajib. Tambahan (Prompt 12b): tolak kalau
-- baris ber-bundle ini sudah dipakai sebagai dasar step berikutnya -- ada baris hidup
-- di step sesudahnya (sort_order lebih besar, artikel sama) untuk bundle yang sama.
--
-- Prompt 12e -- tab "Dikirim" di /station (dulu "Menunggu Diserahkan"):
--   @Action = 'CANCEL_HANDOVER' ("Batal Serah"): soft delete baris serah yang salah,
--   guard received_at IS NULL (begitu diterima, harus lewat UNRECEIVE di divisi penerima,
--   bukan ini). @ActingDivisionId (bila diisi) harus = division_id baris (divisi pembuat).
--   delete_reason diisi tetap ('Batal serah (stasiun)') -- UI tidak menyediakan input alasan
--   bebas untuk aksi ini, beda dengan DELETE biasa.
--
--   @Action = 'REVISE_HANDOVER' ("Revisi" di tab Dikirim): superset dari UPDATE khusus baris
--   serah -- selain qty_*/remark, boleh juga mengubah target_division_id (@NewTargetDivisionId,
--   wajib, harus divisi yang dipakai step manapun di workflow artikel ini) dan resource_id
--   (@ResourceId, penjahit/pelaksana baris ini, opsional, harus resource hidup milik divisi
--   baris ini). Guard received_at IS NULL, sama dengan UPDATE. SENGAJA tidak menjalankan
--   validasi kuota QTY_EXCEED/QTY_SHORT (di luar cakupan Prompt 12e) -- nilai disimpan apa
--   adanya, murni koreksi data sebelum diterima. Mengisi trio updated_at/updated_by/
--   updated_by_resource_id (Prompt 12d) seperti UPDATE.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowLog_Manage
    @Action              VARCHAR(20),
    @Id                  INT = NULL,
    @ArticleWorkflowId   INT = NULL,
    @BundleId            INT = NULL,
    @ArticleSizeId       INT = NULL,
    @ResourceId          INT = NULL,
    @QtyOk               INT = 0,
    @QtyRejectPrint      INT = 0,
    @QtyRejectFabric     INT = 0,
    @QtyRejectSewing     INT = 0,
    @Remark              VARCHAR(500) = NULL,
    @UserId              INT = NULL,
    @DeleteReason        VARCHAR(255) = NULL,
    @ActingDivisionId    INT = NULL,
    @ReceivedByResourceId INT = NULL,
    @ReceivedRemark      VARCHAR(500) = NULL,
    @UpdatedByResourceId INT = NULL,
    @ConfirmExceed       BIT = 0,
    @ConfirmShort        BIT = 0,
    @NewTargetDivisionId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        DECLARE @DivisionId INT, @RequiresBundle BIT, @ArticleId INT, @SortOrder INT;

        SELECT @DivisionId = division_id, @RequiresBundle = requires_bundle,
               @ArticleId = article_id, @SortOrder = sort_order
        FROM article_workflows
        WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL;

        IF @DivisionId IS NULL
        BEGIN
            RAISERROR('Step workflow tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @DivisionId
        BEGIN
            RAISERROR('Step ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        DECLARE @MaxSort INT;
        SELECT @MaxSort = MAX(sort_order) FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL;

        -- Divisi tujuan terkunci sesuai urutan workflow: divisi step hidup berikutnya
        -- (NULL kalau step ini adalah step terakhir artikel -- tidak ada serah lanjutan).
        DECLARE @ComputedTargetDivisionId INT;
        SELECT TOP 1 @ComputedTargetDivisionId = division_id
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order > @SortOrder
        ORDER BY sort_order ASC;

        IF @RequiresBundle = 0
        BEGIN
            IF @BundleId IS NOT NULL
            BEGIN
                RAISERROR('Step ini tidak butuh bundle. Bundle harus kosong.', 16, 1);
                RETURN;
            END

            IF @ArticleSizeId IS NULL
            BEGIN
                RAISERROR('Size wajib dipilih untuk step ini.', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM article_sizes
                WHERE article_size_id = @ArticleSizeId AND article_id = @ArticleId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Size tidak sesuai dengan artikel step ini.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            IF @BundleId IS NULL
            BEGIN
                RAISERROR('Step ini butuh bundle. Bundle wajib diisi.', 16, 1);
                RETURN;
            END

            IF @ArticleSizeId IS NOT NULL
            BEGIN
                RAISERROR('Step ini tidak menerima input size (sudah melekat pada bundle).', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND article_id = @ArticleId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Bundle tidak sesuai dengan artikel step ini.', 16, 1);
                RETURN;
            END

            DECLARE @FirstBundleSort INT;
            SELECT @FirstBundleSort = MIN(sort_order)
            FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1;

            IF @SortOrder = @FirstBundleSort
            BEGIN
                DECLARE @BundleResourceId INT;
                SELECT @BundleResourceId = resource_id FROM bundles WHERE bundle_id = @BundleId;

                IF @BundleResourceId IS NOT NULL AND (@ResourceId IS NULL OR @BundleResourceId <> @ResourceId)
                BEGIN
                    RAISERROR('Bundle ini ditugaskan ke line lain.', 16, 1);
                    RETURN;
                END
            END
            ELSE
            BEGIN
                DECLARE @PrevArticleWorkflowId INT;
                SELECT TOP 1 @PrevArticleWorkflowId = article_workflow_id
                FROM article_workflows
                WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1 AND sort_order < @SortOrder
                ORDER BY sort_order DESC;

                IF @PrevArticleWorkflowId IS NULL OR NOT EXISTS (
                    SELECT 1 FROM article_workflow_logs
                    WHERE article_workflow_id = @PrevArticleWorkflowId AND bundle_id = @BundleId
                      AND received_at IS NOT NULL AND target_division_id = @DivisionId AND deleted_at IS NULL
                )
                BEGIN
                    RAISERROR('Bundle belum diterima divisi ini.', 16, 1);
                    RETURN;
                END
            END

            -- Prompt 14: validasi kuota qty (boleh lewat lewat @ConfirmExceed = 1).
            DECLARE @QtyMasuk INT;
            IF @SortOrder = @FirstBundleSort
                SELECT @QtyMasuk = qty FROM bundles WHERE bundle_id = @BundleId;
            ELSE
                SELECT @QtyMasuk = ISNULL(SUM(qty_ok), 0)
                FROM article_workflow_logs
                WHERE article_workflow_id = @PrevArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

            SET @QtyMasuk = ISNULL(@QtyMasuk, 0);

            DECLARE @QtySudah INT;
            SELECT @QtySudah = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

            IF @ConfirmExceed = 0 AND (@QtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing) > @QtyMasuk
            BEGIN
                RAISERROR('QTY_EXCEED|Total melebihi qty masuk step ini (masuk %d, sudah tercatat %d).', 16, 1, @QtyMasuk, @QtySudah);
                RETURN;
            END

            -- Prompt 14b: kurang dari batas boleh (baris susulan menyusul), tapi lewat
            -- konfirmasi sadar juga -- simetris dengan exceed di atas.
            IF @ConfirmShort = 0 AND (@QtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing) < @QtyMasuk
            BEGIN
                DECLARE @NewTotalCreate INT = @QtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing;
                RAISERROR('QTY_SHORT|Total baru %d dari %d - serahan tidak lengkap. Sisa bisa dicatat sebagai baris susulan.', 16, 1, @NewTotalCreate, @QtyMasuk);
                RETURN;
            END
        END

        INSERT INTO article_workflow_logs (
            article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
            qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing,
            remark, target_division_id, created_at, created_by
        )
        VALUES (
            @ArticleWorkflowId, @BundleId, @ArticleSizeId, @DivisionId, @ResourceId, NULL,
            @QtyOk, @QtyRejectPrint, @QtyRejectFabric, @QtyRejectSewing,
            @Remark, @ComputedTargetDivisionId, SYSDATETIME(), @UserId
        );

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        DECLARE @UpdDivisionId INT, @UpdBundleId INT, @UpdReceivedAt DATETIME2, @UpdArticleId INT,
                @UpdArticleWorkflowId INT, @UpdSortOrder INT;
        SELECT @UpdDivisionId = awl.division_id, @UpdBundleId = awl.bundle_id,
               @UpdReceivedAt = awl.received_at, @UpdArticleId = aw.article_id,
               @UpdArticleWorkflowId = awl.article_workflow_id, @UpdSortOrder = aw.sort_order
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id AND awl.deleted_at IS NULL;

        IF @UpdDivisionId IS NULL
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @UpdReceivedAt IS NOT NULL
        BEGIN
            RAISERROR('Log ini sudah diterima, tidak bisa diubah lagi.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @UpdDivisionId
        BEGIN
            RAISERROR('Log ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        IF @UserId IS NULL
        BEGIN
            RAISERROR('User pengubah tidak dikenal.', 16, 1);
            RETURN;
        END

        IF @UpdatedByResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @UpdatedByResourceId AND division_id = @UpdDivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Operator bukan milik divisi ini.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        IF @UpdBundleId IS NULL
        BEGIN
            IF @ArticleSizeId IS NULL
            BEGIN
                RAISERROR('Size wajib dipilih untuk step ini.', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM article_sizes
                WHERE article_size_id = @ArticleSizeId AND article_id = @UpdArticleId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Size tidak sesuai dengan artikel step ini.', 16, 1);
                RETURN;
            END
        END
        ELSE IF @ArticleSizeId IS NOT NULL
        BEGIN
            RAISERROR('Step ini tidak menerima input size (sudah melekat pada bundle).', 16, 1);
            RETURN;
        END

        -- Prompt 14: validasi kuota qty (hanya step ber-bundle, kecualikan baris ini sendiri
        -- dari @QtySudah karena sedang direvisi).
        IF @UpdBundleId IS NOT NULL
        BEGIN
            DECLARE @UpdFirstBundleSort INT;
            SELECT @UpdFirstBundleSort = MIN(sort_order)
            FROM article_workflows
            WHERE article_id = @UpdArticleId AND deleted_at IS NULL AND requires_bundle = 1;

            DECLARE @UpdQtyMasuk INT;
            IF @UpdSortOrder = @UpdFirstBundleSort
                SELECT @UpdQtyMasuk = qty FROM bundles WHERE bundle_id = @UpdBundleId;
            ELSE
            BEGIN
                DECLARE @UpdPrevArticleWorkflowId INT;
                SELECT TOP 1 @UpdPrevArticleWorkflowId = article_workflow_id
                FROM article_workflows
                WHERE article_id = @UpdArticleId AND deleted_at IS NULL AND requires_bundle = 1 AND sort_order < @UpdSortOrder
                ORDER BY sort_order DESC;

                SELECT @UpdQtyMasuk = ISNULL(SUM(qty_ok), 0)
                FROM article_workflow_logs
                WHERE article_workflow_id = @UpdPrevArticleWorkflowId AND bundle_id = @UpdBundleId AND deleted_at IS NULL;
            END

            SET @UpdQtyMasuk = ISNULL(@UpdQtyMasuk, 0);

            DECLARE @UpdQtySudah INT;
            SELECT @UpdQtySudah = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @UpdArticleWorkflowId AND bundle_id = @UpdBundleId
              AND deleted_at IS NULL AND workflow_log_id <> @Id;

            IF @ConfirmExceed = 0 AND (@UpdQtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing) > @UpdQtyMasuk
            BEGIN
                RAISERROR('QTY_EXCEED|Total melebihi qty masuk step ini (masuk %d, sudah tercatat %d).', 16, 1, @UpdQtyMasuk, @UpdQtySudah);
                RETURN;
            END

            IF @ConfirmShort = 0 AND (@UpdQtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing) < @UpdQtyMasuk
            BEGIN
                DECLARE @NewTotalUpdate INT = @UpdQtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing;
                RAISERROR('QTY_SHORT|Total baru %d dari %d - serahan tidak lengkap. Sisa bisa dicatat sebagai baris susulan.', 16, 1, @NewTotalUpdate, @UpdQtyMasuk);
                RETURN;
            END
        END

        UPDATE article_workflow_logs
        SET qty_ok = @QtyOk,
            qty_reject_print = @QtyRejectPrint,
            qty_reject_fabric = @QtyRejectFabric,
            qty_reject_sewing = @QtyRejectSewing,
            remark = @Remark,
            article_size_id = @ArticleSizeId,
            updated_at = SYSDATETIME(),
            updated_by = @UserId,
            updated_by_resource_id = @UpdatedByResourceId
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'RECEIVE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM article_workflow_logs WHERE workflow_log_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @RecTargetDivisionId INT, @RecReceivedAt DATETIME2;
        SELECT @RecTargetDivisionId = target_division_id, @RecReceivedAt = received_at
        FROM article_workflow_logs
        WHERE workflow_log_id = @Id;

        IF @RecTargetDivisionId IS NULL
        BEGIN
            RAISERROR('Log ini tidak memiliki tujuan serah, tidak bisa diterima.', 16, 1);
            RETURN;
        END

        IF @RecReceivedAt IS NOT NULL
        BEGIN
            RAISERROR('Log ini sudah diterima sebelumnya.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @RecTargetDivisionId
        BEGIN
            RAISERROR('Serah terima ini bukan untuk divisi Anda.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET received_at = SYSDATETIME(),
            received_by_resource_id = @ReceivedByResourceId,
            received_remark = @ReceivedRemark
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'UNRECEIVE'
    BEGIN
        DECLARE @UnrTargetDivisionId INT, @UnrBundleId INT, @UnrArticleId INT, @UnrSortOrder INT;
        SELECT @UnrTargetDivisionId = awl.target_division_id, @UnrBundleId = awl.bundle_id,
               @UnrArticleId = aw.article_id, @UnrSortOrder = aw.sort_order
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id AND awl.deleted_at IS NULL AND awl.received_at IS NOT NULL;

        IF @UnrTargetDivisionId IS NULL
        BEGIN
            RAISERROR('Baris ini belum diterima.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @UnrTargetDivisionId
        BEGIN
            RAISERROR('Hanya divisi penerima yang bisa membatalkan.', 16, 1);
            RETURN;
        END

        IF @UpdatedByResourceId IS NULL
        BEGIN
            RAISERROR('Operator wajib dipilih.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @UpdatedByResourceId AND division_id = @UnrTargetDivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Operator bukan milik divisi ini.', 16, 1);
            RETURN;
        END

        IF @UnrBundleId IS NOT NULL AND EXISTS (
            SELECT 1
            FROM article_workflow_logs awl2
            INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
            WHERE awl2.bundle_id = @UnrBundleId AND awl2.deleted_at IS NULL
              AND aw2.article_id = @UnrArticleId AND aw2.sort_order > @UnrSortOrder
        )
        BEGIN
            RAISERROR('Sudah ada hasil tercatat di step berikutnya. Hapus dulu hasil tersebut.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET received_at = NULL,
            received_by_resource_id = NULL,
            received_remark = NULL,
            updated_at = SYSDATETIME(),
            updated_by = @UserId,
            updated_by_resource_id = @UpdatedByResourceId
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'CANCEL_HANDOVER'
    BEGIN
        DECLARE @CancelDivisionId INT, @CancelReceivedAt DATETIME2, @CancelTargetDivisionId INT;
        SELECT @CancelDivisionId = division_id, @CancelReceivedAt = received_at,
               @CancelTargetDivisionId = target_division_id
        FROM article_workflow_logs
        WHERE workflow_log_id = @Id AND deleted_at IS NULL;

        IF @CancelDivisionId IS NULL
        BEGIN
            RAISERROR('Baris serah tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @CancelTargetDivisionId IS NULL
        BEGIN
            RAISERROR('Baris ini bukan baris serah.', 16, 1);
            RETURN;
        END

        IF @CancelReceivedAt IS NOT NULL
        BEGIN
            RAISERROR('Baris ini sudah diterima, tidak bisa dibatalkan lewat Batal Serah.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @CancelDivisionId
        BEGIN
            RAISERROR('Baris serah ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            delete_reason = 'Batal serah (stasiun)'
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'REVISE_HANDOVER'
    BEGIN
        DECLARE @RevDivisionId INT, @RevReceivedAt DATETIME2, @RevArticleId INT;
        SELECT @RevDivisionId = awl.division_id, @RevReceivedAt = awl.received_at, @RevArticleId = aw.article_id
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id AND awl.deleted_at IS NULL;

        IF @RevDivisionId IS NULL
        BEGIN
            RAISERROR('Baris serah tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @RevReceivedAt IS NOT NULL
        BEGIN
            RAISERROR('Baris ini sudah diterima, tidak bisa direvisi.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @RevDivisionId
        BEGIN
            RAISERROR('Baris serah ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        IF @UserId IS NULL
        BEGIN
            RAISERROR('User pengubah tidak dikenal.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        IF @NewTargetDivisionId IS NULL
        BEGIN
            RAISERROR('Divisi tujuan wajib diisi.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM article_workflows
            WHERE article_id = @RevArticleId AND division_id = @NewTargetDivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Divisi tujuan tidak valid untuk artikel ini.', 16, 1);
            RETURN;
        END

        IF @ResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources WHERE resource_id = @ResourceId AND division_id = @RevDivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Penjahit bukan milik divisi ini.', 16, 1);
            RETURN;
        END

        IF @UpdatedByResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources WHERE resource_id = @UpdatedByResourceId AND division_id = @RevDivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Operator bukan milik divisi ini.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET qty_ok = @QtyOk,
            qty_reject_print = @QtyRejectPrint,
            qty_reject_fabric = @QtyRejectFabric,
            qty_reject_sewing = @QtyRejectSewing,
            remark = @Remark,
            target_division_id = @NewTargetDivisionId,
            resource_id = ISNULL(@ResourceId, resource_id),
            updated_at = SYSDATETIME(),
            updated_by = @UserId,
            updated_by_resource_id = @UpdatedByResourceId
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF @DeleteReason IS NULL OR LTRIM(RTRIM(@DeleteReason)) = ''
        BEGIN
            RAISERROR('Alasan hapus wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @DelBundleId INT, @DelSortOrder INT, @DelArticleId INT;
        SELECT @DelBundleId = awl.bundle_id, @DelSortOrder = aw.sort_order, @DelArticleId = aw.article_id
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id AND awl.deleted_at IS NULL;

        IF @DelBundleId IS NOT NULL AND EXISTS (
            SELECT 1
            FROM article_workflow_logs awl2
            INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
            WHERE awl2.bundle_id = @DelBundleId AND awl2.deleted_at IS NULL
              AND aw2.article_id = @DelArticleId AND aw2.sort_order > @DelSortOrder
        )
        BEGIN
            RAISERROR('Baris ini sudah dipakai sebagai dasar step berikutnya, tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            delete_reason = @DeleteReason
        WHERE workflow_log_id = @Id AND deleted_at IS NULL;
    END
    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO

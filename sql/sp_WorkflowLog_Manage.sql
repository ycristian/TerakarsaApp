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
--     - is_bundling = 1 (step Bundling implisit, Prompt 17): baris log-nya TIDAK PERNAH
--       dibuat lewat @Action = 'CREATE' -- ditolak, hanya lahir lewat SIS_Bundle_Manage
--       CREATE (lihat sql/sp_Bundle_Manage.sql).
--     - SETIAP step ber-bundle is_bundling = 0 (termasuk step station PERTAMA, mis.
--       Sewing): baris step ber-bundle tepat sebelumnya (bundle sama -- untuk step station
--       pertama, ini SELALU step Bundling) harus ada, received_at sudah terisi, dan
--       target_division_id-nya = divisi step ini (baru diserahkan & diterima ke divisi
--       ini). Step ber-bundle pertama TIDAK LAGI bebas prasyarat sejak Prompt 17.
--     - Khusus step station PERTAMA (MIN sort_order di antara requires_bundle = 1 AND
--       is_bundling = 0): kalau bundles.resource_id diisi, @ResourceId wajib sama (bundle
--       ditugaskan ke line tertentu) -- KECUALI stasiun pengirim tidak terkunci ke resource
--       bawaan (@ActingAllowResourceChange = 1, Prompt 27), match ini dilewati sepenuhnya.
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
-- Prompt 23: baris step TERAKHIR artikel (target_division_id NULL) tidak pernah punya
-- received_at (tidak ada divisi tujuan yang "menerima"), jadi tanpa batas lain baris ini
-- bisa direvisi selamanya -- dibatasi jendela H+1 (hari dibuat + 1 hari kalender) alih-alih.
-- Baris dengan target_division_id NOT NULL tidak kena batas ini (tetap dikunci oleh RECEIVE
-- seperti biasa). Guard sama juga ditegakkan di SIS_Bundle_ScanInfo supaya UI tidak
-- menawarkan tombol Edit di luar jendela ini.
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
--   Prompt 23: baris step TERAKHIR (target_division_id NULL) juga boleh dibatalkan lewat
--   aksi yang sama selama masih dalam jendela H+1 (received_at selalu NULL utk baris ini,
--   jadi guard itu otomatis lolos) -- delete_reason jadi 'Batal step terakhir (stasiun)'
--   untuk kasus ini. Baris target_division_id NOT NULL yang sudah lewat H+1 tapi belum
--   diterima TETAP bisa dibatalkan kapan saja (tidak kena guard H+1, beda dengan UPDATE).
--
--   @Action = 'REVISE_HANDOVER' ("Revisi" di tab Dikirim): superset dari UPDATE khusus baris
--   serah -- selain qty_*/remark, boleh juga mengubah target_division_id (@NewTargetDivisionId,
--   wajib, harus divisi yang dipakai step manapun di workflow artikel ini) dan resource_id
--   (@ResourceId, penjahit/pelaksana baris ini, opsional, harus resource hidup milik divisi
--   baris ini). Guard received_at IS NULL, sama dengan UPDATE. SENGAJA tidak menjalankan
--   validasi kuota QTY_EXCEED/QTY_SHORT (di luar cakupan Prompt 12e) -- nilai disimpan apa
--   adanya, murni koreksi data sebelum diterima. Mengisi trio updated_at/updated_by/
--   updated_by_resource_id (Prompt 12d) seperti UPDATE.
-- Fix (pasca Prompt 34): auto-terima DIHITUNG ULANG di sini juga (lihat blok komentar Prompt
-- 34 di bawah) -- kalau step @NewTargetDivisionId ber-auto_receive = 1, baris yang direvisi
-- ini langsung diterima lagi dalam transaksi yang sama. Ini membalik larangan asli Prompt 34
-- yang mengecualikan REVISE_HANDOVER.
--
-- Prompt 18 -- penguncian project: CREATE/UPDATE/RECEIVE/UNRECEIVE ditolak kalau project
-- artikel bersangkutan berstatus manual (ON_HOLD/COMPLETED/CANCELLED) -- pesan RAISERROR
-- menyertakan alasan bila ada. DELETE TIDAK dikunci (koreksi data oleh admin tetap boleh).
--
-- Prompt 28 -- @QtyRejectRework/@QtyLost: dua kategori qty baru, diperlakukan identik dengan
-- qty_reject_* yang sudah ada di CREATE/UPDATE/REVISE_HANDOVER (validasi non-negatif, ikut
-- SUM @QtySudah kuota). DELETE tidak berubah (soft delete generik, berlaku sama utk baris
-- NORMAL maupun ADJUSTMENT).
--
-- Prompt 28 -- @Action = 'ADJUST': penyesuaian qty ber-bundle (hanya step requires_bundle = 1
-- hidup) -- memindah qty yang SUDAH tercatat sebagai reject/hilang ke kategori reject/hilang
-- lain ATAU ke Qty OK (barang diperbaiki/ditemukan). Qty OK TIDAK PERNAH boleh dikurangi lewat
-- aksi ini. Dicatat sebagai baris BARU log_type = 'ADJUSTMENT' (riwayat baris lama terjaga),
-- bukan UPDATE baris lama. Jumlah keenam nilai (@QtyOk + 5 kategori reject/lost, boleh negatif
-- utk kategori yg dikurangi) WAJIB 0 -- murni mutasi antar kategori, tidak menambah/mengurangi
-- total step. Karena totalnya selalu 0, baris ADJUSTMENT otomatis netral terhadap kuota
-- step-nya sendiri (@QtySudah di CREATE/UPDATE tidak perlu filter log_type). @QtyOk pada baris
-- ADJUSTMENT tetap ikut terhitung ke @QtyMasuk step BERIKUTNYA (SUM qty_ok apa adanya, tanpa
-- filter log_type) -- barang hasil perbaikan mengalir maju seperti hasil normal.
-- Saldo per kategori reject/lost = SUM kolom itu atas semua baris hidup (step, bundle) ini
-- (NORMAL + ADJUSTMENT sebelumnya) -- tidak boleh negatif setelah penyesuaian. @QtyOk > 0
-- mewajibkan @TargetDivisionId (divisi step ber-bundle berikutnya, dikunci sama seperti
-- COMPLETE) KECUALI step ini step ber-bundle terakhir; @QtyOk = 0 -> target_division_id NULL
-- (baris ini tidak pernah "diserahkan", tidak butuh diterima -- lihat catatan qty_ok = 0 di
-- SIS_Station_PendingReceives/PendingHandover & SIS_Bundle_ScanInfo).
-- @ActingDivisionId (dari token stasiun) WAJIB = divisi step (divisi pemilik step tempat
-- reject/hilang tercatat) -- hanya divisi itu yang boleh menyesuaikan.

-- Prompt 34 -- auto-terima per step: step penerima (step hidup berikutnya, sort_order
-- terkecil > step ini, division_id = target_division_id) bisa ber-flag article_workflows
-- .auto_receive = 1 -- kalau ya, @Action = 'CREATE' langsung mengisi received_at/
-- received_by_resource_id (= @ResourceId, pelaksana pengirim, boleh NULL)/received_remark
-- ('Otomatis: auto-terima') pada baris yang sama, tanpa RECEIVE manual. Tidak retroaktif
-- (hanya dihitung saat CREATE); RECEIVE/UNRECEIVE/UPDATE/CANCEL_HANDOVER/DELETE tidak
-- berubah -- UNRECEIVE tetap bisa membatalkan baris auto-received. REVISE_HANDOVER awalnya
-- juga dikecualikan, tapi lihat "Fix (pasca Prompt 34)" di atas action REVISE_HANDOVER --
-- belakangan JUGA dihitung ulang (dibalik atas permintaan pengguna, skenario Batal
-- Terima -> Revisi harus bisa auto-terima lagi).

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
    @QtyRejectRework     INT = 0,
    @QtyLost             INT = 0,
    @Remark              VARCHAR(500) = NULL,
    @UserId              INT = NULL,
    @DeleteReason        VARCHAR(255) = NULL,
    @ActingDivisionId    INT = NULL,
    @ReceivedByResourceId INT = NULL,
    @ReceivedRemark      VARCHAR(500) = NULL,
    @UpdatedByResourceId INT = NULL,
    @ConfirmExceed       BIT = 0,
    @ConfirmShort        BIT = 0,
    @NewTargetDivisionId INT = NULL,
    @ActingAllowResourceChange BIT = NULL,
    @TargetDivisionId    INT = NULL     -- Prompt 28: hanya dipakai @Action = 'ADJUST'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        DECLARE @DivisionId INT, @RequiresBundle BIT, @ArticleId INT, @SortOrder INT, @IsBundling BIT;

        SELECT @DivisionId = division_id, @RequiresBundle = requires_bundle,
               @ArticleId = article_id, @SortOrder = sort_order, @IsBundling = is_bundling
        FROM article_workflows
        WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL;

        IF @DivisionId IS NULL
        BEGIN
            RAISERROR('Step workflow tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- Prompt 18: project terkunci (manual_status) menolak pencatatan log workflow.
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

        -- Prompt 17: baris step Bundling implisit hanya lahir lewat SIS_Bundle_Manage CREATE.
        IF @IsBundling = 1
        BEGIN
            RAISERROR('Log step Bundling hanya dibuat lewat pembuatan bundle.', 16, 1);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @DivisionId
        BEGIN
            RAISERROR('Step ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0
           OR @QtyRejectRework < 0 OR @QtyLost < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        -- Total 0 di semua kategori tidak boleh dikirim sebagai hasil (baris kosong tidak
        -- pernah "diterima" -- lihat catatan qty_ok = 0 di sp_Bundle_ScanInfo.sql -- dan cuma
        -- jadi sampah timeline/posisi bundle, mis. artefak migrasi Prompt 33 untuk B26-000561).
        IF @QtyOk = 0 AND @QtyRejectPrint = 0 AND @QtyRejectFabric = 0 AND @QtyRejectSewing = 0
           AND @QtyRejectRework = 0 AND @QtyLost = 0
        BEGIN
            RAISERROR('Total qty tidak boleh 0. Isi minimal satu kategori (OK/reject/hilang).', 16, 1);
            RETURN;
        END

        DECLARE @MaxSort INT;
        SELECT @MaxSort = MAX(sort_order) FROM article_workflows WHERE article_id = @ArticleId AND deleted_at IS NULL;

        -- Divisi tujuan terkunci sesuai urutan workflow: divisi step hidup berikutnya
        -- (NULL kalau step ini adalah step terakhir artikel -- tidak ada serah lanjutan).
        -- Prompt 34: step penerima yang sama juga menentukan auto-terima -- kalau step
        -- penerima itu ber-auto_receive = 1, baris ini langsung diterima saat insert.
        DECLARE @ComputedTargetDivisionId INT, @ComputedTargetAutoReceive BIT;
        SELECT TOP 1 @ComputedTargetDivisionId = division_id, @ComputedTargetAutoReceive = auto_receive
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND sort_order > @SortOrder
        ORDER BY sort_order ASC;

        DECLARE @AutoReceivedAt DATETIME2 = NULL, @AutoReceivedByResourceId INT = NULL, @AutoReceivedRemark VARCHAR(500) = NULL;
        IF ISNULL(@ComputedTargetAutoReceive, 0) = 1
        BEGIN
            SET @AutoReceivedAt = SYSDATETIME();
            SET @AutoReceivedByResourceId = @ResourceId;
            SET @AutoReceivedRemark = 'Otomatis: auto-terima';
        END

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

            -- Prompt 17: step ber-bundle pertama TIDAK LAGI bebas prasyarat -- Bundling
            -- (disisipkan otomatis, sort_order lebih kecil dari semua step station) selalu
            -- jadi "step sebelumnya" untuk step station pertama, jadi aturan generik di bawah
            -- berlaku ke SEMUA step ber-bundle is_bundling = 0 tanpa pengecualian.
            DECLARE @FirstStationBundleSort INT;
            SELECT @FirstStationBundleSort = MIN(sort_order)
            FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1 AND is_bundling = 0;

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

            -- Validasi "bundle ditugaskan ke line lain" hanya berlaku di step station PERTAMA
            -- (bukan lagi step ber-bundle pertama overall -- itu sekarang Bundling). Prompt 27:
            -- kalau stasiun pengirim TIDAK terkunci ke resource bawaan (@ActingAllowResourceChange
            -- = 1), match persis dilewati -- operator sesi manapun di divisi ini (sudah dijamin
            -- lewat @ActingDivisionId + daftar operator stasiun) boleh mengirim hasil biarpun
            -- beda dari resource yang ditugaskan ke bundle. Stasiun terkunci (atau pemanggil non-
            -- stasiun, @ActingAllowResourceChange NULL) tetap wajib match persis seperti semula.
            IF @SortOrder = @FirstStationBundleSort AND ISNULL(@ActingAllowResourceChange, 0) = 0
            BEGIN
                DECLARE @BundleResourceId INT;
                SELECT @BundleResourceId = resource_id FROM bundles WHERE bundle_id = @BundleId;

                IF @BundleResourceId IS NOT NULL AND (@ResourceId IS NULL OR @BundleResourceId <> @ResourceId)
                BEGIN
                    RAISERROR('Bundle ini ditugaskan ke line lain.', 16, 1);
                    RETURN;
                END
            END

            -- Prompt 14: validasi kuota qty (boleh lewat lewat @ConfirmExceed = 1). Prompt 17:
            -- tidak perlu lagi cabang khusus bundles.qty -- qty masuk step station pertama
            -- otomatis = SUM qty_ok baris step Bundling (nilainya memang qty bundle).
            DECLARE @QtyMasuk INT;
            SELECT @QtyMasuk = ISNULL(SUM(qty_ok), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @PrevArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

            SET @QtyMasuk = ISNULL(@QtyMasuk, 0);

            DECLARE @QtySudah INT;
            SELECT @QtySudah = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

            IF @ConfirmExceed = 0 AND (@QtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost) > @QtyMasuk
            BEGIN
                RAISERROR('QTY_EXCEED|Total melebihi qty masuk step ini (masuk %d, sudah tercatat %d).', 16, 1, @QtyMasuk, @QtySudah);
                RETURN;
            END

            -- Prompt 14b: kurang dari batas boleh (baris susulan menyusul), tapi lewat
            -- konfirmasi sadar juga -- simetris dengan exceed di atas.
            IF @ConfirmShort = 0 AND (@QtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost) < @QtyMasuk
            BEGIN
                DECLARE @NewTotalCreate INT = @QtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost;
                RAISERROR('QTY_SHORT|Total baru %d dari %d - serahan tidak lengkap. Sisa bisa dicatat sebagai baris susulan.', 16, 1, @NewTotalCreate, @QtyMasuk);
                RETURN;
            END
        END

        INSERT INTO article_workflow_logs (
            article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
            qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_reject_rework, qty_lost,
            remark, target_division_id, received_at, received_by_resource_id, received_remark,
            created_at, created_by
        )
        VALUES (
            @ArticleWorkflowId, @BundleId, @ArticleSizeId, @DivisionId, @ResourceId, NULL,
            @QtyOk, @QtyRejectPrint, @QtyRejectFabric, @QtyRejectSewing, @QtyRejectRework, @QtyLost,
            @Remark, @ComputedTargetDivisionId, @AutoReceivedAt, @AutoReceivedByResourceId, @AutoReceivedRemark,
            SYSDATETIME(), @UserId
        );

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        DECLARE @UpdDivisionId INT, @UpdBundleId INT, @UpdReceivedAt DATETIME2, @UpdArticleId INT,
                @UpdArticleWorkflowId INT, @UpdSortOrder INT, @UpdTargetDivisionId INT, @UpdCreatedAt DATETIME2;
        SELECT @UpdDivisionId = awl.division_id, @UpdBundleId = awl.bundle_id,
               @UpdReceivedAt = awl.received_at, @UpdArticleId = aw.article_id,
               @UpdArticleWorkflowId = awl.article_workflow_id, @UpdSortOrder = aw.sort_order,
               @UpdTargetDivisionId = awl.target_division_id, @UpdCreatedAt = awl.created_at
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id AND awl.deleted_at IS NULL;

        IF @UpdDivisionId IS NULL
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- Prompt 18: project terkunci (manual_status) menolak revisi log workflow.
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

        IF @UpdReceivedAt IS NOT NULL
        BEGIN
            RAISERROR('Log ini sudah diterima, tidak bisa diubah lagi.', 16, 1);
            RETURN;
        END

        -- Prompt 23: step terakhir artikel (tidak ada serah lanjutan) -- jendela revisi H+1.
        IF @UpdTargetDivisionId IS NULL AND CAST(SYSDATETIME() AS DATE) > CAST(DATEADD(DAY, 1, @UpdCreatedAt) AS DATE)
        BEGIN
            RAISERROR('Batas waktu revisi (H+1) untuk step terakhir ini sudah lewat.', 16, 1);
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
           OR @QtyRejectRework < 0 OR @QtyLost < 0
        BEGIN
            RAISERROR('Qty tidak boleh negatif.', 16, 1);
            RETURN;
        END

        IF @QtyOk = 0 AND @QtyRejectPrint = 0 AND @QtyRejectFabric = 0 AND @QtyRejectSewing = 0
           AND @QtyRejectRework = 0 AND @QtyLost = 0
        BEGIN
            RAISERROR('Total qty tidak boleh 0. Isi minimal satu kategori (OK/reject/hilang).', 16, 1);
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
            SELECT @UpdQtySudah = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @UpdArticleWorkflowId AND bundle_id = @UpdBundleId
              AND deleted_at IS NULL AND workflow_log_id <> @Id;

            IF @ConfirmExceed = 0 AND (@UpdQtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost) > @UpdQtyMasuk
            BEGIN
                RAISERROR('QTY_EXCEED|Total melebihi qty masuk step ini (masuk %d, sudah tercatat %d).', 16, 1, @UpdQtyMasuk, @UpdQtySudah);
                RETURN;
            END

            IF @ConfirmShort = 0 AND (@UpdQtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost) < @UpdQtyMasuk
            BEGIN
                DECLARE @NewTotalUpdate INT = @UpdQtySudah + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost;
                RAISERROR('QTY_SHORT|Total baru %d dari %d - serahan tidak lengkap. Sisa bisa dicatat sebagai baris susulan.', 16, 1, @NewTotalUpdate, @UpdQtyMasuk);
                RETURN;
            END
        END

        UPDATE article_workflow_logs
        SET qty_ok = @QtyOk,
            qty_reject_print = @QtyRejectPrint,
            qty_reject_fabric = @QtyRejectFabric,
            qty_reject_sewing = @QtyRejectSewing,
            qty_reject_rework = @QtyRejectRework,
            qty_lost = @QtyLost,
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

        DECLARE @RecTargetDivisionId INT, @RecReceivedAt DATETIME2, @RecArticleId INT;
        SELECT @RecTargetDivisionId = awl.target_division_id, @RecReceivedAt = awl.received_at, @RecArticleId = aw.article_id
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @Id;

        -- Prompt 18: project terkunci (manual_status) menolak penerimaan log workflow.
        DECLARE @LockStatus_Receive VARCHAR(20), @LockReason_Receive VARCHAR(255);
        SELECT @LockStatus_Receive = p.manual_status, @LockReason_Receive = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @RecArticleId;

        IF @LockStatus_Receive IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Receive VARCHAR(30) = CASE @LockStatus_Receive
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Receive END;
            DECLARE @LockSuffix_Receive VARCHAR(300) = CASE WHEN @LockReason_Receive IS NOT NULL AND LTRIM(RTRIM(@LockReason_Receive)) <> ''
                THEN ' (Alasan: ' + @LockReason_Receive + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Receive, @LockSuffix_Receive);
            RETURN;
        END

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

        -- Prompt 18: project terkunci (manual_status) menolak pembatalan penerimaan.
        DECLARE @LockStatus_Unreceive VARCHAR(20), @LockReason_Unreceive VARCHAR(255);
        SELECT @LockStatus_Unreceive = p.manual_status, @LockReason_Unreceive = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @UnrArticleId;

        IF @LockStatus_Unreceive IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Unreceive VARCHAR(30) = CASE @LockStatus_Unreceive
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Unreceive END;
            DECLARE @LockSuffix_Unreceive VARCHAR(300) = CASE WHEN @LockReason_Unreceive IS NOT NULL AND LTRIM(RTRIM(@LockReason_Unreceive)) <> ''
                THEN ' (Alasan: ' + @LockReason_Unreceive + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Unreceive, @LockSuffix_Unreceive);
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
        DECLARE @CancelDivisionId INT, @CancelReceivedAt DATETIME2, @CancelTargetDivisionId INT, @CancelCreatedAt DATETIME2;
        SELECT @CancelDivisionId = division_id, @CancelReceivedAt = received_at,
               @CancelTargetDivisionId = target_division_id, @CancelCreatedAt = created_at
        FROM article_workflow_logs
        WHERE workflow_log_id = @Id AND deleted_at IS NULL;

        IF @CancelDivisionId IS NULL
        BEGIN
            RAISERROR('Baris serah tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- Prompt 23: baris step terakhir (tanpa tujuan serah) -- jendela H+1 alih-alih guard
        -- received_at (baris ini tidak pernah "diterima").
        IF @CancelTargetDivisionId IS NULL
        BEGIN
            IF CAST(SYSDATETIME() AS DATE) > CAST(DATEADD(DAY, 1, @CancelCreatedAt) AS DATE)
            BEGIN
                RAISERROR('Batas waktu pembatalan (H+1) untuk step terakhir ini sudah lewat.', 16, 1);
                RETURN;
            END
        END
        ELSE IF @CancelReceivedAt IS NOT NULL
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
            delete_reason = CASE WHEN @CancelTargetDivisionId IS NULL
                THEN 'Batal step terakhir (stasiun)' ELSE 'Batal serah (stasiun)' END
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
           OR @QtyRejectRework < 0 OR @QtyLost < 0
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

        -- Fix (pasca Prompt 34): REVISE_HANDOVER kini JUGA memicu auto-terima -- kalau step
        -- penerima (@NewTargetDivisionId) ber-auto_receive = 1, baris yang direvisi ini
        -- langsung diterima lagi dalam transaksi yang sama. Kasus nyata: Trim membatalkan
        -- terima (UNRECEIVE) baris QC yang salah input, QC perbaiki lewat Revisi -- baris
        -- harus otomatis WIP lagi di Trim tanpa Trim menekan Terima manual kedua kalinya.
        -- Tidak retroaktif ke baris lain -- hanya baris @Id ini, dalam transaksi ini saja.
        -- Ini membalik larangan eksplisit di prompt_34_auto_receive.md ("REVISE_HANDOVER
        -- TIDAK men-trigger auto-terima") atas permintaan pengguna setelah skenario ini
        -- ditemukan di lapangan.
        DECLARE @RevAutoReceive BIT = 0;
        SELECT TOP 1 @RevAutoReceive = ISNULL(auto_receive, 0)
        FROM article_workflows
        WHERE article_id = @RevArticleId AND division_id = @NewTargetDivisionId AND deleted_at IS NULL;

        UPDATE article_workflow_logs
        SET qty_ok = @QtyOk,
            qty_reject_print = @QtyRejectPrint,
            qty_reject_fabric = @QtyRejectFabric,
            qty_reject_sewing = @QtyRejectSewing,
            qty_reject_rework = @QtyRejectRework,
            qty_lost = @QtyLost,
            remark = @Remark,
            target_division_id = @NewTargetDivisionId,
            resource_id = ISNULL(@ResourceId, resource_id),
            received_at = CASE WHEN @RevAutoReceive = 1 THEN SYSDATETIME() ELSE NULL END,
            received_by_resource_id = CASE WHEN @RevAutoReceive = 1 THEN ISNULL(@ResourceId, resource_id) ELSE NULL END,
            received_remark = CASE WHEN @RevAutoReceive = 1 THEN 'Otomatis: auto-terima' ELSE NULL END,
            updated_at = SYSDATETIME(),
            updated_by = @UserId,
            updated_by_resource_id = @UpdatedByResourceId
        WHERE workflow_log_id = @Id;
    END

    ELSE IF @Action = 'ADJUST'
    BEGIN
        DECLARE @AdjDivisionId INT, @AdjRequiresBundle BIT, @AdjArticleId INT, @AdjSortOrder INT, @AdjIsBundling BIT;

        SELECT @AdjDivisionId = division_id, @AdjRequiresBundle = requires_bundle,
               @AdjArticleId = article_id, @AdjSortOrder = sort_order, @AdjIsBundling = is_bundling
        FROM article_workflows
        WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL;

        IF @AdjDivisionId IS NULL
        BEGIN
            RAISERROR('Step workflow tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @AdjRequiresBundle = 0 OR @AdjIsBundling = 1
        BEGIN
            RAISERROR('Penyesuaian hanya berlaku untuk step ber-bundle.', 16, 1);
            RETURN;
        END

        IF @BundleId IS NULL OR NOT EXISTS (
            SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND article_id = @AdjArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Bundle tidak sesuai dengan artikel step ini.', 16, 1);
            RETURN;
        END

        IF @ResourceId IS NULL OR NOT EXISTS (
            SELECT 1 FROM resources WHERE resource_id = @ResourceId AND division_id = @AdjDivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pelaksana penyesuaian tidak valid untuk divisi ini.', 16, 1);
            RETURN;
        END

        -- Prompt 18: project terkunci (manual_status) menolak penyesuaian juga.
        DECLARE @LockStatus_Adjust VARCHAR(20), @LockReason_Adjust VARCHAR(255);
        SELECT @LockStatus_Adjust = p.manual_status, @LockReason_Adjust = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @AdjArticleId;

        IF @LockStatus_Adjust IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Adjust VARCHAR(30) = CASE @LockStatus_Adjust
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Adjust END;
            DECLARE @LockSuffix_Adjust VARCHAR(300) = CASE WHEN @LockReason_Adjust IS NOT NULL AND LTRIM(RTRIM(@LockReason_Adjust)) <> ''
                THEN ' (Alasan: ' + @LockReason_Adjust + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Adjust, @LockSuffix_Adjust);
            RETURN;
        END

        IF @ActingDivisionId IS NOT NULL AND @ActingDivisionId <> @AdjDivisionId
        BEGIN
            RAISERROR('Penyesuaian hanya boleh dilakukan divisi pemilik step ini.', 16, 1);
            RETURN;
        END

        IF @QtyOk < 0
        BEGIN
            RAISERROR('Qty OK tidak boleh dikurangi lewat penyesuaian.', 16, 1);
            RETURN;
        END

        DECLARE @AdjTotal INT = @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost;
        IF @AdjTotal <> 0
        BEGIN
            RAISERROR('Total penyesuaian harus 0.', 16, 1);
            RETURN;
        END

        IF @QtyOk = 0 AND @QtyRejectPrint = 0 AND @QtyRejectFabric = 0 AND @QtyRejectSewing = 0
           AND @QtyRejectRework = 0 AND @QtyLost = 0
        BEGIN
            RAISERROR('Minimal satu nilai penyesuaian harus diisi.', 16, 1);
            RETURN;
        END

        -- Saldo per kategori reject/lost = SUM kolom itu atas semua baris hidup (step, bundle)
        -- ini -- tidak boleh negatif setelah penyesuaian.
        DECLARE @SaldoRejectPrint INT, @SaldoRejectFabric INT, @SaldoRejectSewing INT,
                @SaldoRejectRework INT, @SaldoLost INT;
        SELECT @SaldoRejectPrint = ISNULL(SUM(qty_reject_print), 0),
               @SaldoRejectFabric = ISNULL(SUM(qty_reject_fabric), 0),
               @SaldoRejectSewing = ISNULL(SUM(qty_reject_sewing), 0),
               @SaldoRejectRework = ISNULL(SUM(qty_reject_rework), 0),
               @SaldoLost = ISNULL(SUM(qty_lost), 0)
        FROM article_workflow_logs
        WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

        -- RAISERROR TIDAK menerima ekspresi (mis. -@QtyRejectPrint) sebagai argumen --
        -- harus variabel/literal polos, jadi nilai negasi ditampung dulu ke variabel lokal.
        DECLARE @NegQtyRejectPrint INT = -@QtyRejectPrint, @NegQtyRejectFabric INT = -@QtyRejectFabric,
                @NegQtyRejectSewing INT = -@QtyRejectSewing, @NegQtyRejectRework INT = -@QtyRejectRework,
                @NegQtyLost INT = -@QtyLost;

        IF @SaldoRejectPrint + @QtyRejectPrint < 0
        BEGIN
            RAISERROR('Saldo Reject Print hanya %d, tidak bisa dikurangi %d.', 16, 1, @SaldoRejectPrint, @NegQtyRejectPrint);
            RETURN;
        END
        IF @SaldoRejectFabric + @QtyRejectFabric < 0
        BEGIN
            RAISERROR('Saldo Reject Bahan hanya %d, tidak bisa dikurangi %d.', 16, 1, @SaldoRejectFabric, @NegQtyRejectFabric);
            RETURN;
        END
        IF @SaldoRejectSewing + @QtyRejectSewing < 0
        BEGIN
            RAISERROR('Saldo Reject Jahit hanya %d, tidak bisa dikurangi %d.', 16, 1, @SaldoRejectSewing, @NegQtyRejectSewing);
            RETURN;
        END
        IF @SaldoRejectRework + @QtyRejectRework < 0
        BEGIN
            RAISERROR('Saldo Reject Rework hanya %d, tidak bisa dikurangi %d.', 16, 1, @SaldoRejectRework, @NegQtyRejectRework);
            RETURN;
        END
        IF @SaldoLost + @QtyLost < 0
        BEGIN
            RAISERROR('Saldo Hilang hanya %d, tidak bisa dikurangi %d.', 16, 1, @SaldoLost, @NegQtyLost);
            RETURN;
        END

        -- Divisi tujuan terkunci sesuai urutan workflow (sama seperti @ComputedTargetDivisionId
        -- di CREATE) -- @TargetDivisionId dari pemanggil sekadar wajib diisi (bukti UI sudah
        -- menampilkannya), nilai final tetap dihitung ulang di sini, bukan dipercaya mentah.
        DECLARE @AdjTargetDivisionId INT = NULL;
        IF @QtyOk > 0
        BEGIN
            SELECT TOP 1 @AdjTargetDivisionId = division_id
            FROM article_workflows
            WHERE article_id = @AdjArticleId AND deleted_at IS NULL AND sort_order > @AdjSortOrder
            ORDER BY sort_order ASC;

            IF @AdjTargetDivisionId IS NOT NULL AND @TargetDivisionId IS NULL
            BEGIN
                RAISERROR('Divisi tujuan wajib diisi kalau Qty OK bertambah.', 16, 1);
                RETURN;
            END
        END

        INSERT INTO article_workflow_logs (
            article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
            qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_reject_rework, qty_lost,
            remark, target_division_id, log_type, created_at, created_by
        )
        VALUES (
            @ArticleWorkflowId, @BundleId, NULL, @AdjDivisionId, @ResourceId, NULL,
            @QtyOk, @QtyRejectPrint, @QtyRejectFabric, @QtyRejectSewing, @QtyRejectRework, @QtyLost,
            @Remark, @AdjTargetDivisionId, 'ADJUSTMENT', SYSDATETIME(), @UserId
        );

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
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

-- Fix: "Cetak Reject" -- cetak nota reject untuk SATU baris article_workflow_logs tertentu
-- (per baris/per workflow, bukan per bundle atau agregat), dipakai tombol yang muncul di
-- timeline BundleScanCard (station) dan tab Riwayat ReportBundle -- HANYA ditampilkan client
-- kalau total reject+hilang baris itu > 0 (ditegakkan ulang di sini). Payload dirakit ulang
-- dari data terkini article_workflow_logs (bukan dikirim client) -- pola sama dengan
-- SIS_Bundle_ReprintLabel/SIS_Pack_ReprintLabel. @Copies (default 1) jumlah lembar dicetak.
CREATE OR ALTER PROCEDURE SIS_WorkflowLog_PrintReject
    @WorkflowLogId INT,
    @Copies        INT = 1,
    @UserId        INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM article_workflow_logs WHERE workflow_log_id = @WorkflowLogId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Baris log tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @Copies IS NULL OR @Copies < 1
    BEGIN
        RAISERROR('Jumlah label harus minimal 1.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM article_workflow_logs
        WHERE workflow_log_id = @WorkflowLogId AND deleted_at IS NULL
          AND (qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost) > 0
    )
    BEGIN
        RAISERROR('Baris ini tidak memiliki reject.', 16, 1);
        RETURN;
    END

    -- Size baris ber-bundle melekat di bundles (asz2/spd2), baris non-bundle di
    -- article_workflow_logs.article_size_id sendiri (asz/spd) -- pola sama dengan
    -- SIS_Pack_Manage COALESCE size lookup.
    DECLARE @Payload NVARCHAR(MAX) = (
        SELECT
            awl.workflow_log_id AS workflow_log_id,
            bd.serial AS bundle_serial,
            bd.bundle_no AS bundle_no,
            pr.bundle_letter AS bundle_letter,
            pr.project_name AS project_name,
            a.article_name AS article_name,
            COALESCE(spd.size_name, spd2.size_name) AS size_name,
            aw.step_name AS step_name,
            d.division_name AS division_name,
            awl.qty_reject_print AS qty_reject_print,
            awl.qty_reject_fabric AS qty_reject_fabric,
            awl.qty_reject_sewing AS qty_reject_sewing,
            awl.qty_reject_rework AS qty_reject_rework,
            awl.qty_lost AS qty_lost,
            awl.remark AS remark,
            r.resource_name AS resource_name,
            awl.created_at AS created_at
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        INNER JOIN articles a ON a.article_id = aw.article_id
        INNER JOIN projects pr ON pr.project_id = a.project_id
        LEFT JOIN bundles bd ON bd.bundle_id = awl.bundle_id
        LEFT JOIN divisions d ON d.division_id = awl.division_id
        LEFT JOIN resources r ON r.resource_id = awl.resource_id
        LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
        LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN article_sizes asz2 ON asz2.article_size_id = bd.article_size_id
        LEFT JOIN size_pack_details spd2 ON spd2.size_pack_detail_id = asz2.size_pack_detail_id
        WHERE awl.workflow_log_id = @WorkflowLogId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    DECLARE @Copy INT = 0;
    DECLARE @LastPrintJobId INT;
    WHILE @Copy < @Copies
    BEGIN
        INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
        VALUES ('REJECT_NOTE', @WorkflowLogId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

        SET @LastPrintJobId = CAST(SCOPE_IDENTITY() AS INT);
        SET @Copy += 1;
    END

    SELECT @LastPrintJobId AS NewPrintJobId;
END;
GO

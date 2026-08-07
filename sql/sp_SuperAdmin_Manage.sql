-- Prompt 29: Module Super Admin -- koreksi data langsung (bundle & workflow log) yang
-- melewati guard normal SIS_Bundle_Manage/SIS_WorkflowLog_Manage. Dipakai jarang, hanya
-- oleh user terpilih (module SUPER_ADMIN, tidak di-auto-assign -- lihat
-- sql/seed_super_admin_module.sql). Semua koreksi tetap soft-delete-aware dan meninggalkan
-- jejak audit (updated_at/updated_by, deleted_at/deleted_by/delete_reason).
--
-- Mutasi lewat SIS_SuperAdmin_Manage (@Action):
--   BUNDLE_UPDATE -- ubah size/qty/bundle_no/serial bundle langsung, walau bundle sudah
--     punya log (bypass guard "sudah diproses" di SIS_Bundle_Manage). TIDAK menyentuh log
--     yang sudah ada (beda dengan SIS_Bundle_Manage UPDATE yang menyinkronkan qty_ok log
--     Bundling) -- perubahan qty/size di sini murni koreksi data induk bundle.
--   BUNDLE_DELETE -- hanya kalau bundle tidak punya log hidup sama sekali (lebih ketat dari
--     SIS_Bundle_Manage DELETE yang punya jendela 1 jam) -- kalau sudah ada log, tolak dan minta
--     hapus lognya dulu (lewat LOG_DELETE) atau batalkan.
--   LOG_UPDATE -- ubah keenam qty + remark baris log HIDUP APA PUN (NORMAL/ADJUSTMENT, sudah
--     diterima atau belum) -- TANPA validasi kuota, TANPA guard received_at (beda dari
--     SIS_WorkflowLog_Manage UPDATE). Validasi minimal saja: baris ADJUSTMENT (mutasi antar
--     kategori, dari SIS_WorkflowLog_Manage ADJUST) -- jumlah keenam qty tetap harus 0 dan
--     qty_ok tidak boleh negatif (invarian log_type ADJUSTMENT dijaga). Baris NORMAL -- qty
--     tidak boleh negatif.
--   LOG_DELETE -- soft delete + alasan wajib, TANPA guard received/dipakai-step-berikutnya
--     (beda dari SIS_WorkflowLog_Manage DELETE).
--
-- Fitur "batalkan status diterima" SENGAJA tidak dibuat -- sudah ada Batal Terima di stasiun
-- (SIS_WorkflowLog_Manage action UNRECEIVE).
--
-- Read: SIS_SuperAdmin_BundleSearch (@Search), SIS_SuperAdmin_BundleDetail (@BundleId) dan
-- SIS_SuperAdmin_LogEditInfo (@WorkflowLogId) -- lihat masing-masing di bawah.
--
-- Prompt 36 -- fitur BARU "Edit Timeline & Info Bundle" di halaman /b/{serial} dan
-- /report-bundle (tab Riwayat), dipakai user SUPER_ADMIN langsung dari tampilan bundle,
-- BEDA dengan LOG_UPDATE/BUNDLE_UPDATE di atas (koreksi bebas tanpa validasi, dari panel
-- /super-admin, TERMASUK bisa ubah serial/bundle_no) -- makanya action BARU, bukan
-- perluasan LOG_UPDATE/BUNDLE_UPDATE:
--   EDIT_LOG -- ubah qty (enam kategori) + pelaksana (resource_id) + remark baris log
--     BER-BUNDLE hidup. WAJIB validasi arah bawah (hard block, TANPA override): total qty_ok
--     baru step ini tidak boleh lebih kecil dari total step ber-bundle berikutnya (bundle
--     sama). Arah atas (qty tidak boleh diam-diam melebihi qty masuk dari step sebelumnya /
--     qty bundle) tetap pola QTY_EXCEED| + @ConfirmExceed, sama seperti SIS_WorkflowLog_Manage.
--   EDIT_BUNDLE -- ubah ukuran/qty/line(resource_id)/penjahit(employee_id) bundle hidup,
--     SEKALIGUS menyinkronkan qty_ok baris log Bundling bundle ini. Qty baru WAJIB validasi
--     arah bawah yang sama (>= total step ber-bundle setelah Bundling). Serial & bundle_no
--     TIDAK PERNAH disentuh aksi ini (beda dengan BUNDLE_UPDATE).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_SuperAdmin_Manage
    @Action          VARCHAR(20),
    @BundleId        INT = NULL,
    @ArticleSizeId   INT = NULL,
    @Qty             INT = NULL,
    @BundleNo        INT = NULL,
    @Serial          VARCHAR(20) = NULL,
    @WorkflowLogId   INT = NULL,
    @QtyOk           INT = 0,
    @QtyRejectPrint  INT = 0,
    @QtyRejectFabric INT = 0,
    @QtyRejectSewing INT = 0,
    @QtyRejectRework INT = 0,
    @QtyLost         INT = 0,
    @Remark          VARCHAR(500) = NULL,
    @DeleteReason    VARCHAR(255) = NULL,
    -- Prompt 36: EDIT_LOG (pelaksana baris log) & EDIT_BUNDLE (line).
    @ResourceId      INT = NULL,
    -- Prompt 36: EDIT_BUNDLE (penjahit, pola cascading Prompt 32).
    @EmployeeId      INT = NULL,
    -- Prompt 36: EDIT_LOG arah atas (pola QTY_EXCEED| yang sudah ada).
    @ConfirmExceed   BIT = 0,
    @UserId          INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'BUNDLE_UPDATE'
    BEGIN
        DECLARE @UpdArticleId INT;
        SELECT @UpdArticleId = article_id FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL;

        IF @UpdArticleId IS NULL
        BEGIN
            RAISERROR('Bundle tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @ArticleSizeId IS NULL OR NOT EXISTS (
            SELECT 1 FROM article_sizes
            WHERE article_size_id = @ArticleSizeId AND article_id = @UpdArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Ukuran tidak sesuai dengan artikel bundle ini.', 16, 1);
            RETURN;
        END

        IF @Qty IS NULL OR @Qty <= 0
        BEGIN
            RAISERROR('Qty bundle harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF @Serial IS NULL OR LTRIM(RTRIM(@Serial)) = ''
        BEGIN
            RAISERROR('Serial wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM bundles WHERE serial = @Serial AND bundle_id <> @BundleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Serial sudah dipakai bundle lain.', 16, 1);
            RETURN;
        END

        IF @BundleNo IS NULL OR @BundleNo <= 0
        BEGIN
            RAISERROR('Nomor bundle wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @UpdProjectId INT;
        SELECT @UpdProjectId = project_id FROM articles WHERE article_id = @UpdArticleId;

        IF EXISTS (
            SELECT 1 FROM bundles b
            INNER JOIN articles a ON a.article_id = b.article_id
            WHERE a.project_id = @UpdProjectId AND b.bundle_no = @BundleNo
              AND b.bundle_id <> @BundleId AND b.deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Nomor bundle sudah dipakai bundle lain di project ini.', 16, 1);
            RETURN;
        END

        UPDATE bundles
        SET article_size_id = @ArticleSizeId,
            qty = @Qty,
            bundle_no = @BundleNo,
            serial = @Serial,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE bundle_id = @BundleId AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'BUNDLE_DELETE'
    BEGIN
        IF @DeleteReason IS NULL OR LTRIM(RTRIM(@DeleteReason)) = ''
        BEGIN
            RAISERROR('Alasan hapus wajib diisi.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Bundle tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM article_workflow_logs WHERE bundle_id = @BundleId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Bundle sudah punya log workflow -- hapus lognya dulu atau batalkan.', 16, 1);
            RETURN;
        END

        UPDATE bundles
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            delete_reason = @DeleteReason
        WHERE bundle_id = @BundleId AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'LOG_UPDATE'
    BEGIN
        DECLARE @UpdLogType VARCHAR(15);
        SELECT @UpdLogType = log_type FROM article_workflow_logs
        WHERE workflow_log_id = @WorkflowLogId AND deleted_at IS NULL;

        IF @UpdLogType IS NULL
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @UpdLogType = 'ADJUSTMENT'
        BEGIN
            IF @QtyOk < 0
            BEGIN
                RAISERROR('Qty OK tidak boleh negatif.', 16, 1);
                RETURN;
            END

            DECLARE @UpdAdjTotal INT = @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost;
            IF @UpdAdjTotal <> 0
            BEGIN
                RAISERROR('Baris penyesuaian: total keenam qty tetap harus 0.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0
               OR @QtyRejectRework < 0 OR @QtyLost < 0
            BEGIN
                RAISERROR('Qty tidak boleh negatif.', 16, 1);
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
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE workflow_log_id = @WorkflowLogId AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'LOG_DELETE'
    BEGIN
        IF @DeleteReason IS NULL OR LTRIM(RTRIM(@DeleteReason)) = ''
        BEGIN
            RAISERROR('Alasan hapus wajib diisi.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM article_workflow_logs WHERE workflow_log_id = @WorkflowLogId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            delete_reason = @DeleteReason
        WHERE workflow_log_id = @WorkflowLogId AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'EDIT_LOG'
    BEGIN
        DECLARE @EditArticleWorkflowId INT, @EditBundleId INT, @EditDivisionId INT,
                @EditArticleId INT, @EditSortOrder INT, @EditLogType VARCHAR(15);
        SELECT @EditArticleWorkflowId = awl.article_workflow_id, @EditBundleId = awl.bundle_id,
               @EditDivisionId = awl.division_id, @EditArticleId = aw.article_id,
               @EditSortOrder = aw.sort_order, @EditLogType = awl.log_type
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.workflow_log_id = @WorkflowLogId AND awl.deleted_at IS NULL;

        IF @EditArticleWorkflowId IS NULL
        BEGIN
            RAISERROR('Log tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @EditBundleId IS NULL
        BEGIN
            RAISERROR('Log ini bukan bagian dari bundle.', 16, 1);
            RETURN;
        END

        IF @EditLogType = 'ADJUSTMENT'
        BEGIN
            IF @QtyOk < 0
            BEGIN
                RAISERROR('Qty OK tidak boleh negatif.', 16, 1);
                RETURN;
            END

            DECLARE @EditAdjTotal INT = @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost;
            IF @EditAdjTotal <> 0
            BEGIN
                RAISERROR('Baris penyesuaian: total keenam qty tetap harus 0.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            IF @QtyOk < 0 OR @QtyRejectPrint < 0 OR @QtyRejectFabric < 0 OR @QtyRejectSewing < 0
               OR @QtyRejectRework < 0 OR @QtyLost < 0
            BEGIN
                RAISERROR('Qty tidak boleh negatif.', 16, 1);
                RETURN;
            END

            -- Fix: total keenam qty tidak boleh 0 (baris NORMAL) -- pola sama dengan
            -- SIS_WorkflowLog_Manage CREATE/UPDATE. Baris ADJUSTMENT dikecualikan (invariannya
            -- justru total HARUS 0, ditegakkan di atas).
            IF @QtyOk = 0 AND @QtyRejectPrint = 0 AND @QtyRejectFabric = 0 AND @QtyRejectSewing = 0
               AND @QtyRejectRework = 0 AND @QtyLost = 0
            BEGIN
                RAISERROR('Total qty tidak boleh 0. Isi minimal satu kategori (OK/reject/hilang).', 16, 1);
                RETURN;
            END
        END

        -- Fix: Pelaksana wajib diisi (beda dari LOG_UPDATE bebas di panel /super-admin).
        IF @ResourceId IS NULL
        BEGIN
            RAISERROR('Pelaksana wajib diisi.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM resources WHERE resource_id = @ResourceId AND division_id = @EditDivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pelaksana tidak sesuai divisi step ini.', 16, 1);
            RETURN;
        END

        -- Arah bawah (hard block, TANPA override): total qty_ok baru step ini (baris yang
        -- diedit pakai nilai baru) tidak boleh < total step ber-bundle berikutnya (bundle sama).
        DECLARE @EditNextArticleWorkflowId INT;
        SELECT TOP 1 @EditNextArticleWorkflowId = article_workflow_id
        FROM article_workflows
        WHERE article_id = @EditArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 1 AND sort_order > @EditSortOrder
        ORDER BY sort_order ASC;

        IF @EditNextArticleWorkflowId IS NOT NULL
        BEGIN
            DECLARE @EditNewSumQtyOk INT, @EditNextTotal INT;
            SELECT @EditNewSumQtyOk = ISNULL(SUM(qty_ok), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @EditArticleWorkflowId AND bundle_id = @EditBundleId
              AND deleted_at IS NULL AND workflow_log_id <> @WorkflowLogId;
            SET @EditNewSumQtyOk = ISNULL(@EditNewSumQtyOk, 0) + @QtyOk;

            SELECT @EditNextTotal = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @EditNextArticleWorkflowId AND bundle_id = @EditBundleId AND deleted_at IS NULL;

            IF @EditNewSumQtyOk < @EditNextTotal
            BEGIN
                RAISERROR('Qty step ini (%d) tidak boleh lebih kecil dari total step berikutnya (%d). Edit step berikutnya terlebih dahulu.', 16, 1, @EditNewSumQtyOk, @EditNextTotal);
                RETURN;
            END
        END

        -- Arah atas (boleh lewat konfirmasi @ConfirmExceed, pola QTY_EXCEED| sama dengan
        -- SIS_WorkflowLog_Manage): total baru step ini tidak boleh diam-diam melebihi qty
        -- masuk (qty_ok step ber-bundle sebelumnya, atau qty bundle kalau step ini Bundling).
        DECLARE @EditPrevArticleWorkflowId INT;
        SELECT TOP 1 @EditPrevArticleWorkflowId = article_workflow_id
        FROM article_workflows
        WHERE article_id = @EditArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 1 AND sort_order < @EditSortOrder
        ORDER BY sort_order DESC;

        DECLARE @EditQtyMasuk INT;
        IF @EditPrevArticleWorkflowId IS NOT NULL
            SELECT @EditQtyMasuk = ISNULL(SUM(qty_ok), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @EditPrevArticleWorkflowId AND bundle_id = @EditBundleId AND deleted_at IS NULL;
        ELSE
            SELECT @EditQtyMasuk = qty FROM bundles WHERE bundle_id = @EditBundleId;

        SET @EditQtyMasuk = ISNULL(@EditQtyMasuk, 0);

        DECLARE @EditQtySudahExcl INT;
        SELECT @EditQtySudahExcl = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost), 0)
        FROM article_workflow_logs
        WHERE article_workflow_id = @EditArticleWorkflowId AND bundle_id = @EditBundleId
          AND deleted_at IS NULL AND workflow_log_id <> @WorkflowLogId;

        DECLARE @EditNewTotalThis INT = @EditQtySudahExcl + @QtyOk + @QtyRejectPrint + @QtyRejectFabric + @QtyRejectSewing + @QtyRejectRework + @QtyLost;

        IF @ConfirmExceed = 0 AND @EditNewTotalThis > @EditQtyMasuk
        BEGIN
            RAISERROR('QTY_EXCEED|Total melebihi qty masuk step ini (masuk %d, sudah tercatat %d).', 16, 1, @EditQtyMasuk, @EditQtySudahExcl);
            RETURN;
        END

        UPDATE article_workflow_logs
        SET qty_ok = @QtyOk,
            qty_reject_print = @QtyRejectPrint,
            qty_reject_fabric = @QtyRejectFabric,
            qty_reject_sewing = @QtyRejectSewing,
            qty_reject_rework = @QtyRejectRework,
            qty_lost = @QtyLost,
            resource_id = @ResourceId,
            remark = @Remark,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE workflow_log_id = @WorkflowLogId AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'EDIT_BUNDLE'
    BEGIN
        DECLARE @EbArticleId INT;
        SELECT @EbArticleId = article_id FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL;

        IF @EbArticleId IS NULL
        BEGIN
            RAISERROR('Bundle tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @ArticleSizeId IS NULL OR NOT EXISTS (
            SELECT 1 FROM article_sizes
            WHERE article_size_id = @ArticleSizeId AND article_id = @EbArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Ukuran tidak sesuai dengan artikel bundle ini.', 16, 1);
            RETURN;
        END

        IF @Qty IS NULL OR @Qty <= 0
        BEGIN
            RAISERROR('Qty bundle harus lebih dari 0.', 16, 1);
            RETURN;
        END

        -- Line/penjahit, pola cascading Prompt 32 (validasi hanya kalau @EmployeeId diisi).
        IF @EmployeeId IS NOT NULL
        BEGIN
            IF @ResourceId IS NULL
            BEGIN
                RAISERROR('Pilih line terlebih dahulu.', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM employees
                WHERE employee_id = @EmployeeId AND resource_id = @ResourceId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Penjahit bukan anggota line ini.', 16, 1);
                RETURN;
            END
        END

        -- Arah bawah (hard block, TANPA override): qty bundle baru tidak boleh lebih kecil
        -- dari total step ber-bundle setelah Bundling (bundle ini).
        DECLARE @EbBundlingArticleWorkflowId INT, @EbBundlingSortOrder INT;
        SELECT @EbBundlingArticleWorkflowId = article_workflow_id, @EbBundlingSortOrder = sort_order
        FROM article_workflows
        WHERE article_id = @EbArticleId AND deleted_at IS NULL AND is_bundling = 1;

        DECLARE @EbNextArticleWorkflowId INT;
        IF @EbBundlingArticleWorkflowId IS NOT NULL
            SELECT TOP 1 @EbNextArticleWorkflowId = article_workflow_id
            FROM article_workflows
            WHERE article_id = @EbArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 1 AND sort_order > @EbBundlingSortOrder
            ORDER BY sort_order ASC;

        IF @EbNextArticleWorkflowId IS NOT NULL
        BEGIN
            DECLARE @EbNextTotal INT;
            SELECT @EbNextTotal = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost), 0)
            FROM article_workflow_logs
            WHERE article_workflow_id = @EbNextArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

            IF @Qty < @EbNextTotal
            BEGIN
                RAISERROR('Qty bundle (%d) tidak boleh lebih kecil dari total step berikutnya (%d). Edit step berikutnya terlebih dahulu.', 16, 1, @Qty, @EbNextTotal);
                RETURN;
            END
        END

        UPDATE bundles
        SET article_size_id = @ArticleSizeId,
            qty = @Qty,
            resource_id = @ResourceId,
            employee_id = @EmployeeId,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE bundle_id = @BundleId AND deleted_at IS NULL;

        -- Qty bundle mengalir ke qty_ok log Bundling (Prompt 17) -- sinkron dalam transaksi
        -- (implisit, statement tunggal) yang sama.
        UPDATE awl
        SET awl.qty_ok = @Qty,
            awl.updated_at = SYSDATETIME(),
            awl.updated_by = @UserId
        FROM article_workflow_logs awl
        WHERE awl.article_workflow_id = @EbBundlingArticleWorkflowId AND awl.bundle_id = @BundleId AND awl.deleted_at IS NULL;
    END
    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO

-- Cari bundle hidup by serial / bundle_no / nama artikel / nama project, TOP 50 terbaru.
-- @Search kosong/NULL -> 50 bundle terbaru (tanpa filter teks), dipakai layar awal /super-admin.
CREATE OR ALTER PROCEDURE SIS_SuperAdmin_BundleSearch
    @Search VARCHAR(120) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @S VARCHAR(120) = ISNULL(LTRIM(RTRIM(@Search)), '');

    SELECT TOP 50
        b.bundle_id AS BundleId,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        b.serial AS Serial,
        p.project_name AS ProjectName,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        spd.size_name AS SizeName,
        b.qty AS Qty,
        (
            SELECT COUNT(*) FROM article_workflow_logs awl
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
        ) AS LiveLogCount
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE b.deleted_at IS NULL
      AND (
          @S = ''
          OR b.serial LIKE '%' + @S + '%'
          OR CAST(b.bundle_no AS VARCHAR(20)) LIKE '%' + @S + '%'
          OR a.article_name LIKE '%' + @S + '%'
          OR p.project_name LIKE '%' + @S + '%'
      )
    ORDER BY b.created_at DESC;
END;
GO

-- Detail satu bundle untuk panel /super-admin DAN modal "Edit Bundle" Prompt 36 (/b/{serial},
-- /report-bundle Riwayat): info bundle, opsi ukuran artikel, dan semua log hidup bundle ini.
-- 3 result set.
CREATE OR ALTER PROCEDURE SIS_SuperAdmin_BundleDetail
    @BundleId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: info bundle.
    -- Prompt 36: ResourceId/ResourceName (line) + EmployeeId/EmployeeName (penjahit) + kolom
    -- pendukung modal Edit Bundle -- LineDivisionId (divisi step ber-bundle PERTAMA setelah
    -- Bundling, dipakai fetch dropdown Line) dan LowerBound (total step ber-bundle setelah
    -- Bundling -- batas bawah qty bundle, lihat SIS_SuperAdmin_Manage EDIT_BUNDLE).
    SELECT
        b.bundle_id AS BundleId,
        b.article_id AS ArticleId,
        b.article_size_id AS ArticleSizeId,
        spd.size_name AS SizeName,
        b.serial AS Serial,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        b.qty AS Qty,
        p.project_name AS ProjectName,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        b.resource_id AS ResourceId,
        r.resource_name AS ResourceName,
        b.employee_id AS EmployeeId,
        emp.employee_name AS EmployeeName,
        lineaw.division_id AS LineDivisionId,
        ISNULL((
            SELECT SUM(awl2.qty_ok + awl2.qty_reject_print + awl2.qty_reject_fabric + awl2.qty_reject_sewing + awl2.qty_reject_rework + awl2.qty_lost)
            FROM article_workflow_logs awl2
            WHERE awl2.article_workflow_id = lineaw.article_workflow_id AND awl2.bundle_id = b.bundle_id AND awl2.deleted_at IS NULL
        ), 0) AS LowerBound
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = b.resource_id
    LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
    OUTER APPLY (
        SELECT TOP 1 aw1.article_workflow_id, aw1.division_id
        FROM article_workflows aw1
        WHERE aw1.article_id = b.article_id AND aw1.deleted_at IS NULL AND aw1.requires_bundle = 1
          AND aw1.sort_order > (
              SELECT sort_order FROM article_workflows
              WHERE article_id = b.article_id AND deleted_at IS NULL AND is_bundling = 1
          )
        ORDER BY aw1.sort_order ASC
    ) lineaw
    WHERE b.bundle_id = @BundleId AND b.deleted_at IS NULL;

    -- Result set 2: opsi ukuran artikel bundle ini (dropdown Edit Bundle).
    SELECT
        asz.article_size_id AS Id,
        spd.size_name AS SizeName
    FROM bundles b
    INNER JOIN article_sizes asz ON asz.article_id = b.article_id AND asz.deleted_at IS NULL
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE b.bundle_id = @BundleId
    ORDER BY spd.sort_order ASC;

    -- Result set 3: semua log hidup bundle ini (sama bentuk dengan
    -- SIS_WorkflowLog_ListByArticle, difilter per bundle bukan per artikel).
    SELECT awl.workflow_log_id AS Id, awl.article_workflow_id AS ArticleWorkflowId,
           aw.step_name AS StepName, aw.sort_order AS SortOrder,
           awl.bundle_id AS BundleId, b.serial AS BundleSerial,
           awl.article_size_id AS ArticleSizeId, spd2.size_name AS SizeName,
           awl.division_id AS DivisionId, d.division_name AS DivisionName,
           awl.resource_id AS ResourceId, r.resource_name AS ResourceName,
           awl.qty_ok AS QtyOk, awl.qty_reject_print AS QtyRejectPrint,
           awl.qty_reject_fabric AS QtyRejectFabric, awl.qty_reject_sewing AS QtyRejectSewing,
           awl.qty_reject_rework AS QtyRejectRework, awl.qty_lost AS QtyLost, awl.log_type AS LogType,
           awl.remark AS Remark,
           awl.target_division_id AS TargetDivisionId, td.division_name AS TargetDivisionName,
           awl.received_at AS ReceivedAt, rr.resource_name AS ReceivedByResourceName,
           awl.received_remark AS ReceivedRemark,
           awl.created_at AS CreatedAt, awl.created_by AS CreatedBy, cu.FullName AS CreatedByName,
           awl.updated_at AS UpdatedAt, uu.FullName AS UpdatedByName, ur.resource_name AS UpdatedByResourceName
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz2 ON asz2.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd2 ON spd2.size_pack_detail_id = asz2.size_pack_detail_id
    LEFT JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    LEFT JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN resources rr ON rr.resource_id = awl.received_by_resource_id
    LEFT JOIN Users cu ON cu.Id = awl.created_by
    LEFT JOIN Users uu ON uu.Id = awl.updated_by
    LEFT JOIN resources ur ON ur.resource_id = awl.updated_by_resource_id
    WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
    ORDER BY aw.sort_order ASC, awl.created_at ASC;
END;
GO

-- Prompt 36: detail 1 baris log untuk modal "Edit Log" (/b/{serial}, /report-bundle Riwayat) --
-- termasuk QtyMasuk (arah atas) dan LowerBound (arah bawah, batas hard block EDIT_LOG) supaya
-- client bisa tampilkan baris info "Masuk: X • Batas bawah: Y" sebelum submit.
CREATE OR ALTER PROCEDURE SIS_SuperAdmin_LogEditInfo
    @WorkflowLogId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ArticleWorkflowId INT, @BundleId INT, @DivisionId INT, @ArticleId INT, @SortOrder INT;
    SELECT @ArticleWorkflowId = awl.article_workflow_id, @BundleId = awl.bundle_id,
           @DivisionId = awl.division_id, @ArticleId = aw.article_id, @SortOrder = aw.sort_order
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    WHERE awl.workflow_log_id = @WorkflowLogId AND awl.deleted_at IS NULL;

    -- Fix: TIDAK bare RETURN di sini kalau log tidak ditemukan -- itu membuat SP tidak
    -- mengembalikan result set SAMA SEKALI, dan EF Core (SqlQueryRaw) gagal dengan error
    -- "required column was not present" karena skema kolom tidak pernah terkirim. SELECT
    -- di bawah sengaja tetap jalan (JOIN-nya sendiri otomatis menghasilkan 0 baris kalau
    -- log tidak ditemukan/sudah dihapus), supaya GetLogEditInfoAsync bisa membedakan
    -- "0 baris" (FirstOrDefault -> null, wajar) dari error.
    DECLARE @NextArticleWorkflowId INT;
    SELECT TOP 1 @NextArticleWorkflowId = article_workflow_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 1 AND sort_order > @SortOrder
    ORDER BY sort_order ASC;

    DECLARE @PrevArticleWorkflowId INT;
    SELECT TOP 1 @PrevArticleWorkflowId = article_workflow_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 1 AND sort_order < @SortOrder
    ORDER BY sort_order DESC;

    DECLARE @QtyMasuk INT;
    IF @PrevArticleWorkflowId IS NOT NULL
        SELECT @QtyMasuk = ISNULL(SUM(qty_ok), 0)
        FROM article_workflow_logs
        WHERE article_workflow_id = @PrevArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;
    ELSE
        SELECT @QtyMasuk = qty FROM bundles WHERE bundle_id = @BundleId;

    DECLARE @LowerBound INT = NULL;
    IF @NextArticleWorkflowId IS NOT NULL
        SELECT @LowerBound = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost), 0)
        FROM article_workflow_logs
        WHERE article_workflow_id = @NextArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

    SELECT
        awl.workflow_log_id AS Id,
        aw.step_name AS StepName,
        awl.log_type AS LogType,
        awl.division_id AS DivisionId,
        awl.resource_id AS ResourceId,
        awl.qty_ok AS QtyOk,
        awl.qty_reject_print AS QtyRejectPrint,
        awl.qty_reject_fabric AS QtyRejectFabric,
        awl.qty_reject_sewing AS QtyRejectSewing,
        awl.qty_reject_rework AS QtyRejectRework,
        awl.qty_lost AS QtyLost,
        awl.remark AS Remark,
        ISNULL(@QtyMasuk, 0) AS QtyMasuk,
        @LowerBound AS LowerBound
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    WHERE awl.workflow_log_id = @WorkflowLogId AND awl.deleted_at IS NULL;
END;
GO

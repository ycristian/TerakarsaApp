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
-- Read: SIS_SuperAdmin_BundleSearch (@Search) dan SIS_SuperAdmin_BundleDetail (@BundleId) --
-- lihat masing-masing di bawah.

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

-- Detail satu bundle untuk panel /super-admin: info bundle, opsi ukuran artikel (dropdown
-- Edit Bundle), dan semua log hidup bundle ini (tabel log + tombol Edit/Hapus). 3 result set.
CREATE OR ALTER PROCEDURE SIS_SuperAdmin_BundleDetail
    @BundleId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: info bundle.
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
        a.color AS Color
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
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

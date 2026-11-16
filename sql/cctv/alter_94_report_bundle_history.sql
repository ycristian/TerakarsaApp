/* =============================================================
   Prompt 94 (module CCTV) -- tambah kolom di AKHIR result set timeline
   SIS_Report_BundleHistory: ResourceId (pelaksana) & DivisionId (divisi step),
   dipakai tombol "Lihat CCTV" di tab Riwayat Laporan Bundle.

   SATU-SATUNYA perubahan pada SP lama yang diizinkan Prompt 94: hanya menambah
   kolom di akhir SELECT, TIDAK ada perubahan logika. Isi SP di bawah = salinan
   persis definisi SP ini di sql/sp_Report_Bundle.sql (yang juga diperbarui).
   Script ini sengaja hanya berisi SP ini supaya SP lain di file itu tidak ikut
   dibuat ulang.

   Idempotent: CREATE OR ALTER.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- C. Riwayat -- timeline perjalanan satu bundle. Wajib @Serial ATAU pasangan
-- (@ProjectId + @BundleNo). Logika posisi sama dengan SIS_Report_BundleWip,
-- dihitung ulang untuk satu bundle saja (bukan reuse SIS_Bundle_ScanInfo -- SP itu
-- SP scan publik, tidak boleh diubah/dipanggil ulang di sini).
CREATE OR ALTER PROCEDURE SIS_Report_BundleHistory
    @Serial    VARCHAR(20) = NULL,
    @ProjectId INT = NULL,
    @BundleNo  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Serial IS NULL AND (@ProjectId IS NULL OR @BundleNo IS NULL)
    BEGIN
        RAISERROR('Serial atau (Project + Bundle No) wajib diisi.', 16, 1);
        RETURN;
    END

    DECLARE @BundleId INT;

    IF @Serial IS NOT NULL
        SELECT @BundleId = bundle_id FROM bundles WHERE serial = @Serial AND deleted_at IS NULL;
    ELSE
        SELECT @BundleId = b.bundle_id
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id
        WHERE a.project_id = @ProjectId AND b.bundle_no = @BundleNo AND b.deleted_at IS NULL;

    IF @BundleId IS NULL
    BEGIN
        RAISERROR('Bundle tidak ditemukan.', 16, 1);
        RETURN;
    END

    DECLARE @ArticleId INT;
    SELECT @ArticleId = article_id FROM bundles WHERE bundle_id = @BundleId;

    DECLARE @LastLogId INT, @LastReceivedAt DATETIME2, @LastTargetDivisionId INT,
            @LastCreatedAt DATETIME2, @LastStepName VARCHAR(255);
    SELECT TOP 1 @LastLogId = awl.workflow_log_id, @LastReceivedAt = awl.received_at,
                 @LastTargetDivisionId = awl.target_division_id, @LastCreatedAt = awl.created_at,
                 @LastStepName = aw.step_name
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
    ORDER BY aw.sort_order DESC, awl.created_at DESC;

    DECLARE @FirstBundleDivisionId INT, @FirstBundleStepName VARCHAR(255);
    SELECT TOP 1 @FirstBundleDivisionId = division_id, @FirstBundleStepName = step_name
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1
    ORDER BY sort_order ASC;

    DECLARE @Status VARCHAR(20) =
        CASE
            WHEN @LastLogId IS NULL THEN 'BELUM_MULAI'
            WHEN @LastReceivedAt IS NULL AND @LastTargetDivisionId IS NOT NULL THEN 'TRANSIT'
            WHEN @LastReceivedAt IS NOT NULL AND @LastTargetDivisionId IS NOT NULL THEN 'DIKERJAKAN'
            ELSE 'SELESAI'
        END;
    DECLARE @PosisiDivisionId INT =
        CASE
            WHEN @LastLogId IS NULL THEN @FirstBundleDivisionId
            WHEN @LastTargetDivisionId IS NOT NULL THEN @LastTargetDivisionId
            ELSE NULL
        END;
    DECLARE @StepNameCalc VARCHAR(255) = CASE WHEN @LastLogId IS NULL THEN @FirstBundleStepName ELSE @LastStepName END;

    -- 1. Header
    SELECT
        b.bundle_id AS BundleId,
        b.serial AS Serial,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        p.project_name AS ProjectName,
        a.article_name AS ArticleName,
        spd.size_name AS SizeName,
        b.qty AS Qty,
        r.resource_name AS TailorName,
        @Status AS Status,
        pd.division_name AS PosisiDivisionName,
        @StepNameCalc AS StepName,
        emp.employee_name AS EmployeeName
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = b.resource_id
    LEFT JOIN divisions pd ON pd.division_id = @PosisiDivisionId
    LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
    WHERE b.bundle_id = @BundleId;

    -- 2. Timeline
    -- Prompt 36: Id (workflow_log_id) ditambahkan supaya tombol "Edit" (Super Admin) di tab
    -- Riwayat bisa memicu modal edit per baris -- kolom murni tambahan.
    SELECT
        awl.workflow_log_id AS Id,
        aw.step_name AS StepName,
        d.division_name AS DivisionName,
        td.division_name AS TargetDivisionName,
        awl.qty_ok AS QtyOk,
        (awl.qty_reject_print + awl.qty_reject_fabric + awl.qty_reject_sewing + awl.qty_reject_rework + awl.qty_lost) AS QtyReject,
        awl.remark AS Remark,
        r.resource_name AS PelaksanaName,
        awl.created_at AS CreatedAt,
        cu.FullName AS CreatedByName,
        awl.received_at AS ReceivedAt,
        rr.resource_name AS ReceivedByResourceName,
        awl.received_remark AS ReceivedRemark,
        -- Prompt 94: id pelaksana & divisi step untuk tombol "Lihat CCTV" -- kolom murni
        -- tambahan di AKHIR, tanpa perubahan logika (lihat sql/cctv/alter_94_report_bundle_history.sql).
        awl.resource_id AS ResourceId,
        awl.division_id AS DivisionId
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    LEFT JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    LEFT JOIN resources rr ON rr.resource_id = awl.received_by_resource_id
    LEFT JOIN Users cu ON cu.Id = awl.created_by
    WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
    ORDER BY aw.sort_order ASC, awl.created_at ASC;
END;
GO

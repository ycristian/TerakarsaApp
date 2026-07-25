-- Prompt 13: Modul Laporan Arus Bundle -- READ-ONLY, tidak menyentuh data sama sekali.
-- Tiga SP dipakai oleh ReportBundleController (module REPORT_BUNDLE, halaman
-- /report-bundle) untuk memantau arus bundle dari article_workflow_logs (model 1-baris,
-- lihat sp_WorkflowLog_Manage.sql / Prompt 12b): baris dibuat saat divisi selesai/serah,
-- received_at terisi saat divisi tujuan menerima.
--
-- Definisi posisi bundle (dipakai SIS_Report_BundleWip & SIS_Report_BundleHistory):
-- "Log terakhir" bundle = baris article_workflow_logs hidup (deleted_at IS NULL) dengan
-- sort_order step (article_workflows) terbesar, tie-break created_at terbesar.
--
--   Kondisi log terakhir                                  | Status      | PosisiDivisionId
--   ------------------------------------------------------|-------------|------------------
--   Tidak ada log                                         | BELUM_MULAI | divisi step ber-bundle PERTAMA artikel
--   received_at NULL, target_division_id NOT NULL         | TRANSIT     | target_division_id (menunggu diterima di sana)
--   received_at NOT NULL, target_division_id NOT NULL     | DIKERJAKAN  | target_division_id (sudah diterima, dikerjakan di sana)
--   target_division_id NULL (step terakhir)                | SELESAI     | NULL
--
-- PosisiDivisionName jadi "divisi yang sedang/segera bertanggung jawab" -- BELUM_MULAI dan
-- TRANSIT sama-sama menunjuk divisi TUJUAN berikutnya (belum vs sudah diserahkan dibedakan
-- lewat Status), DIKERJAKAN menunjuk divisi yang sedang memegang bundle sekarang.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- A. WIP -- posisi setiap bundle saat ini.
CREATE OR ALTER PROCEDURE SIS_Report_BundleWip
    @ProjectId  INT = NULL,
    @ArticleId  INT = NULL,
    @DivisionId INT = NULL,
    @Status     VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Base AS (
        SELECT
            b.bundle_id, b.serial, b.bundle_no, p.bundle_letter, b.qty,
            a.article_id, a.article_name,
            p.project_id, p.project_name,
            spd.size_name,
            ISNULL(b.resource_person_name, rr.resource_name) AS tailor_name,
            ll.workflow_log_id AS last_log_id,
            ll.received_at AS last_received_at,
            ll.target_division_id AS last_target_division_id,
            ll.created_at AS last_created_at,
            law.step_name AS last_step_name,
            fbs.division_id AS first_bundle_division_id,
            fbs.step_name AS first_bundle_step_name
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources rr ON rr.resource_id = b.resource_id
        OUTER APPLY (
            SELECT TOP 1 awl.workflow_log_id, awl.article_workflow_id, awl.received_at,
                         awl.target_division_id, awl.created_at
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
            ORDER BY aw.sort_order DESC, awl.created_at DESC
        ) ll
        LEFT JOIN article_workflows law ON law.article_workflow_id = ll.article_workflow_id
        OUTER APPLY (
            SELECT TOP 1 aw2.division_id, aw2.step_name
            FROM article_workflows aw2
            WHERE aw2.article_id = b.article_id AND aw2.deleted_at IS NULL AND aw2.requires_bundle = 1
            ORDER BY aw2.sort_order ASC
        ) fbs
        WHERE b.deleted_at IS NULL
    ),
    Classified AS (
        SELECT *,
            CASE
                WHEN last_log_id IS NULL THEN 'BELUM_MULAI'
                WHEN last_received_at IS NULL AND last_target_division_id IS NOT NULL THEN 'TRANSIT'
                WHEN last_received_at IS NOT NULL AND last_target_division_id IS NOT NULL THEN 'DIKERJAKAN'
                ELSE 'SELESAI'
            END AS status_calc,
            CASE
                WHEN last_log_id IS NULL THEN first_bundle_division_id
                WHEN last_target_division_id IS NOT NULL THEN last_target_division_id
                ELSE NULL
            END AS posisi_division_id,
            CASE WHEN last_log_id IS NULL THEN first_bundle_step_name ELSE last_step_name END AS step_name_calc,
            CASE
                WHEN last_log_id IS NULL THEN NULL
                WHEN last_received_at IS NOT NULL THEN last_received_at
                ELSE last_created_at
            END AS updated_info
        FROM Base
    )
    SELECT
        c.bundle_id AS BundleId,
        c.serial AS Serial,
        c.bundle_no AS BundleNo,
        c.bundle_letter AS BundleLetter,
        c.project_name AS ProjectName,
        c.article_name AS ArticleName,
        c.size_name AS SizeName,
        c.qty AS Qty,
        c.status_calc AS Status,
        pd.division_name AS PosisiDivisionName,
        c.step_name_calc AS StepName,
        c.tailor_name AS TailorName,
        c.updated_info AS UpdatedInfo
    FROM Classified c
    LEFT JOIN divisions pd ON pd.division_id = c.posisi_division_id
    WHERE (@ProjectId IS NULL OR c.project_id = @ProjectId)
      AND (@ArticleId IS NULL OR c.article_id = @ArticleId)
      AND (@DivisionId IS NULL OR c.posisi_division_id = @DivisionId)
      AND (@Status IS NULL OR c.status_calc = @Status)
    ORDER BY c.project_name ASC, c.article_name ASC, c.bundle_no ASC;
END;
GO

-- B. Progres -- matriks step x bundle per artikel dalam satu project.
CREATE OR ALTER PROCEDURE SIS_Report_ArticleProgress
    @ProjectId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: step ber-bundle (requires_bundle = 1).
    SELECT
        a.article_id AS ArticleId,
        a.article_name AS ArticleName,
        aw.article_workflow_id AS ArticleWorkflowId,
        aw.step_name AS StepName,
        d.division_name AS DivisionName,
        aw.sort_order AS SortOrder,
        (SELECT COUNT(*) FROM bundles bb WHERE bb.article_id = a.article_id AND bb.deleted_at IS NULL) AS TotalBundle,
        -- Prompt 14b: satu bundle boleh punya beberapa baris (susulan) per step -- hitung
        -- bundle unik yang tersentuh, bukan jumlah baris.
        (SELECT COUNT(DISTINCT l.bundle_id) FROM article_workflow_logs l
         WHERE l.article_workflow_id = aw.article_workflow_id AND l.deleted_at IS NULL) AS BundleSelesai,
        (SELECT COUNT(DISTINCT l.bundle_id) FROM article_workflow_logs l
         WHERE l.article_workflow_id = aw.article_workflow_id AND l.received_at IS NOT NULL AND l.deleted_at IS NULL) AS BundleDiterima,
        (SELECT ISNULL(SUM(l.qty_ok), 0) FROM article_workflow_logs l
         WHERE l.article_workflow_id = aw.article_workflow_id AND l.deleted_at IS NULL) AS QtyOk,
        (SELECT ISNULL(SUM(l.qty_reject_print + l.qty_reject_fabric + l.qty_reject_sewing + l.qty_reject_rework + l.qty_lost), 0)
         FROM article_workflow_logs l
         WHERE l.article_workflow_id = aw.article_workflow_id AND l.deleted_at IS NULL) AS QtyReject
    FROM article_workflows aw
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN divisions d ON d.division_id = aw.division_id
    WHERE a.project_id = @ProjectId AND a.deleted_at IS NULL AND aw.deleted_at IS NULL AND aw.requires_bundle = 1
    ORDER BY a.article_name ASC, aw.sort_order ASC;

    -- Result set 2: step non-bundle (requires_bundle = 0).
    SELECT
        a.article_id AS ArticleId,
        aw.article_workflow_id AS ArticleWorkflowId,
        aw.step_name AS StepName,
        d.division_name AS DivisionName,
        aw.sort_order AS SortOrder,
        (SELECT ISNULL(SUM(asz.qty), 0) FROM article_sizes asz
         WHERE asz.article_id = a.article_id AND asz.deleted_at IS NULL) AS QtyTarget,
        (SELECT ISNULL(SUM(l.qty_ok), 0) FROM article_workflow_logs l
         WHERE l.article_workflow_id = aw.article_workflow_id AND l.deleted_at IS NULL) AS QtyOk,
        (SELECT ISNULL(SUM(l.qty_reject_print + l.qty_reject_fabric + l.qty_reject_sewing + l.qty_reject_rework + l.qty_lost), 0)
         FROM article_workflow_logs l
         WHERE l.article_workflow_id = aw.article_workflow_id AND l.deleted_at IS NULL) AS QtyReject
    FROM article_workflows aw
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN divisions d ON d.division_id = aw.division_id
    WHERE a.project_id = @ProjectId AND a.deleted_at IS NULL AND aw.deleted_at IS NULL AND aw.requires_bundle = 0
    ORDER BY a.article_name ASC, aw.sort_order ASC;

    -- Result set 3 (Prompt 14): surplus per artikel per step non-bundle per ukuran -- progres
    -- dibatasi 100% di client (result set 2 tetap dipakai untuk progress bar), kelebihan
    -- (mis. hasil potong lebih dari qty order) ditampilkan terpisah di sini per ukuran,
    -- hanya baris dengan surplus > 0.
    SELECT
        a.article_id AS ArticleId,
        aw.article_workflow_id AS ArticleWorkflowId,
        spd.size_name AS SizeName,
        asz.qty AS QtyTarget,
        ISNULL(SUM(l.qty_ok), 0) AS QtyOk,
        ISNULL(SUM(l.qty_ok), 0) - asz.qty AS Surplus
    FROM article_workflows aw
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN article_sizes asz ON asz.article_id = a.article_id AND asz.deleted_at IS NULL
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN article_workflow_logs l ON l.article_workflow_id = aw.article_workflow_id
        AND l.article_size_id = asz.article_size_id AND l.deleted_at IS NULL
    WHERE a.project_id = @ProjectId AND a.deleted_at IS NULL AND aw.deleted_at IS NULL AND aw.requires_bundle = 0
    GROUP BY a.article_id, aw.article_workflow_id, spd.size_name, asz.qty
    HAVING ISNULL(SUM(l.qty_ok), 0) - asz.qty > 0
    ORDER BY a.article_id ASC, aw.article_workflow_id ASC, spd.size_name ASC;
END;
GO

-- C. Riwayat -- timeline perjalanan satu bundle. Wajib @Serial ATAU pasangan
-- (@ProjectId + @BundleNo). Logika posisi sama dengan SIS_Report_BundleWip di atas,
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
        ISNULL(b.resource_person_name, r.resource_name) AS TailorName,
        @Status AS Status,
        pd.division_name AS PosisiDivisionName,
        @StepNameCalc AS StepName
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = b.resource_id
    LEFT JOIN divisions pd ON pd.division_id = @PosisiDivisionId
    WHERE b.bundle_id = @BundleId;

    -- 2. Timeline
    SELECT
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
        awl.received_remark AS ReceivedRemark
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

-- D. Selisih (Prompt 14) -- kebocoran qty per bundle per step ber-bundle, mulai step ke-2
-- (step pertama qty masuk = qty bundle itu sendiri, tidak relevan dibandingkan). Hanya
-- menyertakan step yang SUDAH punya log (step yang belum dikerjakan bukan "selisih", cuma
-- belum sampai) -- QtyMasuk step ini = QtyOk log step SEBELUMNYA (atau qty bundle utk step
-- pertama), QtyKeluar = ok + 3 reject step ini. Kelebihan (QtyKeluar > QtyMasuk) tampil
-- negatif pada Selisih, sesuai definisi (QtyMasuk - QtyKeluar).
-- Prompt 14b: satu bundle boleh punya beberapa baris (susulan) per step -- QtyOk/QtyKeluar
-- di sini SUM semua baris hidup step tsb per bundle (StepAgg), bukan baris tunggal.
CREATE OR ALTER PROCEDURE SIS_Report_BundleVariance
    @ProjectId INT = NULL,
    @ArticleId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH StepAgg AS (
        SELECT article_workflow_id, bundle_id,
               SUM(qty_ok) AS QtyOk,
               SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost) AS QtyKeluar
        FROM article_workflow_logs
        WHERE deleted_at IS NULL
        GROUP BY article_workflow_id, bundle_id
    )
    SELECT
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        b.serial AS Serial,
        a.article_name AS ArticleName,
        spd.size_name AS SizeName,
        aw.step_name AS StepName,
        CASE WHEN prevaw.article_workflow_id IS NULL THEN b.qty ELSE ISNULL(prevAgg.QtyOk, 0) END AS QtyMasuk,
        ISNULL(curAgg.QtyKeluar, 0) AS QtyKeluar,
        CASE WHEN prevaw.article_workflow_id IS NULL THEN b.qty ELSE ISNULL(prevAgg.QtyOk, 0) END
            - ISNULL(curAgg.QtyKeluar, 0) AS Selisih
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
    INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    INNER JOIN article_workflows aw ON aw.article_id = b.article_id AND aw.deleted_at IS NULL AND aw.requires_bundle = 1
    INNER JOIN StepAgg curAgg ON curAgg.article_workflow_id = aw.article_workflow_id AND curAgg.bundle_id = b.bundle_id
    OUTER APPLY (
        SELECT TOP 1 aw2.article_workflow_id
        FROM article_workflows aw2
        WHERE aw2.article_id = b.article_id AND aw2.deleted_at IS NULL AND aw2.requires_bundle = 1 AND aw2.sort_order < aw.sort_order
        ORDER BY aw2.sort_order DESC
    ) prevaw
    LEFT JOIN StepAgg prevAgg ON prevAgg.article_workflow_id = prevaw.article_workflow_id AND prevAgg.bundle_id = b.bundle_id
    WHERE b.deleted_at IS NULL
      AND prevaw.article_workflow_id IS NOT NULL
      AND (@ProjectId IS NULL OR p.project_id = @ProjectId)
      AND (@ArticleId IS NULL OR a.article_id = @ArticleId)
      AND (
            (CASE WHEN prevaw.article_workflow_id IS NULL THEN b.qty ELSE ISNULL(prevAgg.QtyOk, 0) END)
            - ISNULL(curAgg.QtyKeluar, 0)
          ) <> 0
    ORDER BY p.project_name ASC, a.article_name ASC, b.bundle_no ASC, aw.sort_order ASC;
END;
GO

-- E. Progres per ukuran -- matriks ukuran x step untuk satu artikel (dipakai kartu
-- "Laporan Progress" di halaman Edit Project). Kolom PO diambil dari article_sizes.qty
-- di result set 1 (client), sisanya dari QtyOk kumulatif tiap step di result set 3.
-- Step ber-bundle (requires_bundle = 1, TERMASUK Bundling implisit) selalu menyimpan
-- article_size_id = NULL di baris log (lihat sp_Bundle_Manage.sql / sp_WorkflowLog_Manage.sql
-- -- ukuran melekat ke bundle, bukan ke baris log) -- ukurannya diambil lewat
-- bundles.article_size_id (nilai TERKINI, konsisten dengan SIS_Report_BundleWip yang juga
-- pakai ukuran bundle saat ini, bukan ukuran saat log dibuat). Step non-bundle menyimpan
-- article_size_id langsung di baris log.
CREATE OR ALTER PROCEDURE SIS_Report_ArticleSizeProgress
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: ukuran (baris tabel) + target PO.
    SELECT
        asz.article_size_id AS SizeId,
        spd.size_name AS SizeName,
        spd.sort_order AS SortOrder,
        asz.qty AS PoQty
    FROM article_sizes asz
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE asz.article_id = @ArticleId AND asz.deleted_at IS NULL
    ORDER BY spd.sort_order ASC;

    -- Result set 2: step (kolom tabel), urut sort_order, termasuk step Bundling implisit.
    SELECT
        aw.article_workflow_id AS ArticleWorkflowId,
        aw.step_name AS StepName,
        aw.sort_order AS SortOrder
    FROM article_workflows aw
    WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL
    ORDER BY aw.sort_order ASC;

    -- Result set 3: isi sel matriks -- SUM(qty_ok) per (step, ukuran).
    ;WITH LogSized AS (
        SELECT
            l.article_workflow_id,
            CASE WHEN aw.requires_bundle = 1 THEN b.article_size_id ELSE l.article_size_id END AS SizeId,
            l.qty_ok
        FROM article_workflow_logs l
        INNER JOIN article_workflows aw ON aw.article_workflow_id = l.article_workflow_id
        LEFT JOIN bundles b ON b.bundle_id = l.bundle_id
        WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL AND l.deleted_at IS NULL
    )
    SELECT
        article_workflow_id AS ArticleWorkflowId,
        SizeId,
        SUM(qty_ok) AS QtyOk
    FROM LogSized
    WHERE SizeId IS NOT NULL
    GROUP BY article_workflow_id, SizeId
    ORDER BY article_workflow_id ASC, SizeId ASC;
END;
GO

-- Prompt 22: Dashboard WIP per Divisi & Resource -- READ-ONLY, tidak menyentuh data sama
-- sekali. Dipakai oleh ReportWipController (module REPORT_WIP, halaman /wip-dashboard).
--
-- Definisi (WAJIB konsisten dengan sp_Report_Bundle.sql):
-- "Log terakhir" bundle = baris article_workflow_logs hidup (deleted_at IS NULL) dengan
-- sort_order step (article_workflows) terbesar, tie-break created_at terbesar. Hanya
-- mencakup step ber-bundle (requires_bundle = 1) -- step non-bundle (mis. Cutting) tidak
-- ikut karena bundle_id NULL untuk baris tsb, tidak pernah jadi log terakhir sebuah bundle.
--
--   Kondisi log terakhir                                        | Kelompok
--   ------------------------------------------------------------|------------------
--   target_division_id NOT NULL, received_at NOT NULL           | DIKERJAKAN (per resource penerima)
--   target_division_id NOT NULL, received_at NULL                | BELUM DITERIMA
--   target_division_id NULL                                      | SELESAI, tidak tampil
--
-- Project manual_status Completed/Cancelled dikecualikan seluruhnya (On Hold tetap tampil).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- A. Ringkasan per divisi -- dua result set (Dikerjakan per resource, Belum diterima per divisi).
-- @ProjectId (opsional, ditambahkan bersama dropdown filter project di /wip-dashboard):
-- NULL = semua project (perilaku lama tidak berubah).
CREATE OR ALTER PROCEDURE SIS_Report_DivisionWip
    @ProjectId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        b.bundle_id,
        ll.target_division_id,
        ll.received_at,
        ll.received_by_resource_id,
        ll.qty_ok,
        ll.created_at,
        p.project_name,
        a.article_name
    INTO #LastLog
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
    INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
    OUTER APPLY (
        SELECT TOP 1 awl.target_division_id, awl.received_at, awl.received_by_resource_id,
                     awl.qty_ok, awl.created_at
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
        ORDER BY aw.sort_order DESC, awl.created_at DESC
    ) ll
    WHERE b.deleted_at IS NULL
      AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
      AND ll.target_division_id IS NOT NULL
      AND (@ProjectId IS NULL OR p.project_id = @ProjectId);

    -- Result set 1: Dikerjakan, agregat per (divisi, resource penerima).
    SELECT
        d.division_id AS DivisionId,
        d.division_name AS DivisionName,
        r.resource_id AS ResourceId,
        r.resource_name AS ResourceName,
        COUNT(*) AS BundleCount,
        SUM(t.qty_ok) AS TotalPcs,
        MIN(t.received_at) AS OldestReceivedAt,
        (
            SELECT t2.project_name AS ProjectName, t2.article_name AS ArticleName, COUNT(*) AS BundleCount
            FROM #LastLog t2
            WHERE t2.target_division_id = MAX(t.target_division_id)
              AND t2.received_at IS NOT NULL
              AND ISNULL(t2.received_by_resource_id, -1) = ISNULL(MAX(t.received_by_resource_id), -1)
            GROUP BY t2.project_name, t2.article_name
            ORDER BY t2.project_name, t2.article_name
            FOR JSON PATH
        ) AS ArticlesJson
    FROM #LastLog t
    INNER JOIN divisions d ON d.division_id = t.target_division_id AND d.deleted_at IS NULL
    LEFT JOIN resources r ON r.resource_id = t.received_by_resource_id AND r.deleted_at IS NULL
    WHERE t.received_at IS NOT NULL
    GROUP BY d.division_id, d.division_name, r.resource_id, r.resource_name
    ORDER BY d.division_name ASC, r.resource_name ASC;

    -- Result set 2: Belum diterima, agregat per divisi.
    SELECT
        d.division_id AS DivisionId,
        d.division_name AS DivisionName,
        COUNT(*) AS BundleCount,
        SUM(t.qty_ok) AS TotalPcs,
        MIN(t.created_at) AS OldestSentAt,
        (
            SELECT t2.project_name AS ProjectName, t2.article_name AS ArticleName, COUNT(*) AS BundleCount
            FROM #LastLog t2
            WHERE t2.target_division_id = MAX(t.target_division_id)
              AND t2.received_at IS NULL
            GROUP BY t2.project_name, t2.article_name
            ORDER BY t2.project_name, t2.article_name
            FOR JSON PATH
        ) AS ArticlesJson
    FROM #LastLog t
    INNER JOIN divisions d ON d.division_id = t.target_division_id AND d.deleted_at IS NULL
    WHERE t.received_at IS NULL
    GROUP BY d.division_id, d.division_name
    ORDER BY d.division_name ASC;

    DROP TABLE #LastLog;
END;
GO

-- B. Daftar bundle untuk popup "Lihat" satu kartu (satu divisi + satu kelompok).
-- @FilterResource membedakan "filter resource tidak dipakai" (0, dipakai mode PENDING) vs
-- "resource NULL" (1 + @ResourceId NULL, kelompok Dikerjakan "Tanpa penerima").
-- @ProjectId (opsional) menyamakan popup dengan filter project dropdown di dashboard.
CREATE OR ALTER PROCEDURE SIS_Report_DivisionWipBundles
    @DivisionId      INT,
    @Mode            VARCHAR(20),
    @ResourceId      INT = NULL,
    @FilterResource  BIT = 0,
    @ProjectId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Mode NOT IN ('DIKERJAKAN', 'PENDING')
    BEGIN
        RAISERROR('Mode tidak dikenal, gunakan DIKERJAKAN atau PENDING.', 16, 1);
        RETURN;
    END

    ;WITH LastLog AS (
        SELECT
            b.bundle_id, b.bundle_no, p.bundle_letter, b.serial,
            a.article_name,
            p.project_name,
            spd.size_name,
            ISNULL(b.resource_person_name, rr.resource_name) AS tailor_name,
            ll.article_workflow_id, ll.qty_ok, ll.target_division_id, ll.received_at,
            ll.received_by_resource_id, ll.created_at,
            law.step_name
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources rr ON rr.resource_id = b.resource_id
        OUTER APPLY (
            SELECT TOP 1 awl.article_workflow_id, awl.qty_ok, awl.target_division_id,
                         awl.received_at, awl.received_by_resource_id, awl.created_at
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
            ORDER BY aw.sort_order DESC, awl.created_at DESC
        ) ll
        LEFT JOIN article_workflows law ON law.article_workflow_id = ll.article_workflow_id
        WHERE b.deleted_at IS NULL
          AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
          AND ll.target_division_id = @DivisionId
          AND (@ProjectId IS NULL OR p.project_id = @ProjectId)
    )
    SELECT
        l.bundle_id AS BundleId,
        l.bundle_no AS BundleNo,
        l.bundle_letter AS BundleLetter,
        l.serial AS Serial,
        l.project_name AS ProjectName,
        l.article_name AS ArticleName,
        l.size_name AS SizeName,
        l.qty_ok AS QtyOk,
        l.tailor_name AS TailorName,
        l.step_name AS StepName,
        CASE WHEN @Mode = 'DIKERJAKAN' THEN l.received_at ELSE l.created_at END AS EventAt,
        CASE WHEN @Mode = 'DIKERJAKAN' THEN rrn.resource_name ELSE NULL END AS ReceivedByResourceName
    FROM LastLog l
    LEFT JOIN resources rrn ON rrn.resource_id = l.received_by_resource_id
    WHERE
        (@Mode = 'DIKERJAKAN' AND l.received_at IS NOT NULL
            AND (
                @FilterResource = 0
                OR (@ResourceId IS NULL AND l.received_by_resource_id IS NULL)
                OR (@ResourceId IS NOT NULL AND l.received_by_resource_id = @ResourceId)
            ))
        OR (@Mode = 'PENDING' AND l.received_at IS NULL)
    ORDER BY CASE WHEN @Mode = 'DIKERJAKAN' THEN l.received_at ELSE l.created_at END ASC;
END;
GO

-- C. Project sedang berjalan + progres qty bundle dibuat vs qty order, dipakai dropdown
-- filter project di /wip-dashboard. "Sedang berjalan" = manual_status BUKAN
-- Completed/Cancelled (sama dengan definisi dashboard di atas -- On Hold tetap tampil).
-- OrderQty = SUM(article_sizes.qty) project ybs, BundleQty = SUM(bundles.qty) project ybs
-- (bundle_qty di article_sizes TIDAK dipakai -- itu rencana jumlah bundle per size, bukan qty
-- yang sudah benar-benar dibuat).
CREATE OR ALTER PROCEDURE SIS_Report_RunningProjects
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.project_id AS ProjectId,
        bu.buyer_name AS BuyerName,
        p.project_name AS ProjectName,
        ISNULL(oq.OrderQty, 0) AS OrderQty,
        ISNULL(bq.BundleQty, 0) AS BundleQty,
        CASE WHEN ISNULL(oq.OrderQty, 0) > 0
             THEN CAST(ROUND(100.0 * ISNULL(bq.BundleQty, 0) / oq.OrderQty, 1) AS FLOAT)
             ELSE CAST(0 AS FLOAT)
        END AS ProgressPercent
    FROM projects p
    INNER JOIN buyers bu ON bu.buyer_id = p.customer_id
    OUTER APPLY (
        SELECT SUM(asz.qty) AS OrderQty
        FROM article_sizes asz
        INNER JOIN articles a ON a.article_id = asz.article_id AND a.deleted_at IS NULL
        WHERE a.project_id = p.project_id AND asz.deleted_at IS NULL
    ) oq
    OUTER APPLY (
        SELECT SUM(b.qty) AS BundleQty
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        WHERE a.project_id = p.project_id AND b.deleted_at IS NULL
    ) bq
    WHERE p.deleted_at IS NULL
      AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
    ORDER BY bu.buyer_name ASC, p.project_name ASC;
END;
GO

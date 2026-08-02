-- Prompt 42: Rekap Produksi mingguan (Divisi/Resource/Penjahit) -- MENGGANTIKAN Rekap Penjahit
-- harian Prompt 41 (SIS_Report_RekapPenjahitHeader/Detail/Print, di-drop di bawah). Kupon per
-- bundle (KUPON_BORONGAN, sp_WorkflowLog_Manage.sql) TIDAK disentuh.
--
-- Periode gajian = SAMA persis logika SIS_Report_ProduksiAgg/Detail (sql/sp_Report_Produksi.sql):
-- Sabtu 10:00 s/d Sabtu 10:00 berikutnya. Bedanya di sana @PeriodStart/@PeriodEnd dihitung di
-- client (dropdown 12 periode); di sini operator hanya pilih SATU TANGGAL (default hari ini,
-- tidak boleh masa depan) dan SP yang menghitung periode yang memuat tanggal itu:
--   - @Date = hari ini -> pakai SYSDATETIME() apa adanya (jam berjalan) supaya baris cutoff
--     Sabtu sebelum/sesudah jam 10:00 otomatis masuk periode berbeda (lihat prompt, verifikasi
--     "uji batas cutoff").
--   - @Date != hari ini (operator pilih tanggal lalu) -> tidak ada info jam, dianggap tengah
--     hari (jam 12:00) supaya SELALU >= cutoff 10:00 -- kalau tanggalnya kebetulan hari Sabtu,
--     ini artinya periode yang DIMULAI Sabtu itu (bukan periode sebelumnya), sesuai intuisi
--     "pilih tanggal di kalender = pilih minggu yang dimulai/berisi tanggal itu".
--   Trik hitung "hari sejak Sabtu terakhir" tanpa bergantung @@DATEFIRST: 1900-01-06 adalah
--   hari Sabtu, jadi DATEDIFF(DAY, '19000106', tgl) % 7 selalu 0 utk Sabtu, 1 utk Minggu, dst.
--
-- Definisi Qty Done & WIP mengikuti PERSIS SIS_Report_ProduksiAgg/Detail (Prompt 30/31/36) --
-- lihat komentar lengkap di sp_Report_Produksi.sql. Rekap ini TIDAK punya kolom "Dicek/Menunggu
-- QC" (di luar cakupan struk borongan) jadi DirectAtoms di sini hanya "atom Qty Done" (baris
-- yg qty_ok/reject-nya jatuh dalam periode, timing sama persis Prompt 30 -- target_division_id
-- NULL pakai created_at, selain itu pakai received_at), langsung difilter di WHERE (bukan
-- di-nol-kan lalu di-HAVING seperti Prompt 30 yg juga butuh kolom lain).
--
-- WIP (Result set 3) pakai ANCHOR @PeriodEnd (persis Prompt 30, BUKAN "SYSDATETIME() selalu") --
-- desain (2026-08-02, tidak eksplisit di prompt): untuk periode berjalan (kasus umum, @Date
-- default hari ini) @PeriodEnd ada di masa depan sehingga otomatis identik "snapshot sekarang"
-- (tidak ada data setelah SYSDATETIME() untuk dihitung). Untuk periode yang SUDAH LEWAT (operator
-- cetak ulang struk minggu lalu), anchor @PeriodEnd yang historis lebih konsisten dgn payroll
-- record drpd snapshot "sekarang" yang bisa sudah berubah drastis.
--
-- @Level (DIVISION|RESOURCE|EMPLOYEE) TIDAK mengubah baris data yang di-scan -- @ResourceId/
-- @EmployeeId (cascading dari dropdown) sudah cukup mempersempit scope-nya. @Level HANYA
-- mengontrol GRANULARITAS pengelompokan baris output (per bundle / per penjahit / per resource)
-- dan kolom Label yang ditampilkan -- lihat CASE @Level di tiap SELECT final.
--
-- Result set row shape (Detail & WIP, SAMA -- "granularitas sama seperti result set 2" sesuai
-- prompt): EventDate (NULL utk WIP, snapshot bukan kejadian harian), ArticleName, SizeName
-- (hanya diisi level EMPLOYEE -- level RESOURCE/DIVISION menggabung lintas size), Label (bundle
-- letter+no / nama penjahit / nama resource sesuai level, SUDAH diformat siap-tampil), Qty +
-- 5 kolom reject/lost (WIP selalu 0 di kelimanya, WIP bukan hasil kerja).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Bersih-bersih SP Prompt 41 yang digantikan total oleh Prompt 42 (idempotent -- aman walau
-- belum pernah di-deploy ke database ini).
DROP PROCEDURE IF EXISTS SIS_Report_RekapPenjahitPrint;
GO
DROP PROCEDURE IF EXISTS SIS_Report_RekapPenjahitDetail;
GO
DROP PROCEDURE IF EXISTS SIS_Report_RekapPenjahitHeader;
GO
-- Dropdown "Line" lintas-divisi Prompt 41 juga sudah tidak dipakai -- Prompt 42 pakai cascading
-- Divisi -> Resource (SIS_Resource_GetActiveByDivision, sudah ada) -> Penjahit.
DROP PROCEDURE IF EXISTS SIS_Resource_TailorLines;
GO

CREATE OR ALTER PROCEDURE SIS_Report_RekapStruk
    @Level      VARCHAR(10),        -- DIVISION | RESOURCE | EMPLOYEE
    @DivisionId INT,
    @ResourceId INT = NULL,
    @EmployeeId INT = NULL,
    @Date       DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EffectiveDate DATE = ISNULL(@Date, CAST(SYSDATETIME() AS DATE));
    DECLARE @Ref DATETIME2 = CASE WHEN @EffectiveDate = CAST(SYSDATETIME() AS DATE)
        THEN SYSDATETIME()
        ELSE DATEADD(HOUR, 12, CAST(@EffectiveDate AS DATETIME2)) END;
    DECLARE @DaysSinceSaturday INT = DATEDIFF(DAY, '19000106', CAST(@Ref AS DATE)) % 7;
    DECLARE @CandidateStart DATETIME2 = DATEADD(HOUR, 10, CAST(DATEADD(DAY, -@DaysSinceSaturday, CAST(@Ref AS DATE)) AS DATETIME2));
    IF @CandidateStart > @Ref SET @CandidateStart = DATEADD(DAY, -7, @CandidateStart);
    DECLARE @PeriodStart DATETIME2 = @CandidateStart;
    DECLARE @PeriodEnd DATETIME2 = DATEADD(DAY, 7, @CandidateStart);

    -- ================= Result set 1: header =================
    ;WITH DirectAtoms AS (
        SELECT
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.resource_id ELSE NULL END AS LineResourceId,
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.employee_id ELSE NULL END AS EmployeeId,
            awl.qty_ok AS QtyOk
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        WHERE awl.deleted_at IS NULL AND aw.division_id = @DivisionId
          AND (
                (awl.target_division_id IS NULL AND awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd)
             OR (awl.target_division_id IS NOT NULL AND awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd)
              )
    )
    SELECT
        dv.division_name AS DivisionName,
        rs.resource_name AS ResourceName,
        emp.employee_name AS EmployeeName,
        @Level AS Level,
        @PeriodStart AS PeriodStart,
        @PeriodEnd AS PeriodEnd,
        ISNULL((
            SELECT SUM(da.QtyOk) FROM DirectAtoms da
            WHERE (@ResourceId IS NULL OR da.LineResourceId = @ResourceId)
              AND (@EmployeeId IS NULL OR da.EmployeeId = @EmployeeId)
        ), 0) AS TotalQty
    FROM divisions dv
    LEFT JOIN resources rs ON rs.resource_id = @ResourceId
    LEFT JOIN employees emp ON emp.employee_id = @EmployeeId AND emp.deleted_at IS NULL
    WHERE dv.division_id = @DivisionId AND dv.deleted_at IS NULL;

    -- ================= Result set 2: detail harian (Qty Done) =================
    ;WITH DirectAtoms AS (
        SELECT
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.resource_id ELSE NULL END AS LineResourceId,
            ISNULL(lr.resource_name, N'Tanpa Line') AS LineResourceName,
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.employee_id ELSE NULL END AS EmployeeId,
            CASE WHEN awl.bundle_id IS NOT NULL THEN ISNULL(ben.employee_name, brn.resource_name) ELSE arn.resource_name END AS PelaksanaName,
            ar.article_name AS ArticleName,
            b.bundle_no AS BundleNo,
            pr.bundle_letter AS BundleLetter,
            ISNULL(spd.size_name, N'-') AS SizeName,
            CASE WHEN awl.target_division_id IS NULL THEN CAST(awl.created_at AS DATE) ELSE CAST(awl.received_at AS DATE) END AS EventDate,
            awl.qty_ok AS QtyOk,
            awl.qty_reject_print AS QtyRejectPrint,
            awl.qty_reject_fabric AS QtyRejectFabric,
            awl.qty_reject_sewing AS QtyRejectSewing,
            awl.qty_reject_rework AS QtyRejectRework,
            awl.qty_lost AS QtyLost
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        INNER JOIN articles ar ON ar.article_id = aw.article_id AND ar.deleted_at IS NULL
        INNER JOIN projects pr ON pr.project_id = ar.project_id AND pr.deleted_at IS NULL
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        LEFT JOIN resources lr ON lr.resource_id = b.resource_id
        LEFT JOIN resources brn ON brn.resource_id = b.resource_id
        LEFT JOIN resources arn ON arn.resource_id = awl.resource_id
        LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL
        LEFT JOIN article_sizes asz ON asz.article_size_id = CASE WHEN awl.bundle_id IS NOT NULL THEN b.article_size_id ELSE awl.article_size_id END
        LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE awl.deleted_at IS NULL AND aw.division_id = @DivisionId
          AND (
                (awl.target_division_id IS NULL AND awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd)
             OR (awl.target_division_id IS NOT NULL AND awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd)
              )
    )
    SELECT
        t.EventDate,
        t.ArticleName,
        CASE WHEN @Level = 'EMPLOYEE' THEN t.SizeName ELSE NULL END AS SizeName,
        CASE @Level
            WHEN 'EMPLOYEE' THEN ISNULL(t.BundleLetter + '-', '') + CAST(t.BundleNo AS VARCHAR(10))
            WHEN 'RESOURCE' THEN t.PelaksanaName
            ELSE t.LineResourceName
        END AS Label,
        SUM(t.QtyOk) AS Qty,
        SUM(t.QtyRejectPrint) AS QtyRejectPrint,
        SUM(t.QtyRejectFabric) AS QtyRejectFabric,
        SUM(t.QtyRejectSewing) AS QtyRejectSewing,
        SUM(t.QtyRejectRework) AS QtyRejectRework,
        SUM(t.QtyLost) AS QtyLost
    FROM DirectAtoms t
    WHERE (@ResourceId IS NULL OR t.LineResourceId = @ResourceId)
      AND (@EmployeeId IS NULL OR t.EmployeeId = @EmployeeId)
    GROUP BY t.EventDate, t.ArticleName,
        CASE WHEN @Level = 'EMPLOYEE' THEN t.SizeName ELSE NULL END,
        CASE @Level
            WHEN 'EMPLOYEE' THEN ISNULL(t.BundleLetter + '-', '') + CAST(t.BundleNo AS VARCHAR(10))
            WHEN 'RESOURCE' THEN t.PelaksanaName
            ELSE t.LineResourceName
        END
    HAVING SUM(t.QtyOk) > 0
        OR SUM(t.QtyRejectPrint + t.QtyRejectFabric + t.QtyRejectSewing + t.QtyRejectRework + t.QtyLost) > 0
    ORDER BY t.EventDate ASC, t.ArticleName ASC;

    -- ================= Result set 3: WIP snapshot (anchor @PeriodEnd, lihat catatan di atas) =================
    ;WITH StepPrev AS (
        SELECT
            aw.article_workflow_id, aw.article_id, aw.sort_order,
            (SELECT TOP 1 p.article_workflow_id FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_article_workflow_id,
            (SELECT TOP 1 p.requires_bundle FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_requires_bundle
        FROM article_workflows aw
        WHERE aw.deleted_at IS NULL AND aw.division_id = @DivisionId
    ),
    BundleMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.bundle_id AS BundleId, SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd AND pl.bundle_id IS NOT NULL
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, pl.bundle_id
    ),
    BundleTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, cl.bundle_id AS BundleId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, cl.bundle_id
    ),
    BundleWip AS (
        SELECT
            b.resource_id AS LineResourceId, ISNULL(lr.resource_name, N'Tanpa Line') AS LineResourceName,
            b.employee_id AS EmployeeId, ISNULL(ben.employee_name, brn.resource_name) AS PelaksanaName,
            ar.article_name AS ArticleName,
            b.bundle_no AS BundleNo, pr.bundle_letter AS BundleLetter,
            ISNULL(spd.size_name, N'-') AS SizeName,
            CASE WHEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0 THEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) ELSE 0 END AS QtyWip
        FROM BundleMasuk bm
        LEFT JOIN BundleTercatat bt ON bt.StepArticleWorkflowId = bm.StepArticleWorkflowId AND bt.BundleId = bm.BundleId
        INNER JOIN bundles b ON b.bundle_id = bm.BundleId AND b.deleted_at IS NULL
        INNER JOIN articles ar ON ar.article_id = b.article_id AND ar.deleted_at IS NULL
        INNER JOIN projects pr ON pr.project_id = ar.project_id AND pr.deleted_at IS NULL
        LEFT JOIN resources lr ON lr.resource_id = b.resource_id
        LEFT JOIN resources brn ON brn.resource_id = b.resource_id
        LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL
        LEFT JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0
    ),
    SizeMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.article_size_id AS ArticleSizeId, SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, pl.article_size_id
    ),
    SizeTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId,
               ISNULL(cl.article_size_id, bb.article_size_id) AS ArticleSizeId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        LEFT JOIN bundles bb ON bb.bundle_id = cl.bundle_id AND bb.deleted_at IS NULL
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, ISNULL(cl.article_size_id, bb.article_size_id)
    ),
    SizeWip AS (
        SELECT
            CAST(NULL AS INT) AS LineResourceId, N'Tanpa Line' AS LineResourceName,
            CAST(NULL AS INT) AS EmployeeId, CAST(NULL AS VARCHAR(150)) AS PelaksanaName,
            ar.article_name AS ArticleName,
            CAST(NULL AS INT) AS BundleNo, CAST(NULL AS VARCHAR(1)) AS BundleLetter,
            ISNULL(spd.size_name, N'-') AS SizeName,
            CASE WHEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0 THEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) ELSE 0 END AS QtyWip
        FROM SizeMasuk sm
        LEFT JOIN SizeTercatat st ON st.StepArticleWorkflowId = sm.StepArticleWorkflowId AND st.ArticleSizeId = sm.ArticleSizeId
        INNER JOIN article_sizes asz ON asz.article_size_id = sm.ArticleSizeId
        INNER JOIN articles ar ON ar.article_id = asz.article_id AND ar.deleted_at IS NULL
        LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0
    ),
    WipAtoms AS (
        SELECT LineResourceId, LineResourceName, EmployeeId, PelaksanaName, ArticleName, BundleNo, BundleLetter, SizeName, QtyWip FROM BundleWip
        UNION ALL
        SELECT LineResourceId, LineResourceName, EmployeeId, PelaksanaName, ArticleName, BundleNo, BundleLetter, SizeName, QtyWip FROM SizeWip
    )
    SELECT
        CAST(NULL AS DATE) AS EventDate,
        w.ArticleName,
        CASE WHEN @Level = 'EMPLOYEE' THEN w.SizeName ELSE NULL END AS SizeName,
        CASE @Level
            WHEN 'EMPLOYEE' THEN ISNULL(w.BundleLetter + '-', '') + CAST(w.BundleNo AS VARCHAR(10))
            WHEN 'RESOURCE' THEN w.PelaksanaName
            ELSE w.LineResourceName
        END AS Label,
        SUM(w.QtyWip) AS Qty,
        0 AS QtyRejectPrint, 0 AS QtyRejectFabric, 0 AS QtyRejectSewing, 0 AS QtyRejectRework, 0 AS QtyLost
    FROM WipAtoms w
    WHERE (@ResourceId IS NULL OR w.LineResourceId = @ResourceId)
      AND (@EmployeeId IS NULL OR w.EmployeeId = @EmployeeId)
    GROUP BY w.ArticleName,
        CASE WHEN @Level = 'EMPLOYEE' THEN w.SizeName ELSE NULL END,
        CASE @Level
            WHEN 'EMPLOYEE' THEN ISNULL(w.BundleLetter + '-', '') + CAST(w.BundleNo AS VARCHAR(10))
            WHEN 'RESOURCE' THEN w.PelaksanaName
            ELSE w.LineResourceName
        END
    HAVING SUM(w.QtyWip) > 0
    ORDER BY w.ArticleName ASC;
END;
GO

-- "Cetak Struk" -- snapshot ULANG di SP (bukan payload dari client), pola sama dgn Prompt 41
-- (SIS_Report_RekapPenjahitPrint yg digantikan). CTE chain diduplikasi dari SIS_Report_RekapStruk
-- di atas supaya payload struk konsisten dgn yang ditampilkan di modal konfirmasi.
CREATE OR ALTER PROCEDURE SIS_Report_RekapStrukPrint
    @Level      VARCHAR(10),
    @DivisionId INT,
    @ResourceId INT = NULL,
    @EmployeeId INT = NULL,
    @Date       DATE = NULL,
    @UserId     INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM divisions WHERE division_id = @DivisionId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Divisi tidak ditemukan.', 16, 1);
        RETURN;
    END

    DECLARE @EffectiveDate DATE = ISNULL(@Date, CAST(SYSDATETIME() AS DATE));
    DECLARE @Ref DATETIME2 = CASE WHEN @EffectiveDate = CAST(SYSDATETIME() AS DATE)
        THEN SYSDATETIME()
        ELSE DATEADD(HOUR, 12, CAST(@EffectiveDate AS DATETIME2)) END;
    DECLARE @DaysSinceSaturday INT = DATEDIFF(DAY, '19000106', CAST(@Ref AS DATE)) % 7;
    DECLARE @CandidateStart DATETIME2 = DATEADD(HOUR, 10, CAST(DATEADD(DAY, -@DaysSinceSaturday, CAST(@Ref AS DATE)) AS DATETIME2));
    IF @CandidateStart > @Ref SET @CandidateStart = DATEADD(DAY, -7, @CandidateStart);
    DECLARE @PeriodStart DATETIME2 = @CandidateStart;
    DECLARE @PeriodEnd DATETIME2 = DATEADD(DAY, 7, @CandidateStart);

    DECLARE @Payload NVARCHAR(MAX);

    ;WITH DirectAtoms AS (
        SELECT
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.resource_id ELSE NULL END AS LineResourceId,
            ISNULL(lr.resource_name, N'Tanpa Line') AS LineResourceName,
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.employee_id ELSE NULL END AS EmployeeId,
            CASE WHEN awl.bundle_id IS NOT NULL THEN ISNULL(ben.employee_name, brn.resource_name) ELSE arn.resource_name END AS PelaksanaName,
            ar.article_name AS ArticleName,
            b.bundle_no AS BundleNo,
            pr.bundle_letter AS BundleLetter,
            ISNULL(spd.size_name, N'-') AS SizeName,
            CASE WHEN awl.target_division_id IS NULL THEN CAST(awl.created_at AS DATE) ELSE CAST(awl.received_at AS DATE) END AS EventDate,
            awl.qty_ok AS QtyOk,
            awl.qty_reject_print AS QtyRejectPrint,
            awl.qty_reject_fabric AS QtyRejectFabric,
            awl.qty_reject_sewing AS QtyRejectSewing,
            awl.qty_reject_rework AS QtyRejectRework,
            awl.qty_lost AS QtyLost
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        INNER JOIN articles ar ON ar.article_id = aw.article_id AND ar.deleted_at IS NULL
        INNER JOIN projects pr ON pr.project_id = ar.project_id AND pr.deleted_at IS NULL
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        LEFT JOIN resources lr ON lr.resource_id = b.resource_id
        LEFT JOIN resources brn ON brn.resource_id = b.resource_id
        LEFT JOIN resources arn ON arn.resource_id = awl.resource_id
        LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL
        LEFT JOIN article_sizes asz ON asz.article_size_id = CASE WHEN awl.bundle_id IS NOT NULL THEN b.article_size_id ELSE awl.article_size_id END
        LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE awl.deleted_at IS NULL AND aw.division_id = @DivisionId
          AND (
                (awl.target_division_id IS NULL AND awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd)
             OR (awl.target_division_id IS NOT NULL AND awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd)
              )
    ),
    StepPrev AS (
        SELECT
            aw.article_workflow_id, aw.article_id, aw.sort_order,
            (SELECT TOP 1 p.article_workflow_id FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_article_workflow_id,
            (SELECT TOP 1 p.requires_bundle FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_requires_bundle
        FROM article_workflows aw
        WHERE aw.deleted_at IS NULL AND aw.division_id = @DivisionId
    ),
    BundleMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.bundle_id AS BundleId, SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd AND pl.bundle_id IS NOT NULL
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, pl.bundle_id
    ),
    BundleTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, cl.bundle_id AS BundleId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, cl.bundle_id
    ),
    BundleWip AS (
        SELECT
            b.resource_id AS LineResourceId, ISNULL(lr.resource_name, N'Tanpa Line') AS LineResourceName,
            b.employee_id AS EmployeeId, ISNULL(ben.employee_name, brn.resource_name) AS PelaksanaName,
            ar2.article_name AS ArticleName,
            b.bundle_no AS BundleNo, pr2.bundle_letter AS BundleLetter,
            ISNULL(spd2.size_name, N'-') AS SizeName,
            CASE WHEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0 THEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) ELSE 0 END AS QtyWip
        FROM BundleMasuk bm
        LEFT JOIN BundleTercatat bt ON bt.StepArticleWorkflowId = bm.StepArticleWorkflowId AND bt.BundleId = bm.BundleId
        INNER JOIN bundles b ON b.bundle_id = bm.BundleId AND b.deleted_at IS NULL
        INNER JOIN articles ar2 ON ar2.article_id = b.article_id AND ar2.deleted_at IS NULL
        INNER JOIN projects pr2 ON pr2.project_id = ar2.project_id AND pr2.deleted_at IS NULL
        LEFT JOIN resources lr ON lr.resource_id = b.resource_id
        LEFT JOIN resources brn ON brn.resource_id = b.resource_id
        LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL
        LEFT JOIN article_sizes asz2 ON asz2.article_size_id = b.article_size_id
        LEFT JOIN size_pack_details spd2 ON spd2.size_pack_detail_id = asz2.size_pack_detail_id
        WHERE (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0
    ),
    SizeMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.article_size_id AS ArticleSizeId, SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, pl.article_size_id
    ),
    SizeTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId,
               ISNULL(cl.article_size_id, bb.article_size_id) AS ArticleSizeId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        LEFT JOIN bundles bb ON bb.bundle_id = cl.bundle_id AND bb.deleted_at IS NULL
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, ISNULL(cl.article_size_id, bb.article_size_id)
    ),
    SizeWip AS (
        SELECT
            CAST(NULL AS INT) AS LineResourceId, N'Tanpa Line' AS LineResourceName,
            CAST(NULL AS INT) AS EmployeeId, CAST(NULL AS VARCHAR(150)) AS PelaksanaName,
            ar3.article_name AS ArticleName,
            CAST(NULL AS INT) AS BundleNo, CAST(NULL AS VARCHAR(1)) AS BundleLetter,
            ISNULL(spd3.size_name, N'-') AS SizeName,
            CASE WHEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0 THEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) ELSE 0 END AS QtyWip
        FROM SizeMasuk sm
        LEFT JOIN SizeTercatat st ON st.StepArticleWorkflowId = sm.StepArticleWorkflowId AND st.ArticleSizeId = sm.ArticleSizeId
        INNER JOIN article_sizes asz3 ON asz3.article_size_id = sm.ArticleSizeId
        INNER JOIN articles ar3 ON ar3.article_id = asz3.article_id AND ar3.deleted_at IS NULL
        LEFT JOIN size_pack_details spd3 ON spd3.size_pack_detail_id = asz3.size_pack_detail_id
        WHERE (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0
    ),
    WipAtoms AS (
        SELECT LineResourceId, LineResourceName, EmployeeId, PelaksanaName, ArticleName, BundleNo, BundleLetter, SizeName, QtyWip FROM BundleWip
        UNION ALL
        SELECT LineResourceId, LineResourceName, EmployeeId, PelaksanaName, ArticleName, BundleNo, BundleLetter, SizeName, QtyWip FROM SizeWip
    )
    SELECT @Payload = (
        SELECT
            dv.division_name AS division_name,
            rs.resource_name AS resource_name,
            emp.employee_name AS employee_name,
            @Level AS [level],
            @PeriodStart AS period_start,
            @PeriodEnd AS period_end,
            ISNULL((
                SELECT SUM(da.QtyOk) FROM DirectAtoms da
                WHERE (@ResourceId IS NULL OR da.LineResourceId = @ResourceId)
                  AND (@EmployeeId IS NULL OR da.EmployeeId = @EmployeeId)
            ), 0) AS total_qty,
            JSON_QUERY((
                SELECT
                    t.EventDate AS event_date,
                    t.ArticleName AS article_name,
                    CASE WHEN @Level = 'EMPLOYEE' THEN t.SizeName ELSE NULL END AS size_name,
                    CASE @Level
                        WHEN 'EMPLOYEE' THEN ISNULL(t.BundleLetter + '-', '') + CAST(t.BundleNo AS VARCHAR(10))
                        WHEN 'RESOURCE' THEN t.PelaksanaName
                        ELSE t.LineResourceName
                    END AS label,
                    SUM(t.QtyOk) AS qty,
                    SUM(t.QtyRejectPrint) AS qty_reject_print,
                    SUM(t.QtyRejectFabric) AS qty_reject_fabric,
                    SUM(t.QtyRejectSewing) AS qty_reject_sewing,
                    SUM(t.QtyRejectRework) AS qty_reject_rework,
                    SUM(t.QtyLost) AS qty_lost
                FROM DirectAtoms t
                WHERE (@ResourceId IS NULL OR t.LineResourceId = @ResourceId)
                  AND (@EmployeeId IS NULL OR t.EmployeeId = @EmployeeId)
                GROUP BY t.EventDate, t.ArticleName,
                    CASE WHEN @Level = 'EMPLOYEE' THEN t.SizeName ELSE NULL END,
                    CASE @Level
                        WHEN 'EMPLOYEE' THEN ISNULL(t.BundleLetter + '-', '') + CAST(t.BundleNo AS VARCHAR(10))
                        WHEN 'RESOURCE' THEN t.PelaksanaName
                        ELSE t.LineResourceName
                    END
                HAVING SUM(t.QtyOk) > 0
                    OR SUM(t.QtyRejectPrint + t.QtyRejectFabric + t.QtyRejectSewing + t.QtyRejectRework + t.QtyLost) > 0
                ORDER BY t.EventDate ASC, t.ArticleName ASC
                FOR JSON PATH
            )) AS lines,
            JSON_QUERY((
                SELECT
                    w.ArticleName AS article_name,
                    CASE WHEN @Level = 'EMPLOYEE' THEN w.SizeName ELSE NULL END AS size_name,
                    CASE @Level
                        WHEN 'EMPLOYEE' THEN ISNULL(w.BundleLetter + '-', '') + CAST(w.BundleNo AS VARCHAR(10))
                        WHEN 'RESOURCE' THEN w.PelaksanaName
                        ELSE w.LineResourceName
                    END AS label,
                    SUM(w.QtyWip) AS qty
                FROM WipAtoms w
                WHERE (@ResourceId IS NULL OR w.LineResourceId = @ResourceId)
                  AND (@EmployeeId IS NULL OR w.EmployeeId = @EmployeeId)
                GROUP BY w.ArticleName,
                    CASE WHEN @Level = 'EMPLOYEE' THEN w.SizeName ELSE NULL END,
                    CASE @Level
                        WHEN 'EMPLOYEE' THEN ISNULL(w.BundleLetter + '-', '') + CAST(w.BundleNo AS VARCHAR(10))
                        WHEN 'RESOURCE' THEN w.PelaksanaName
                        ELSE w.LineResourceName
                    END
                HAVING SUM(w.QtyWip) > 0
                ORDER BY w.ArticleName ASC
                FOR JSON PATH
            )) AS wip_lines
        FROM divisions dv
        LEFT JOIN resources rs ON rs.resource_id = @ResourceId
        LEFT JOIN employees emp ON emp.employee_id = @EmployeeId AND emp.deleted_at IS NULL
        WHERE dv.division_id = @DivisionId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
    VALUES ('REKAP_PRODUKSI', @DivisionId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewPrintJobId;
END;
GO

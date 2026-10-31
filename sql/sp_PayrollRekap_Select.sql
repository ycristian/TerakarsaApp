-- Prompt 83: Rekap Gajian admin -- isi satu PERIODE GAJIAN, baris LOG dan MANUAL dalam
-- satu daftar per resource, dengan harga yang DIBEKUKAN saat lock (workflow_lock_items
-- .unit_price) dan bisa dikoreksi admin lewat SIS_LockItem_UpdatePrice.
-- SELECT saja.
--
-- Bedanya dengan SIS_Station_RekapProduksi (Prompt 59):
--   * harga di sini dari SNAPSHOT lock item, bukan dari article_workflows.unit_price yang
--     berlaku sekarang. Mengubah master tarif TIDAK lagi mengubah angka periode lampau.
--     Rekap stasiun sengaja dibiarkan apa adanya (di luar cakupan Prompt 83) -- jadi dua
--     rekap itu bisa berbeda untuk periode yang tarifnya diubah setelah lock.
--   * baris MANUAL (manual_outputs) ikut, dengan badge sumber.
--   * non_po_outputs TIDAK ikut -- tabel itu diretire, punya harganya sendiri dari PIC,
--     dan tidak pernah masuk mekanisme lock.
--
-- Definisi qty upah DISAMAKAN dengan rekap stasiun: qty_ok + qty_reject_fabric (reject
-- BAHAN dibayar, kategori reject lain tidak). Untuk baris MANUAL qty dipakai apa adanya
-- dan BOLEH MINUS -- baris minus adalah catatan potongan.
--
-- Hanya lock item AKTIF yang dihitung: released_at IS NULL (lock yang sudah dilepas lewat
-- unlock request tidak lagi jadi isi periode) dan deleted_at IS NULL.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ===========================================================================
-- SIS_PayrollRekap_Periods -- pemilih periode di halaman Rekap Gajian.
-- Hanya periode yang PUNYA isi (ada lock item aktif) -- periode kosong tidak ada
-- yang bisa dikerjakan di sana. MissingPriceCount yang mengunci tombol Finalisasi.
-- ===========================================================================
CREATE OR ALTER PROCEDURE SIS_PayrollRekap_Periods
AS
BEGIN
    SET NOCOUNT ON;

    SELECT pp.payroll_period_id AS PayrollPeriodId,
           pp.period_code       AS PeriodCode,
           pp.period_start      AS PeriodStart,
           pp.period_end        AS PeriodEnd,
           pp.finalized_at      AS FinalizedAt,
           CAST(CASE WHEN pp.finalized_at IS NULL THEN 0 ELSE 1 END AS BIT) AS IsFinalized,
           COUNT(wli.lock_item_id) AS ItemCount,
           SUM(CASE WHEN wli.unit_price IS NULL THEN 1 ELSE 0 END) AS MissingPriceCount
    FROM payroll_periods pp
    INNER JOIN workflow_locks wl ON wl.payroll_period_id = pp.payroll_period_id
                                AND wl.deleted_at IS NULL
    INNER JOIN workflow_lock_items wli ON wli.lock_id = wl.lock_id
                                      AND wli.released_at IS NULL AND wli.deleted_at IS NULL
    WHERE pp.deleted_at IS NULL
    GROUP BY pp.payroll_period_id, pp.period_code, pp.period_start, pp.period_end, pp.finalized_at
    ORDER BY pp.period_start DESC;
END;
GO

-- ===========================================================================
-- SIS_PayrollRekap_List -- isi satu periode.
--
-- Tiga result set:
--   1. header periode (termasuk IsFinalized -> client menjadikan kolom harga read-only)
--   2. baris LOG + MANUAL, sudah diurutkan per resource
--   3. ringkasan per resource (total qty & nilai)
-- ===========================================================================
CREATE OR ALTER PROCEDURE SIS_PayrollRekap_List
    @PayrollPeriodId  INT,
    @DivisionId       INT = NULL,
    @ResourceId       INT = NULL,
    @OnlyMissingPrice BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM payroll_periods
        WHERE payroll_period_id = @PayrollPeriodId AND deleted_at IS NULL
    )
    BEGIN
        RAISERROR('Periode gajian tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- ---- 1. header ----
    SELECT pp.payroll_period_id AS PayrollPeriodId,
           pp.period_code       AS PeriodCode,
           pp.period_start      AS PeriodStart,
           pp.period_end        AS PeriodEnd,
           pp.finalized_at      AS FinalizedAt,
           CAST(CASE WHEN pp.finalized_at IS NULL THEN 0 ELSE 1 END AS BIT) AS IsFinalized,
           u.FullName           AS FinalizedByName
    FROM payroll_periods pp
    LEFT JOIN Users u ON u.Id = pp.finalized_by
    WHERE pp.payroll_period_id = @PayrollPeriodId;

    -- ---- baris, ditampung dulu supaya dipakai dua kali (detail + ringkasan) ----
    -- Qty baris LOG: qty_ok + qty_reject_fabric (sama dengan rekap stasiun).
    -- Qty baris MANUAL: snap_qty_ok apa adanya (= manual_outputs.qty saat lock), boleh minus.
    SELECT
        wli.lock_item_id AS LockItemId,
        wli.source       AS Source,
        CAST(CASE WHEN wli.source = 'MANUAL' THEN 1 ELSE 0 END AS BIT) AS IsManual,
        wl.division_id   AS DivisionId,
        d.division_name  AS DivisionName,
        wli.snap_resource_id AS ResourceId,
        res.resource_name    AS ResourceName,
        CASE WHEN wli.source = 'MANUAL' THEN mo.article_id ELSE aw.article_id END AS ArticleId,
        CASE WHEN wli.source = 'MANUAL' THEN mo_a.article_name ELSE a.article_name END AS ArticleName,
        CASE WHEN wli.source = 'MANUAL' THEN mo_p.no_po ELSE p.no_po END AS NoPo,
        aw.step_name AS StepName,
        -- Deskripsi yang dibaca admin: baris manual pakai teks bebas PIC, baris log pakai
        -- nama step (artikel/PO sudah punya kolomnya sendiri).
        CASE WHEN wli.source = 'MANUAL' THEN mo.work_description ELSE CAST(aw.step_name AS NVARCHAR(300)) END AS WorkDescription,
        CASE WHEN wli.source = 'MANUAL' THEN mo.size_name ELSE spd.size_name END AS SizeName,
        CASE WHEN wli.source = 'MANUAL'
             THEN wli.snap_qty_ok
             ELSE wli.snap_qty_ok + wli.snap_qty_reject_fabric END AS Qty,
        -- Reject baris MANUAL tidak di-snapshot per kategori (output manual cuma punya satu
        -- angka reject tanpa kategori), jadi dibaca dari manual_outputs -- aman karena baris
        -- yang sudah lock tidak bisa diubah lagi.
        CASE WHEN wli.source = 'MANUAL'
             THEN mo.reject_qty
             ELSE wli.snap_qty_reject_print + wli.snap_qty_reject_sewing
                  + wli.snap_qty_reject_rework + wli.snap_qty_lost END AS RejectQty,
        wli.unit_price AS UnitPrice,
        CAST(CASE WHEN wli.unit_price IS NULL THEN NULL
                  WHEN wli.source = 'MANUAL' THEN wli.snap_qty_ok * wli.unit_price
                  ELSE (wli.snap_qty_ok + wli.snap_qty_reject_fabric) * wli.unit_price
             END AS DECIMAL(19,4)) AS Total,
        CAST(CASE WHEN wli.unit_price IS NULL THEN 1 ELSE 0 END AS BIT) AS IsMissingPrice,
        -- Badge "Potongan" di UI.
        CAST(CASE WHEN wli.source = 'MANUAL' AND wli.snap_qty_ok < 0 THEN 1 ELSE 0 END AS BIT) AS IsPotongan,
        mo.note AS Note,
        mo.manual_output_id AS ManualOutputId,
        wli.workflow_log_id AS WorkflowLogId
    INTO #rows
    FROM workflow_lock_items wli
    INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id AND wl.deleted_at IS NULL
    LEFT JOIN divisions d ON d.division_id = wl.division_id
    LEFT JOIN resources res ON res.resource_id = wli.snap_resource_id
    -- jalur LOG
    LEFT JOIN article_workflow_logs awl ON awl.workflow_log_id = wli.workflow_log_id
    LEFT JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    LEFT JOIN articles a ON a.article_id = aw.article_id
    LEFT JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = wli.snap_article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    -- jalur MANUAL
    LEFT JOIN manual_outputs mo ON mo.manual_output_id = wli.manual_output_id
    LEFT JOIN articles mo_a ON mo_a.article_id = mo.article_id
    LEFT JOIN projects mo_p ON mo_p.project_id = mo_a.project_id
    WHERE wl.payroll_period_id = @PayrollPeriodId
      AND wli.released_at IS NULL AND wli.deleted_at IS NULL
      AND (@DivisionId IS NULL OR wl.division_id = @DivisionId)
      AND (@ResourceId IS NULL OR wli.snap_resource_id = @ResourceId)
      AND (@OnlyMissingPrice = 0 OR wli.unit_price IS NULL);

    -- ---- 2. detail ----
    SELECT * FROM #rows
    ORDER BY DivisionName, ResourceName, Source DESC, NoPo, ArticleName, LockItemId;

    -- ---- 3. ringkasan per resource ----
    SELECT ResourceId,
           ResourceName,
           DivisionName,
           COUNT(*) AS ItemCount,
           SUM(CASE WHEN IsMissingPrice = 1 THEN 1 ELSE 0 END) AS MissingPriceCount,
           SUM(Qty) AS TotalQty,
           CAST(SUM(ISNULL(Total, 0)) AS DECIMAL(19,4)) AS TotalNilai
    FROM #rows
    GROUP BY ResourceId, ResourceName, DivisionName
    ORDER BY DivisionName, ResourceName;
END;
GO

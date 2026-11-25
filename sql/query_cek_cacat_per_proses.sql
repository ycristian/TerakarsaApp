-- ============================================================================
-- Query ad-hoc (read-only): barang CACAT (reject) + HILANG (lost) yang tercatat,
-- dirinci per PROSES (step workflow) tempat dicatatnya.
--
-- Sumber: v_bundle_reject_unified (sql/v_84_reject_unified.sql) -- sudah menggabungkan
-- gaya LAMA (kolom qty_reject_*/qty_lost di log) dan gaya BARU (bundle anak +
-- bundles.missing_qty) tanpa dobel. Jangan menjumlah ulang dari tabel mentah.
--
-- Kategori: RejectBahan | RejectJahit | RejectPrint | Perbaikan | TidakLengkap | Hilang
-- Catatan:
--   * Hilang gaya baru = saldo missing_qty per bundle induk, tanggalnya = log 'Hilang'
--     terakhir bundle itu (bukan per kejadian).
--   * Baris LAMA bisa bernilai negatif (ADJUSTMENT) -- memang begitu, ikut dijumlah.
--   * Selisih LEBIH (missing_qty negatif) tidak termasuk.
--
-- Isi parameter di bawah (NULL = semua), lalu jalankan di SSMS.
-- ============================================================================

DECLARE @DateFrom  DATETIME = NULL;   -- mis. '2026-11-01'
DECLARE @DateTo    DATETIME = NULL;   -- eksklusif, mis. '2026-12-01'
DECLARE @ProjectId INT      = NULL;
DECLARE @ArticleId INT      = NULL;

;WITH R AS (
    SELECT
        v.*,
        p.project_id, p.project_name,
        a.article_id, a.article_name,
        aw.step_name, aw.sort_order,
        d.division_name
    FROM v_bundle_reject_unified v
    INNER JOIN bundles b   ON b.bundle_id = v.BundleId
    INNER JOIN articles a  ON a.article_id = b.article_id
    INNER JOIN projects p  ON p.project_id = a.project_id
    LEFT JOIN article_workflows aw ON aw.article_workflow_id = v.ArticleWorkflowId
    LEFT JOIN divisions d          ON d.division_id = ISNULL(v.DivisionId, aw.division_id)
    WHERE (@DateFrom  IS NULL OR v.CreatedAt >= @DateFrom)
      AND (@DateTo    IS NULL OR v.CreatedAt <  @DateTo)
      AND (@ProjectId IS NULL OR p.project_id = @ProjectId)
      AND (@ArticleId IS NULL OR a.article_id = @ArticleId)
)
-- ---------------------------------------------------------------------------
-- 1. REKAP per artikel x proses: qty per kategori cacat + hilang.
-- ---------------------------------------------------------------------------
SELECT
    project_name                                  AS Project,
    article_name                                  AS Artikel,
    sort_order                                    AS Urutan,
    ISNULL(step_name, '(proses tidak diketahui)') AS Proses,
    division_name                                 AS Divisi,
    SUM(CASE WHEN Category = 'RejectBahan'  THEN Qty ELSE 0 END) AS RejectBahan,
    SUM(CASE WHEN Category = 'RejectJahit'  THEN Qty ELSE 0 END) AS RejectJahit,
    SUM(CASE WHEN Category = 'RejectPrint'  THEN Qty ELSE 0 END) AS RejectPrint,
    SUM(CASE WHEN Category = 'Perbaikan'    THEN Qty ELSE 0 END) AS Perbaikan,
    SUM(CASE WHEN Category = 'TidakLengkap' THEN Qty ELSE 0 END) AS TidakLengkap,
    SUM(CASE WHEN Category NOT IN ('Hilang') THEN Qty ELSE 0 END) AS TotalCacat,
    SUM(CASE WHEN Category = 'Hilang'       THEN Qty ELSE 0 END) AS Hilang,
    SUM(Qty)                                                     AS TotalCacatHilang
FROM R
GROUP BY project_name, article_name, sort_order, step_name, division_name
ORDER BY project_name, article_name, sort_order;

-- ---------------------------------------------------------------------------
-- 2. DETAIL per bundle: proses, kategori, qty, penjahit/pelaksana, tanggal.
-- ---------------------------------------------------------------------------
;WITH R AS (
    SELECT v.*, p.project_name, a.article_name, aw.step_name, aw.sort_order,
           d.division_name, b.serial, p.bundle_letter, b.bundle_no, spd.size_name,
           cb.serial AS child_serial
    FROM v_bundle_reject_unified v
    INNER JOIN bundles b   ON b.bundle_id = v.BundleId
    INNER JOIN articles a  ON a.article_id = b.article_id
    INNER JOIN projects p  ON p.project_id = a.project_id
    LEFT JOIN article_sizes asz      ON asz.article_size_id = b.article_size_id
    LEFT JOIN size_pack_details spd  ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN bundles cb             ON cb.bundle_id = v.ChildBundleId
    LEFT JOIN article_workflows aw   ON aw.article_workflow_id = v.ArticleWorkflowId
    LEFT JOIN divisions d            ON d.division_id = ISNULL(v.DivisionId, aw.division_id)
    WHERE (@DateFrom  IS NULL OR v.CreatedAt >= @DateFrom)
      AND (@DateTo    IS NULL OR v.CreatedAt <  @DateTo)
      AND (@ProjectId IS NULL OR p.project_id = @ProjectId)
      AND (@ArticleId IS NULL OR a.article_id = @ArticleId)
)
SELECT
    R.CreatedAt                                   AS Tanggal,
    R.project_name                                AS Project,
    R.article_name                                AS Artikel,
    R.size_name                                   AS Ukuran,
    CONCAT(R.bundle_letter + '-', R.bundle_no)    AS Bundle,      -- mis. B-27 (project lama tanpa huruf: 27)
    R.serial                                      AS SerialInduk,
    R.child_serial                                AS SerialAnak,
    ISNULL(R.step_name, '(proses tidak diketahui)') AS Proses,
    R.division_name                               AS Divisi,
    R.Category                                    AS Kategori,
    R.Qty                                         AS Qty,
    res.resource_name                             AS Pelaksana,
    emp.employee_name                             AS Penjahit,
    R.[Source]                                    AS Sumber,      -- LAMA | ANAK
    R.WorkflowLogId                               AS WorkflowLogId
FROM R
LEFT JOIN resources res ON res.resource_id = R.ResourceId
LEFT JOIN employees emp ON emp.employee_id = R.EmployeeId
ORDER BY R.project_name, R.article_name, R.sort_order, R.Category, R.CreatedAt;

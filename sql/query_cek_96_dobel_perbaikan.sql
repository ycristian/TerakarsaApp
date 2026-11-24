-- ============================================================================
-- Prompt 96 -- query cek (read-only): qty_ok bundle ANAK yang terhitung DOBEL di
-- kartu "Laporan Progress per Ukuran" sebelum revisi SIS_Report_ArticleSizeProgress.
--
-- Dobel = baris log milik bundle anak (sequence_no > 0) di step dengan sort_order LEBIH
-- KECIL dari step kelahirannya. Di step-step itu pcs-nya sudah terhitung lewat induk.
-- Kasus utama: anak Perbaikan dikembalikan ke Sewing dari QC/Trim, lalu Kirim-nya
-- mengisi qty_ok penuh lagi di Sewing.
--
-- Angka di sini = selisih kolom step tsb antara SP LAMA dan SP BARU. Jalankan SEBELUM
-- dan SESUDAH sp_Report_Bundle.sql dieksekusi: hasilnya tetap sama (query ini tidak
-- bergantung pada SP), yang berubah hanya angka di kartu laporan.
-- ============================================================================

DECLARE @ArticleId INT = NULL;   -- NULL = semua artikel

;WITH ChildLog AS (
    SELECT
        a.article_id, a.article_name,
        aw.article_workflow_id, aw.step_name, aw.sort_order,
        b.bundle_id, b.serial, b.[status], b.reject_category,
        birth.BirthStepName, birth.BirthSort,
        l.workflow_log_id, l.log_kind, l.qty_ok, l.created_at
    FROM article_workflow_logs l
    INNER JOIN bundles b            ON b.bundle_id = l.bundle_id AND ISNULL(b.sequence_no, 0) > 0
    INNER JOIN article_workflows aw ON aw.article_workflow_id = l.article_workflow_id AND aw.deleted_at IS NULL
    INNER JOIN articles a           ON a.article_id = aw.article_id
    CROSS APPLY (
        SELECT TOP 1 paw.sort_order AS BirthSort, paw.step_name AS BirthStepName
        FROM bundle_split_results sr
        INNER JOIN bundle_splits bs ON bs.split_id = sr.split_id
        INNER JOIN article_workflow_logs pl ON pl.split_id = bs.split_id
            AND pl.bundle_id = bs.source_bundle_id AND pl.deleted_at IS NULL
        INNER JOIN article_workflows paw ON paw.article_workflow_id = pl.article_workflow_id
        WHERE sr.bundle_id = b.bundle_id
        ORDER BY pl.workflow_log_id
    ) birth
    WHERE l.deleted_at IS NULL
      AND l.qty_ok <> 0
      AND aw.sort_order < birth.BirthSort
      AND (@ArticleId IS NULL OR a.article_id = @ArticleId)
)
-- 1. Rekap per artikel x step: qty_ok yang hilang dari kolom step itu setelah revisi.
SELECT
    article_name   AS Artikel,
    sort_order     AS Urutan,
    step_name      AS Proses,
    COUNT(DISTINCT bundle_id) AS JumlahBundleAnak,
    SUM(qty_ok)    AS QtyDobel
FROM ChildLog
GROUP BY article_name, sort_order, step_name
ORDER BY article_name, sort_order;

-- 2. Detail per baris log (untuk ditelusuri satu per satu).
;WITH ChildLog AS (
    SELECT
        a.article_name, aw.step_name, aw.sort_order,
        b.serial, b.[status], b.reject_category,
        birth.BirthStepName,
        l.workflow_log_id, l.log_kind, l.qty_ok, l.created_at
    FROM article_workflow_logs l
    INNER JOIN bundles b            ON b.bundle_id = l.bundle_id AND ISNULL(b.sequence_no, 0) > 0
    INNER JOIN article_workflows aw ON aw.article_workflow_id = l.article_workflow_id AND aw.deleted_at IS NULL
    INNER JOIN articles a           ON a.article_id = aw.article_id
    CROSS APPLY (
        SELECT TOP 1 paw.sort_order AS BirthSort, paw.step_name AS BirthStepName
        FROM bundle_split_results sr
        INNER JOIN bundle_splits bs ON bs.split_id = sr.split_id
        INNER JOIN article_workflow_logs pl ON pl.split_id = bs.split_id
            AND pl.bundle_id = bs.source_bundle_id AND pl.deleted_at IS NULL
        INNER JOIN article_workflows paw ON paw.article_workflow_id = pl.article_workflow_id
        WHERE sr.bundle_id = b.bundle_id
        ORDER BY pl.workflow_log_id
    ) birth
    WHERE l.deleted_at IS NULL
      AND l.qty_ok <> 0
      AND aw.sort_order < birth.BirthSort
      AND (@ArticleId IS NULL OR a.article_id = @ArticleId)
)
SELECT
    created_at       AS Tanggal,
    article_name     AS Artikel,
    serial           AS SerialAnak,
    reject_category  AS KategoriAwal,
    [status]         AS StatusSekarang,
    BirthStepName    AS LahirDiProses,
    step_name        AS DihitungUlangDi,
    log_kind         AS JenisLog,
    qty_ok           AS QtyOk,
    workflow_log_id  AS WorkflowLogId
FROM ChildLog
ORDER BY article_name, sort_order, created_at;

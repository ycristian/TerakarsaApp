-- ============================================================================
-- Prompt 82 (revisi) -- DUA JALUR reject/hilang selama PO lama masih jalan.
--
-- Selama masa transisi ada DUA sumber angka reject yang sama-sama sah:
--   A. GAYA LAMA  -- kolom article_workflow_logs.qty_reject_*/qty_lost, untuk baris
--                    log dengan created_at < app_settings.bundle_split_migrated_at
--   B. GAYA BARU  -- bundle ANAK (bundles.status/reject_category) + bundles.missing_qty,
--                    untuk pemecahan yang terjadi SESUDAH tanggal itu
--
-- Menjumlahkan keduanya tanpa batas tanggal = DOBEL. View di bawah yang memegang
-- batas itu, jadi tiap laporan cukup membaca satu sumber dan tidak perlu mengulang
-- aturan tanggalnya sendiri-sendiri.
--
-- v_bundle_reject_unified -- satu baris per (bundle, step, kategori) dengan qty > 0:
--   BundleId          bundle INDUK yang reject-nya berasal darinya (bukan id anak)
--   ChildBundleId     id bundle anak (NULL untuk baris gaya lama)
--   ArticleWorkflowId step tempat reject itu tercatat
--   DivisionId        divisi yang mencatatnya
--   ResourceId/EmployeeId  pelaksana (dari baris log Kirim; NULL kalau tidak terisi)
--   WorkflowLogId     baris log sumber -- dipakai menyambung ke lock_id/periode gajian
--   CreatedAt         waktu kejadian (basis filter periode di laporan)
--   Category          RejectBahan | RejectJahit | RejectPrint | Perbaikan |
--                     TidakLengkap | Hilang
--   Qty               jumlah pcs
--   Source            'LAMA' | 'ANAK'
--
-- Catatan: kategori 'Hilang' gaya lama berasal dari qty_lost; gaya baru dari
-- bundles.missing_qty POSITIF (missing_qty negatif = Lebih, TIDAK muncul di sini --
-- baca langsung dari bundles kalau butuh angka Lebih).
-- ============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW v_bundle_reject_unified
AS
-- ---------------------------------------------------------------------------
-- A. GAYA LAMA: kolom qty_reject_*/qty_lost pada baris log SEBELUM tanggal migrasi.
-- ---------------------------------------------------------------------------
-- Baris ADJUSTMENT ikut (nilainya boleh negatif = mutasi keluar dari kategori itu),
-- supaya totalnya sama dengan yang dibaca laporan lama hari ini.
SELECT
    awl.bundle_id            AS BundleId,
    CAST(NULL AS INT)        AS ChildBundleId,
    awl.article_workflow_id  AS ArticleWorkflowId,
    awl.division_id          AS DivisionId,
    awl.resource_id          AS ResourceId,
    awl.employee_id          AS EmployeeId,
    awl.workflow_log_id      AS WorkflowLogId,
    awl.created_at           AS CreatedAt,
    v.Category               AS Category,
    v.Qty                    AS Qty,
    CAST('LAMA' AS VARCHAR(4)) AS [Source]
FROM article_workflow_logs awl
CROSS APPLY (VALUES
    ('RejectPrint',  awl.qty_reject_print),
    ('RejectBahan',  awl.qty_reject_fabric),
    ('RejectJahit',  awl.qty_reject_sewing),
    ('Perbaikan',    awl.qty_reject_rework),
    ('Hilang',       awl.qty_lost)
) v(Category, Qty)
WHERE awl.deleted_at IS NULL
  AND awl.bundle_id IS NOT NULL
  AND v.Qty <> 0
  AND awl.created_at < ISNULL(
        (SELECT TOP 1 bundle_split_migrated_at FROM app_settings WHERE deleted_at IS NULL),
        '9999-12-31')
  -- Migrasi 86 (sql/migrasi_86_qty_lost_ke_missing.sql): KHUSUS irisan 'Hilang',
  -- qty_lost sudah dilipat ke bundles.missing_qty dan dibaca di cabang C. Baris yang
  -- sudah dilipat WAJIB berhenti dibaca dari sini, kalau tidak angkanya dobel.
  -- Kolom qty_lost-nya sendiri sengaja TIDAK dinolkan (masih dipakai laporan lama dan
  -- fn_55_workflow_saldo), jadi penyaringnya tabel pemetaan, bukan nilai kolomnya.
  -- Kategori reject lain tidak terpengaruh -- batas tanggal di atas tetap berlaku.
  AND NOT (v.Category = 'Hilang' AND EXISTS (
            SELECT 1 FROM qty_lost_migration_items i
            WHERE i.workflow_log_id = awl.workflow_log_id))

UNION ALL

-- ---------------------------------------------------------------------------
-- B. GAYA BARU (bundle anak): satu baris per anak ber-status bukan OK.
-- ---------------------------------------------------------------------------
-- Induk & step diambil dari bundle_splits + baris log yang membawa split_id itu --
-- bukan dari parent_bundle_id, supaya anak-dari-anak tetap teratribusi ke pernyataan
-- pemecahan yang melahirkannya.
SELECT
    bs.source_bundle_id      AS BundleId,
    cb.bundle_id             AS ChildBundleId,
    src.article_workflow_id  AS ArticleWorkflowId,
    bs.division_id           AS DivisionId,
    bs.resource_id           AS ResourceId,
    src.employee_id          AS EmployeeId,
    src.workflow_log_id      AS WorkflowLogId,
    bs.created_at            AS CreatedAt,
    CAST(ISNULL(cb.reject_category, cb.[status]) AS VARCHAR(20)) AS Category,
    cb.qty                   AS Qty,
    CAST('ANAK' AS VARCHAR(4)) AS [Source]
FROM bundle_split_results sr
INNER JOIN bundle_splits bs ON bs.split_id = sr.split_id
INNER JOIN bundles cb ON cb.bundle_id = sr.bundle_id AND cb.deleted_at IS NULL
-- Baris log INDUK yang membawa split_id ini (log Kirim untuk kind 'split',
-- log Ketemu untuk kind 'found') -- sumber step & penjahitnya.
OUTER APPLY (
    SELECT TOP 1 l.workflow_log_id, l.article_workflow_id, l.employee_id
    FROM article_workflow_logs l
    WHERE l.split_id = bs.split_id AND l.bundle_id = bs.source_bundle_id
      AND l.deleted_at IS NULL
    ORDER BY l.workflow_log_id
) src
WHERE cb.sequence_no > 0
  AND cb.[status] <> 'OK'
  AND cb.qty > 0

UNION ALL

-- ---------------------------------------------------------------------------
-- C. GAYA BARU (selisih): missing_qty POSITIF di induk utama = Hilang.
-- ---------------------------------------------------------------------------
-- Satu baris per induk (bukan per kejadian) -- angkanya saldo, bukan mutasi.
-- Step/divisi diambil dari baris log 'Hilang' TERAKHIR bundle itu.
SELECT
    b.bundle_id              AS BundleId,
    CAST(NULL AS INT)        AS ChildBundleId,
    h.article_workflow_id    AS ArticleWorkflowId,
    h.division_id            AS DivisionId,
    h.resource_id            AS ResourceId,
    h.employee_id            AS EmployeeId,
    h.workflow_log_id        AS WorkflowLogId,
    ISNULL(h.created_at, b.created_at) AS CreatedAt,
    CAST('Hilang' AS VARCHAR(20)) AS Category,
    b.missing_qty            AS Qty,
    CAST('ANAK' AS VARCHAR(4)) AS [Source]
FROM bundles b
OUTER APPLY (
    SELECT TOP 1 l.workflow_log_id, l.article_workflow_id, l.division_id,
                 l.resource_id, l.employee_id, l.created_at
    FROM article_workflow_logs l
    WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
    ORDER BY l.created_at DESC, l.workflow_log_id DESC
) h
WHERE b.deleted_at IS NULL
  AND b.sequence_no = 0
  AND b.missing_qty > 0;
GO

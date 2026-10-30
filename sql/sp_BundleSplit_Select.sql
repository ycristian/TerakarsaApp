-- ============================================================================
-- Prompt 82 -- pengambilan data untuk modal "Kirim Hasil" (model pemecahan),
-- modal "Barang ketemu", dan angka Hilang/Lebih di kartu artikel stasiun.
-- Mutasi datanya ada di sql/sp_BundleSplit_Manage.sql.
-- ============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------
-- SIS_BundleSplit_Info -- isi awal modal Kirim Hasil untuk satu (bundle, step).
-- Dua result set:
--   1. Header: Masuk, qty sekarang, sisa selisih yang sudah tercatat, kode anak
--      berikutnya, status edit (IsEdit/CanEdit/LockedReason), divisi tujuan.
--   2. Anak yang SUDAH lahir dari pemecahan di step ini -- tampil read-only di modal
--      (tidak bisa diubah/dihapus, cuma bisa ditambah baris baru).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_BundleSplit_Info
    @BundleId          INT,
    @ArticleWorkflowId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ArticleId INT, @Qty INT, @RootId INT, @SizeId INT, @Serial VARCHAR(20),
            @SequenceNo INT, @BundleStatus VARCHAR(15);
    SELECT @ArticleId = article_id, @Qty = qty, @RootId = root_bundle_id,
           @SizeId = article_size_id, @Serial = serial, @SequenceNo = sequence_no,
           @BundleStatus = [status]
    FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL;

    IF @ArticleId IS NULL
    BEGIN
        RAISERROR('Bundle tidak ditemukan.', 16, 1);
        RETURN;
    END

    DECLARE @SortOrder INT;
    SELECT @SortOrder = sort_order FROM article_workflows WHERE article_workflow_id = @ArticleWorkflowId;

    -- Split kind = 'split' milik (bundle, step) ini -- dasar Masuk & daftar anak.
    DECLARE @StepSplits TABLE (SplitId INT PRIMARY KEY, SourceQtyBefore INT, LockId INT);
    INSERT INTO @StepSplits (SplitId, SourceQtyBefore, LockId)
    SELECT s.split_id, s.source_qty_before, s.lock_id
    FROM bundle_splits s
    WHERE s.source_bundle_id = @BundleId AND s.kind = 'split'
      AND EXISTS (
          SELECT 1 FROM article_workflow_logs l
          WHERE l.split_id = s.split_id AND l.bundle_id = @BundleId
            AND l.article_workflow_id = @ArticleWorkflowId AND l.deleted_at IS NULL
      );

    DECLARE @Masuk INT = ISNULL((SELECT MIN(SourceQtyBefore) FROM @StepSplits), @Qty);

    DECLARE @ExistingChildQty INT = ISNULL((
        SELECT SUM(sr.qty) FROM bundle_split_results sr
        WHERE sr.split_id IN (SELECT SplitId FROM @StepSplits)
    ), 0);

    DECLARE @ExistingMissing INT = @Masuk - @Qty - @ExistingChildQty;

    -- Sudah ada baris Kirim hidup di step ini = modal berjalan dalam mode EDIT.
    DECLARE @IsEdit BIT = CASE WHEN EXISTS (
        SELECT 1 FROM article_workflow_logs
        WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId
          AND deleted_at IS NULL AND log_kind = 'Kirim'
    ) THEN 1 ELSE 0 END;

    DECLARE @IsLocked BIT = CASE WHEN EXISTS (
        SELECT 1 FROM article_workflow_logs
        WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId
          AND deleted_at IS NULL AND log_kind = 'Kirim' AND lock_id IS NOT NULL
    ) THEN 1 ELSE 0 END;

    -- Lock otomatis: station berikutnya sudah membuat log untuk bundle ini.
    DECLARE @NextStationDone BIT = CASE WHEN EXISTS (
        SELECT 1 FROM article_workflow_logs awl
        INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
          AND awl.log_kind IN ('Kirim', 'Creation') AND aw2.sort_order > @SortOrder
    ) THEN 1 ELSE 0 END;

    DECLARE @NextSeq INT = ISNULL((
        SELECT MAX(sequence_no) FROM bundles WHERE root_bundle_id = @RootId AND deleted_at IS NULL
    ), 0) + 1;

    SELECT
        @BundleId AS BundleId,
        @Serial AS Serial,
        @SequenceNo AS SequenceNo,
        @BundleStatus AS BundleStatus,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        rb.bundle_no AS RootBundleNo,
        spd.size_name AS SizeName,
        a.article_name AS ArticleName,
        p.project_name AS ProjectName,
        p.no_po AS NoPo,
        aw.step_name AS StepName,
        @Masuk AS QtyMasuk,
        @Qty AS QtyNow,
        @ExistingChildQty AS ExistingChildQty,
        @ExistingMissing AS ExistingMissing,
        b.missing_qty AS MissingQty,
        @NextSeq AS NextSequenceNo,
        @IsEdit AS IsEdit,
        @IsLocked AS IsLocked,
        @NextStationDone AS NextStationDone,
        CAST(CASE WHEN @IsEdit = 1 AND (@IsLocked = 1 OR @NextStationDone = 1) THEN 0 ELSE 1 END AS BIT) AS CanSubmit,
        nd.division_id AS NextDivisionId,
        nd.division_name AS NextDivisionName,
        CAST(CASE WHEN nx.article_workflow_id IS NULL THEN 1 ELSE 0 END AS BIT) AS IsLastStep
    FROM bundles b
    INNER JOIN bundles rb ON rb.bundle_id = @RootId
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    INNER JOIN article_workflows aw ON aw.article_workflow_id = @ArticleWorkflowId
    OUTER APPLY (
        SELECT TOP 1 aw2.article_workflow_id, aw2.division_id
        FROM article_workflows aw2
        WHERE aw2.article_id = b.article_id AND aw2.deleted_at IS NULL AND aw2.inactive_at IS NULL
          AND aw2.sort_order > @SortOrder
        ORDER BY aw2.sort_order ASC
    ) nx
    LEFT JOIN divisions nd ON nd.division_id = nx.division_id
    WHERE b.bundle_id = @BundleId;

    -- Result set 2: anak yang sudah lahir di step ini (read-only di modal).
    SELECT
        cb.bundle_id AS BundleId,
        cb.serial AS Serial,
        cb.sequence_no AS SequenceNo,
        CAST(ISNULL(p.bundle_letter + '-', '') + CAST(rb.bundle_no AS VARCHAR(10))
             + '-' + CAST(cb.sequence_no AS VARCHAR(10)) AS VARCHAR(40)) AS DisplayCode,
        sr.qty AS Qty,
        sr.[status] AS [Status],
        sr.reject_category AS RejectCategory,
        sr.reject_reason AS RejectReason
    FROM bundle_split_results sr
    INNER JOIN bundles cb ON cb.bundle_id = sr.bundle_id
    INNER JOIN bundles rb ON rb.bundle_id = cb.root_bundle_id
    INNER JOIN articles a ON a.article_id = cb.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    WHERE sr.split_id IN (SELECT SplitId FROM @StepSplits)
    ORDER BY cb.sequence_no;
END;
GO

-- ---------------------------------------------------------------------------
-- SIS_BundleSplit_MissingByArticle -- angka Hilang / Lebih kartu artikel stasiun.
-- Hilang = Sigma missing_qty POSITIF semua induk artikel ini (SEMUA station, bukan
-- cuma station pemanggil). Lebih = Sigma missing_qty negatif (absolut).
-- Dipanggil per artikel yang tampil di tab WIP.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_BundleSplit_MissingByArticle
    @ArticleId INT = NULL      -- NULL = semua artikel yang punya selisih terbuka
AS
BEGIN
    SET NOCOUNT ON;

    SELECT b.article_id AS ArticleId,
           SUM(CASE WHEN b.missing_qty > 0 THEN b.missing_qty ELSE 0 END) AS MissingQty,
           SUM(CASE WHEN b.missing_qty < 0 THEN -b.missing_qty ELSE 0 END) AS OverQty
    FROM bundles b
    WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.missing_qty <> 0
      AND (@ArticleId IS NULL OR b.article_id = @ArticleId)
    GROUP BY b.article_id;
END;
GO

-- ---------------------------------------------------------------------------
-- SIS_BundleSplit_MissingSizes -- isi dropdown Size modal "Barang ketemu":
-- hanya size yang punya selisih TERBUKA (> 0), beserta angkanya.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_BundleSplit_MissingSizes
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT asz.article_size_id AS ArticleSizeId,
           spd.size_name AS SizeName,
           SUM(b.missing_qty) AS MissingQty
    FROM bundles b
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.article_id = @ArticleId
      AND b.missing_qty > 0
    GROUP BY asz.article_size_id, spd.size_name, spd.sort_order
    ORDER BY spd.sort_order;
END;
GO

-- ---------------------------------------------------------------------------
-- SIS_BundleSplit_MissingBundles -- blok "Akan dicatat ke" modal Barang ketemu.
-- Urutan otomatis LIFO: induk ber-missing_qty > 0 pada size itu, urut created_at
-- baris log 'Hilang' TERAKHIR desc ("yang paling baru hilang diisi lebih dulu").
-- Kolom AllocQty = hasil alokasi untuk @Qty (0 kalau tidak kebagian); kolom
-- IsOverflow = 1 kalau baris itu menerima kelebihan di atas selisihnya sendiri
-- (akan dicatat sebagai Lebih). @Qty NULL = tampilkan semua kandidat tanpa alokasi
-- (dipakai tombol "Ubah" -> input qty manual).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_BundleSplit_MissingBundles
    @ArticleSizeId INT,
    @Qty           INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Candidates AS (
        SELECT b.bundle_id, b.root_bundle_id, b.bundle_no, b.serial, b.missing_qty, b.article_id,
               ISNULL((
                   SELECT MAX(l.created_at) FROM article_workflow_logs l
                   WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
               ), b.created_at) AS LastMissingAt
        FROM bundles b
        WHERE b.deleted_at IS NULL AND b.sequence_no = 0
          AND b.article_size_id = @ArticleSizeId AND b.missing_qty > 0
    ),
    Ordered AS (
        SELECT c.*,
               SUM(c.missing_qty) OVER (ORDER BY c.LastMissingAt DESC, c.bundle_id DESC ROWS UNBOUNDED PRECEDING) AS CumQty,
               ROW_NUMBER() OVER (ORDER BY c.LastMissingAt DESC, c.bundle_id DESC) AS rn,
               COUNT(*) OVER () AS TotalRows
        FROM Candidates c
    )
    SELECT o.bundle_id AS BundleId,
           o.serial AS Serial,
           CAST(ISNULL(p.bundle_letter + '-', '') + CAST(o.bundle_no AS VARCHAR(10)) AS VARCHAR(40)) AS DisplayCode,
           o.missing_qty AS MissingQty,
           o.LastMissingAt AS LastMissingAt,
           CAST(ISNULL(p.bundle_letter + '-', '') + CAST(o.bundle_no AS VARCHAR(10)) + '-'
                + CAST(ISNULL((
                      SELECT MAX(sequence_no) FROM bundles cb
                      WHERE cb.root_bundle_id = o.root_bundle_id AND cb.deleted_at IS NULL
                  ), 0) + 1 AS VARCHAR(10)) AS VARCHAR(40)) AS NextChildCode,
           CASE WHEN @Qty IS NULL THEN 0
                WHEN o.CumQty <= @Qty THEN o.missing_qty
                WHEN (o.CumQty - o.missing_qty) < @Qty THEN @Qty - (o.CumQty - o.missing_qty)
                ELSE 0 END
           + CASE WHEN @Qty IS NOT NULL AND o.rn = o.TotalRows AND @Qty > o.CumQty
                  THEN @Qty - o.CumQty ELSE 0 END AS AllocQty,
           CAST(CASE WHEN @Qty IS NOT NULL AND o.rn = o.TotalRows AND @Qty > o.CumQty THEN 1 ELSE 0 END AS BIT) AS IsOverflow,
           o.rn AS SortOrder
    FROM Ordered o
    INNER JOIN articles a ON a.article_id = o.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    ORDER BY o.rn;
END;
GO

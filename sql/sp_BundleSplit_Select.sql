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

    -- Baris serah PERTAMA yang dibuat step ini untuk bundle ini. Ada = modal berjalan
    -- dalam mode EDIT.
    DECLARE @FirstSendLogId INT, @FirstSendAt DATETIME2;
    SELECT TOP 1 @FirstSendLogId = awl.workflow_log_id, @FirstSendAt = awl.created_at
    FROM article_workflow_logs awl
    WHERE awl.bundle_id = @BundleId AND awl.article_workflow_id = @ArticleWorkflowId
      AND awl.deleted_at IS NULL AND awl.log_kind IN ('Kirim', 'Split', 'Dikembalikan')
    ORDER BY awl.created_at ASC, awl.workflow_log_id ASC;

    DECLARE @IsEdit BIT = CASE WHEN @FirstSendLogId IS NULL THEN 0 ELSE 1 END;

    -- "Masuk N": Kirim pertama -> qty bundle saat ini. Mode EDIT -> qty_after baris
    -- TEPAT SEBELUM baris serah pertama step ini, yaitu isi bundle sewaktu station ini
    -- menerimanya. Dengan begitu invarian OK + Sigma anak + hilang = Masuk tetap utuh
    -- berapa kali pun hasilnya diedit.
    DECLARE @Masuk INT = @Qty;
    IF @FirstSendLogId IS NOT NULL
        SET @Masuk = ISNULL((
            SELECT TOP 1 prev.qty_after
            FROM article_workflow_logs prev
            INNER JOIN article_workflows paw ON paw.article_workflow_id = prev.article_workflow_id
            WHERE prev.bundle_id = @BundleId AND prev.deleted_at IS NULL
              AND prev.log_kind IN ('Creation', 'Kirim', 'Split', 'Dikembalikan')
              AND (paw.sort_order < @SortOrder
                   OR (paw.sort_order = @SortOrder
                       AND (prev.created_at < @FirstSendAt
                            OR (prev.created_at = @FirstSendAt AND prev.workflow_log_id < @FirstSendLogId))))
            ORDER BY paw.sort_order DESC, prev.created_at DESC, prev.workflow_log_id DESC
        ), @Qty);

    DECLARE @ExistingChildQty INT = ISNULL((
        SELECT SUM(sr.qty) FROM bundle_split_results sr
        WHERE sr.split_id IN (SELECT SplitId FROM @StepSplits)
    ), 0);

    DECLARE @ExistingMissing INT = @Masuk - @Qty - @ExistingChildQty;

    DECLARE @IsLocked BIT = CASE WHEN EXISTS (
        SELECT 1 FROM article_workflow_logs
        WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId
          AND deleted_at IS NULL AND log_kind IN ('Kirim', 'Split', 'Dikembalikan')
          AND lock_id IS NOT NULL
    ) THEN 1 ELSE 0 END;

    -- Lock otomatis: station berikutnya sudah menyentuh bundle ini. Namanya dibawa ke
    -- client untuk tooltip "Sudah diproses {nama step}".
    DECLARE @BlockedByStepName VARCHAR(255);
    SELECT TOP 1 @BlockedByStepName = aw2.step_name
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl.article_workflow_id
    WHERE awl.bundle_id = @BundleId AND awl.deleted_at IS NULL
      AND awl.log_kind IN ('Creation', 'Kirim', 'Split', 'Dikembalikan')
      AND aw2.sort_order > @SortOrder
    ORDER BY aw2.sort_order ASC;

    DECLARE @NextStationDone BIT = CASE WHEN @BlockedByStepName IS NULL THEN 0 ELSE 1 END;

    -- Kategori TidakLengkap hanya ditawarkan di step Bundling/Loading (is_bundling = 1):
    -- part kurang hanya bisa dinyatakan oleh station yang merakit bundle-nya.
    DECLARE @IsBundlingStep BIT = ISNULL((
        SELECT is_bundling FROM article_workflows WHERE article_workflow_id = @ArticleWorkflowId
    ), 0);

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
        @BlockedByStepName AS BlockedByStepName,
        @IsBundlingStep AS IsBundlingStep,
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
-- SIS_BundleSplit_MissingByArticle -- angka Hilang / Lebih / Tidak lengkap di kartu
-- artikel stasiun.
--   Hilang       = Sigma missing_qty POSITIF induk artikel ini
--   Lebih        = Sigma missing_qty negatif (absolut)
--   Tidak lengkap= Sigma qty bundle ber-status 'TidakLengkap' artikel ini (bundle ANAK)
--   LegacyMissingQty (ad hoc 2026-10-31) = hilang GAYA LAMA (article_workflow_logs.qty_lost
--                  sebelum app_settings.bundle_split_migrated_at). Angka TERPISAH, jangan
--                  dijumlahkan ke MissingQty -- lihat alasannya di cabang UNION ketiga.
-- Dipanggil sekali untuk semua artikel yang tampil di tab WIP.
--
-- @ResourceId (BARU, permintaan owner 2026-10-30 -- MENGGANTI aturan "semua station" di
-- Prompt 82 baris 122): kalau diisi, ketiga angka hanya menghitung selisih yang
-- DINYATAKAN HILANG OLEH line itu sendiri, bukan gabungan semua line. Tanpa ini tiap
-- line melihat angka yang sama persis untuk artikel yang sama, sehingga tidak ada yang
-- merasa angka itu miliknya.
--
-- Cara atribusi -- penting, baca sebelum mengubah:
--   missing_qty adalah SALDO BERSIH di induk (bertambah saat Kirim Hasil menyisakan
--   barang, berkurang saat "Barang ketemu"), dan qty per kejadian TIDAK disimpan sebagai
--   angka di mana pun -- baris log 'Hilang'/'Ketemu' memakai qty_delta = 0 dan hanya
--   menulis jumlahnya di kolom reason sebagai teks. Jadi saldo TIDAK bisa dipecah
--   per line dengan menjumlahkan baris log. Yang dipakai: SELURUH saldo terbuka satu
--   induk menjadi milik resource pada baris log 'Hilang' TERAKHIR bundle itu (pola LIFO
--   yang sama dengan urutan kandidat di SIS_BundleSplit_MissingBundles). Konsekuensinya
--   kalau dua line pernah kehilangan di bundle yang SAMA, sisa terbukanya dihitung utuh
--   ke line yang paling terakhir menyatakan hilang -- di praktiknya satu bundle hanya
--   dipegang satu line pada satu waktu.
--   Induk ber-selisih TANPA baris log 'Hilang' (data migrasi/manual) jatuh ke
--   bundles.resource_id supaya tidak ada angka yang hilang dari semua kartu.
--   'Tidak lengkap' memakai bundles.resource_id bundle ANAK-nya (anak mewarisi line induk).
--
-- Cakupannya SELURUH riwayat artikel: semua induk yang saldonya masih terbuka ikut
-- terhitung, termasuk bundle yang sudah lama lewat dari station ini -- bukan hanya
-- bundle yang sedang tampil di tab WIP. Angka turun HANYA lewat "Barang ketemu"
-- (SIS_BundleSplit_Manage @Action = 'FOUND' mengurangi missing_qty induk tujuan).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_BundleSplit_MissingByArticle
    @ArticleId  INT = NULL,    -- NULL = semua artikel yang punya salah satu angka di atas
    @ResourceId INT = NULL     -- NULL = semua line (dipakai admin/laporan)
AS
BEGIN
    SET NOCOUNT ON;

    -- Ad hoc (2026-10-31): batas dua jalur reject/hilang -- lihat sql/v_84_reject_unified.sql.
    DECLARE @MigratedAt DATETIME2 = ISNULL(
        (SELECT TOP 1 bundle_split_migrated_at FROM app_settings WHERE deleted_at IS NULL),
        '9999-12-31');

    -- Empat angka dari tiga "bentuk" baris yang berbeda (selisih di induk, qty di anak,
    -- kolom qty_lost gaya lama), jadi digabung lewat UNION ALL lalu dijumlahkan per
    -- artikel -- bukan satu WHERE.
    SELECT x.article_id AS ArticleId,
           SUM(x.MissingQty) AS MissingQty,
           SUM(x.OverQty) AS OverQty,
           SUM(x.IncompleteQty) AS IncompleteQty,
           SUM(x.LegacyMissingQty) AS LegacyMissingQty
    FROM (
        SELECT b.article_id,
               CASE WHEN b.missing_qty > 0 THEN b.missing_qty ELSE 0 END AS MissingQty,
               CASE WHEN b.missing_qty < 0 THEN -b.missing_qty ELSE 0 END AS OverQty,
               0 AS IncompleteQty,
               0 AS LegacyMissingQty
        FROM bundles b
        OUTER APPLY (
            SELECT TOP 1 l.resource_id
            FROM article_workflow_logs l
            WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
            ORDER BY l.created_at DESC, l.workflow_log_id DESC
        ) lm
        WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.missing_qty <> 0
          AND (@ArticleId IS NULL OR b.article_id = @ArticleId)
          AND (@ResourceId IS NULL OR ISNULL(lm.resource_id, b.resource_id) = @ResourceId)

        UNION ALL

        SELECT b.article_id, 0, 0, b.qty, 0
        FROM bundles b
        WHERE b.deleted_at IS NULL AND b.[status] = 'TidakLengkap' AND b.qty > 0
          AND (@ArticleId IS NULL OR b.article_id = @ArticleId)
          AND (@ResourceId IS NULL OR b.resource_id = @ResourceId)

        UNION ALL

        -- Ad hoc (2026-10-31): HILANG GAYA LAMA -- kolom article_workflow_logs.qty_lost
        -- pada baris SEBELUM tanggal migrasi. Dipisah dari MissingQty dan TIDAK boleh
        -- digabung ke sana: angka ini bukan saldo terbuka melainkan riwayat beku --
        -- tidak ada mekanisme "Barang ketemu" untuk model lama, jadi ia tidak akan
        -- pernah turun, sedangkan MissingQty yang bisa diklik di kartu memang harus
        -- bisa ditutup lewat modal itu. Baris ADJUSTMENT boleh negatif (mutasi keluar
        -- dari kategori), sama dengan cara v_bundle_reject_unified membacanya.
        -- Migrasi 86: baris yang qty_lost-nya SUDAH dilipat ke bundles.missing_qty
        -- tidak dihitung lagi di sini -- angkanya kini ikut MissingQty di cabang
        -- pertama. Jadi kolom ini menyusut sendiri jadi 0 setelah migrasi dijalankan,
        -- tanpa perlu ubah kode lagi.
        SELECT b.article_id, 0, 0, 0, awl.qty_lost
        FROM article_workflow_logs awl
        INNER JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        WHERE awl.deleted_at IS NULL AND awl.qty_lost <> 0
          AND awl.created_at < @MigratedAt
          AND (@ArticleId IS NULL OR b.article_id = @ArticleId)
          AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
          AND NOT EXISTS (SELECT 1 FROM qty_lost_migration_items i
                          WHERE i.workflow_log_id = awl.workflow_log_id)
    ) x
    GROUP BY x.article_id;
END;
GO

-- ---------------------------------------------------------------------------
-- SIS_BundleSplit_MissingSizes -- isi dropdown Size modal "Barang ketemu":
-- hanya size yang punya selisih TERBUKA (> 0), beserta angkanya.
-- @ResourceId: atribusi line yang SAMA dengan SIS_BundleSplit_MissingByArticle (lihat
-- blok komentar panjang di sana) -- wajib ikut supaya isi dropdown selalu konsisten
-- dengan angka Hilang yang diklik di kartu.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_BundleSplit_MissingSizes
    @ArticleId  INT,
    @ResourceId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT asz.article_size_id AS ArticleSizeId,
           spd.size_name AS SizeName,
           SUM(b.missing_qty) AS MissingQty
    FROM bundles b
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    OUTER APPLY (
        SELECT TOP 1 l.resource_id
        FROM article_workflow_logs l
        WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
        ORDER BY l.created_at DESC, l.workflow_log_id DESC
    ) lm
    WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.article_id = @ArticleId
      AND b.missing_qty > 0
      AND (@ResourceId IS NULL OR ISNULL(lm.resource_id, b.resource_id) = @ResourceId)
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
-- @ResourceId: atribusi line yang SAMA dengan SIS_BundleSplit_MissingByArticle (lihat
-- blok komentar panjang di sana). Wajib ikut: tanpa ini satu line bisa menutup
-- kehilangan milik line lain, dan angka Hilang di kartunya sendiri tidak berkurang
-- sepeser pun walau dia sudah mencatat barang ketemu.
-- ---------------------------------------------------------------------------
-- Ad hoc (2026-10-31): @ArticleSizeId jadi OPSIONAL dan @ArticleId ditambahkan, supaya SP
-- yang sama bisa dipakai dua cara:
--   (a) @ArticleSizeId diisi  -> kandidat alokasi satu size (perilaku lama, dipakai blok
--                                "Akan dicatat ke")
--   (b) @ArticleId diisi      -> DAFTAR seluruh bundle yang masih punya selisih terbuka di
--                                artikel itu, lintas size. Dipakai daftar "Bundle yang masih
--                                hilang" di bawah form Barang ketemu, supaya operator bisa
--                                mencocokkan barang yang dipegangnya dengan nomor bundle
--                                sebelum memilih size. Panggil dengan @Qty NULL (tanpa
--                                alokasi) -- AllocQty-nya 0 semua.
-- SizeName ikut dikembalikan: wajib untuk cara (b) yang lintas size, dan tidak mengganggu
-- cara (a).
CREATE OR ALTER PROCEDURE SIS_BundleSplit_MissingBundles
    @ArticleSizeId INT = NULL,
    @Qty           INT = NULL,
    @ResourceId    INT = NULL,
    @ArticleId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @ArticleSizeId IS NULL AND @ArticleId IS NULL RETURN;

    ;WITH Candidates AS (
        SELECT b.bundle_id, b.root_bundle_id, b.bundle_no, b.serial, b.missing_qty, b.article_id,
               spd.size_name AS SizeName, spd.sort_order AS SizeSortOrder,
               ISNULL((
                   SELECT MAX(l.created_at) FROM article_workflow_logs l
                   WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
               ), b.created_at) AS LastMissingAt
        FROM bundles b
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        OUTER APPLY (
            SELECT TOP 1 l.resource_id
            FROM article_workflow_logs l
            WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
            ORDER BY l.created_at DESC, l.workflow_log_id DESC
        ) lm
        WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.missing_qty > 0
          AND (@ArticleSizeId IS NULL OR b.article_size_id = @ArticleSizeId)
          AND (@ArticleId IS NULL OR b.article_id = @ArticleId)
          AND (@ResourceId IS NULL OR ISNULL(lm.resource_id, b.resource_id) = @ResourceId)
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
           o.SizeName AS SizeName,
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

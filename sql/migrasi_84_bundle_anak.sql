-- ============================================================================
-- Prompt 82 (revisi) -- MIGRASI DATA LAMA, versi RINGAN.
--
-- Hanya mengisi kolom default di `bundles` dan qty_delta/qty_after/log_kind di log
-- lama. TIDAK melahirkan bundle anak, TIDAK mengisi missing_qty, TIDAK menyentuh
-- needs_reprint. Reject lama TETAP jadi angka di kolom qty_reject_*/qty_lost dan
-- tetap jadi sumber laporan untuk log SEBELUM tanggal migrasi (lihat "dua jalur"
-- di kepala sql/v_84_reject_unified.sql).
--
-- SEKALI JALAN, idempotent (ditandai tabel bundle_split_migration), SATU transaksi.
-- Verifikasi tunggal, gagal = ROLLBACK seluruhnya:
--     Sigma qty_delta per bundle = bundles.qty, untuk setiap bundle yang PUNYA log.
--
-- URUTAN EKSEKUSI MANUAL (ke database produksi dijalankan developer sendiri):
--   1. sql/alter_84_bundle_anak.sql        (kolom + tabel baru)
--   2. sql/migrasi_84_bundle_anak.sql      (FILE INI -- sekaligus mencatat tanggal
--                                           migrasi ke app_settings)
--   3. sql/v_84_reject_unified.sql
--      sql/sp_BundleSplit_Manage.sql, sql/sp_BundleSplit_Select.sql,
--      sql/sp_Bundle_Manage.sql, sql/sp_Bundle_ScanInfo.sql,
--      sql/sp_Station_Operations.sql, sql/cutting/sp_78_Cutting.sql,
--      sql/cutting/sp_80_CuttingTake.sql
--
-- LINGKUP: bundle HIDUP dan log HIDUP. Log tanpa bundle_id (Cutting per size) TIDAK
-- disentuh. Log terhapus tidak dimigrasi. Bundle tanpa log (382 stok cutting) tidak
-- diberi baris Creation -- bundles.qty-nya dibiarkan, dan baris Creation lahir sendiri
-- saat bundle itu pertama kali dikirim (SIS_Bundle_Manage / SIS_CuttingBundle_Take).
--
-- Rumus (per bundle, log diurutkan article_workflows.sort_order lalu created_at):
--   log PERTAMA   : qty_delta = +(qty_ok + Sigma reject + qty_lost), qty_after = nilai
--                   itu, log_kind = 'Creation'
--   log BERIKUTNYA: qty_delta = qty_ok - qty_after sebelumnya, qty_after = qty_ok,
--                   log_kind = 'Kirim'. Selisih tak tercatat (282 bundle) terserap di
--                   delta ini, TIDAK dicatat terpisah.
--   log ADJUSTMENT: log_kind = 'Kirim', rumus sama.
-- Terakhir: bundles.qty = qty_after log terakhir.
-- ============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
GO

-- ---------------------------------------------------------------------------
-- Penanda idempotensi
-- ---------------------------------------------------------------------------
IF OBJECT_ID('bundle_split_migration', 'U') IS NULL
    CREATE TABLE bundle_split_migration(
        migration_id  INT PRIMARY KEY IDENTITY(1,1),
        ran_at        DATETIME2 NOT NULL CONSTRAINT DF_bsmig_ran_at DEFAULT SYSDATETIME(),
        summary       NVARCHAR(MAX) NULL
    );
GO

IF EXISTS (SELECT 1 FROM bundle_split_migration)
BEGIN
    PRINT 'Migrasi Prompt 82 sudah pernah dijalankan (bundle_split_migration terisi) -- dilewati.';
    SET NOEXEC ON;
END
GO

BEGIN TRAN;
BEGIN TRY

    DECLARE @RanAt DATETIME2 = SYSDATETIME();

    ------------------------------------------------------------------
    -- 1. Semua bundle lama = induk utama, status OK, tanpa selisih
    ------------------------------------------------------------------
    -- Tidak ada anak yang dilahirkan dari reject lama (lihat "Di luar scope" prompt).
    -- needs_reprint SENGAJA tidak disentuh: tidak ada stiker lama yang perlu dicetak ulang.
    UPDATE b
    SET parent_bundle_id = NULL,
        root_bundle_id = b.bundle_id,
        sequence_no = 0,
        [status] = 'OK',
        reject_category = NULL,
        reject_reason = NULL,
        missing_qty = 0
    FROM bundles b
    WHERE b.deleted_at IS NULL;

    ------------------------------------------------------------------
    -- 2. Rantai qty di log lama
    ------------------------------------------------------------------
    -- rn = urutan baris dalam satu bundle. T1 (baris PERTAMA) = qty yang MASUK ke
    -- bundle itu = qty_ok + semua reject + qty_lost; untuk baris Bundling (kasus
    -- normal) reject-nya 0 jadi T1 = qty bundle.
    SELECT awl.workflow_log_id,
           awl.bundle_id,
           awl.qty_ok,
           awl.qty_ok + awl.qty_reject_print + awl.qty_reject_fabric + awl.qty_reject_sewing
               + awl.qty_reject_rework + awl.qty_lost AS T1,
           ROW_NUMBER() OVER (PARTITION BY awl.bundle_id
                              ORDER BY aw.sort_order, awl.created_at, awl.workflow_log_id) AS rn
    INTO #l
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
    WHERE awl.deleted_at IS NULL AND awl.bundle_id IS NOT NULL;

    CREATE UNIQUE CLUSTERED INDEX IX_l ON #l(workflow_log_id);
    CREATE INDEX IX_l_bundle ON #l(bundle_id, rn);

    -- qty_after tiap baris: rn = 1 -> T1, selebihnya -> qty_ok baris itu.
    -- qty_delta: rn = 1 -> T1 (bundle lahir dari nol), selebihnya -> qty_ok dikurangi
    -- qty_after baris SEBELUMNYA (LAG atas rumus qty_after yang sama).
    SELECT l.workflow_log_id,
           l.bundle_id,
           l.rn,
           CASE WHEN l.rn = 1 THEN l.T1 ELSE l.qty_ok END AS QtyAfter,
           CASE WHEN l.rn = 1
                THEN l.T1
                ELSE l.qty_ok - LAG(CASE WHEN l.rn = 1 THEN l.T1 ELSE l.qty_ok END)
                                OVER (PARTITION BY l.bundle_id ORDER BY l.rn)
           END AS QtyDelta,
           CAST(CASE WHEN l.rn = 1 THEN 'Creation' ELSE 'Kirim' END AS VARCHAR(15)) AS LogKind
    INTO #chain
    FROM #l l;

    CREATE UNIQUE CLUSTERED INDEX IX_chain ON #chain(workflow_log_id);
    CREATE INDEX IX_chain_bundle ON #chain(bundle_id, rn);

    UPDATE awl
    SET awl.qty_delta = c.QtyDelta,
        awl.qty_after = c.QtyAfter,
        awl.log_kind = c.LogKind
    FROM article_workflow_logs awl
    INNER JOIN #chain c ON c.workflow_log_id = awl.workflow_log_id;

    ------------------------------------------------------------------
    -- 3. bundles.qty = qty_after log terakhir (hanya bundle yang punya log)
    ------------------------------------------------------------------
    UPDATE b
    SET qty = lastrow.QtyAfter
    FROM bundles b
    CROSS APPLY (
        SELECT TOP 1 c.QtyAfter
        FROM #chain c
        WHERE c.bundle_id = b.bundle_id
        ORDER BY c.rn DESC
    ) lastrow
    WHERE b.deleted_at IS NULL;

    ------------------------------------------------------------------
    -- 4. VERIFIKASI (gagal = ROLLBACK seluruhnya)
    ------------------------------------------------------------------
    -- Sigma qty_delta per bundle = bundles.qty, untuk tiap bundle yang PUNYA log.
    -- Bundle tanpa log sengaja dikecualikan: qty-nya memang belum punya rantai log
    -- (baris Creation-nya lahir nanti saat bundle pertama kali dikirim).
    DECLARE @BadCount INT, @BadSerial VARCHAR(20), @BadQty INT, @BadDelta INT;

    SELECT @BadCount = COUNT(*) FROM (
        SELECT b.bundle_id
        FROM bundles b
        INNER JOIN (SELECT DISTINCT bundle_id FROM #chain) h ON h.bundle_id = b.bundle_id
        CROSS APPLY (
            SELECT ISNULL(SUM(awl.qty_delta), 0) AS Total
            FROM article_workflow_logs awl
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
        ) d
        WHERE b.deleted_at IS NULL AND d.Total <> b.qty
    ) x;

    IF @BadCount > 0
    BEGIN
        -- Sebut satu contohnya supaya langsung bisa ditelusuri tanpa query manual.
        SELECT TOP 1 @BadSerial = b.serial, @BadQty = b.qty, @BadDelta = d.Total
        FROM bundles b
        INNER JOIN (SELECT DISTINCT bundle_id FROM #chain) h ON h.bundle_id = b.bundle_id
        CROSS APPLY (
            SELECT ISNULL(SUM(awl.qty_delta), 0) AS Total
            FROM article_workflow_logs awl
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
        ) d
        WHERE b.deleted_at IS NULL AND d.Total <> b.qty
        ORDER BY b.bundle_id;

        ROLLBACK TRAN;
        -- Severity 16 di dalam TRY melompat ke CATCH; CATCH meneruskannya lewat THROW.
        RAISERROR('MIGRASI DIBATALKAN. %d bundle dengan SUM(qty_delta) <> bundles.qty. Contoh: %s (qty %d, SUM delta %d).',
                  16, 1, @BadCount, @BadSerial, @BadQty, @BadDelta);
    END

    ------------------------------------------------------------------
    -- 5. Tanggal migrasi -> app_settings (batas "dua jalur" laporan)
    ------------------------------------------------------------------
    -- Log dengan created_at < tanggal ini dibaca dari qty_reject_*/qty_lost;
    -- sesudahnya dari bundle anak + missing_qty. Lihat sql/v_84_reject_unified.sql.
    IF EXISTS (SELECT 1 FROM app_settings WHERE deleted_at IS NULL)
        UPDATE app_settings
        SET bundle_split_migrated_at = @RanAt, updated_at = @RanAt
        WHERE deleted_at IS NULL;
    ELSE
        -- Belum ada baris app_settings sama sekali. created_by NOT NULL tanpa default,
        -- jadi diisi Id user mana pun yang ada (tabel Users: PascalCase, tanpa soft delete).
        INSERT INTO app_settings (auto_print_coupon_active, bundle_split_migrated_at, created_at, created_by)
        SELECT 1, @RanAt, @RanAt, (SELECT MIN(Id) FROM Users);

    ------------------------------------------------------------------
    -- 6. Ringkasan
    ------------------------------------------------------------------
    DECLARE @BundleTotal   INT = (SELECT COUNT(*) FROM bundles WHERE deleted_at IS NULL);
    DECLARE @BundleWithLog INT = (SELECT COUNT(DISTINCT bundle_id) FROM #chain);
    DECLARE @LogTotal      INT = (SELECT COUNT(*) FROM #chain);
    DECLARE @CreationRows  INT = (SELECT COUNT(*) FROM #chain WHERE LogKind = 'Creation');
    DECLARE @TotalPcs      INT = (SELECT ISNULL(SUM(qty), 0) FROM bundles WHERE deleted_at IS NULL);

    -- Bundle yang baris log TERAKHIRNYA adalah baris ADJUSTMENT: qty-nya ikut qty_ok
    -- baris itu, karena rumus prompt dipakai apa adanya untuk ADJUSTMENT. Dilaporkan
    -- supaya bisa dicek manual sesudah migrasi.
    DECLARE @EndsOnAdjust INT = ISNULL((
        SELECT COUNT(*)
        FROM (SELECT DISTINCT bundle_id FROM #chain) h
        CROSS APPLY (
            SELECT TOP 1 awl.log_type
            FROM #chain c
            INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = c.workflow_log_id
            WHERE c.bundle_id = h.bundle_id
            ORDER BY c.rn DESC
        ) last_row
        WHERE last_row.log_type = 'ADJUSTMENT'
    ), 0);

    DECLARE @Summary NVARCHAR(MAX) =
        'Bundle hidup: ' + CAST(@BundleTotal AS VARCHAR(10))
        + ' (punya log: ' + CAST(@BundleWithLog AS VARCHAR(10))
        + ', tanpa log: ' + CAST(@BundleTotal - @BundleWithLog AS VARCHAR(10)) + ')'
        + ' | Log dimigrasi: ' + CAST(@LogTotal AS VARCHAR(10))
        + ' (Creation: ' + CAST(@CreationRows AS VARCHAR(10))
        + ', Kirim: ' + CAST(@LogTotal - @CreationRows AS VARCHAR(10)) + ')'
        + ' | Total pcs (SUM bundles.qty): ' + CAST(@TotalPcs AS VARCHAR(20))
        + ' | Bundle yang log terakhirnya ADJUSTMENT: ' + CAST(@EndsOnAdjust AS VARCHAR(10))
        + ' | Tanggal migrasi: ' + CONVERT(VARCHAR(23), @RanAt, 121);

    INSERT INTO bundle_split_migration (ran_at, summary) VALUES (@RanAt, @Summary);

    PRINT @Summary;

    COMMIT TRAN;

    SELECT @Summary AS Summary;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    THROW;
END CATCH
GO

SET NOEXEC OFF;
GO

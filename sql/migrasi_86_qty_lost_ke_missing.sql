-- ============================================================================
-- Migrasi 86 (2026-10-31) -- LIPAT hilang gaya lama (article_workflow_logs.qty_lost)
-- menjadi saldo gaya baru (bundles.missing_qty), supaya mulai sekarang hanya ADA SATU
-- angka "hilang" yang dibaca di mana pun dan bisa ditutup lewat "Barang ketemu".
--
-- LATAR: migrasi Prompt 82 (sql/migrasi_84_bundle_anak.sql) SENGAJA tidak menyentuh
-- qty_lost -- hilang lama tetap jadi angka di kolom lama dan dibaca lewat "jalur LAMA"
-- (lihat sql/v_84_reject_unified.sql). Akibatnya satu PO bisa punya dua angka hilang
-- yang tidak bisa dijumlahkan sembarangan, dan yang lama tidak akan pernah bisa
-- berkurang karena tidak punya mekanisme penutup. Script ini menutup celah itu.
--
-- YANG DILAKUKAN, per baris log hidup dengan qty_lost <> 0 (SEMUA tanggal):
--   1. bundles.missing_qty += qty_lost pada bundle baris itu
--   2. lahir satu baris log penyerta log_kind = 'Hilang' -- SALINAN konteks baris asal
--      (step, divisi, resource, employee, created_at, lock_id) dengan qty 0 dan
--      jumlahnya di kolom reason, PERSIS bentuk baris Hilang yang ditulis
--      SIS_BundleSplit_Manage. Baris ini yang membuat saldo ter-ATRIBUSI ke line yang
--      dulu mencatatnya (SIS_BundleSplit_MissingByArticle memakai baris 'Hilang'
--      TERAKHIR bundle itu); tanpa baris ini saldo jatuh ke bundles.resource_id yang
--      belum tentu line yang sama.
--   3. pemetaan baris asal -> baris baru disimpan di qty_lost_migration_items, dipakai
--      dua hal: idempotensi, dan MENCEGAH DOBEL (pembaca jalur lama menyaring baris
--      yang sudah dilipat lewat NOT EXISTS ke tabel ini).
--
-- YANG TIDAK DILAKUKAN -- penting:
--   * qty_lost TIDAK dinolkan. Kolom itu masih dibaca banyak tempat yang BELUM
--     dialihkan ke v_bundle_reject_unified (sp_Report_Produksi, sp_Report_Bundle,
--     sp_Report_LineDetail, sp_Article_Wip, sp_Print_Render, dan -- yang paling
--     berbahaya -- fn_55_workflow_saldo yang memakainya sebagai penjaga saldo).
--     Menolkannya akan mengubah laporan historis dan melonggarkan penjaga saldo.
--     Riwayatnya dibiarkan utuh; yang diubah hanya SIAPA yang boleh membacanya
--     sebagai "Hilang".
--   * qty_reject_* (reject gaya lama) TIDAK disentuh sama sekali -- app_settings
--     .bundle_split_migrated_at tetap berlaku untuk kategori reject. Yang pindah
--     jalur hanya irisan "Hilang".
--
-- EFEK SAMPING YANG DISENGAJA:
--   * Angka Hilang di kartu stasiun melonjak (jadi saldo sebenarnya) dan menjadi
--     bisa diklik -> "Barang ketemu" kini bisa menutup kehilangan lama.
--   * Di v_bundle_reject_unified, kehilangan lama satu bundle yang terjadi di
--     beberapa tanggal menyatu jadi SATU baris saldo bertanggal kejadian TERAKHIR
--     (cabang C memang per induk, bukan per kejadian). Granularitas per periode
--     untuk kehilangan lama berkurang; rinciannya tetap terbaca dari kolom qty_lost
--     dan dari tabel pemetaan di bawah.
--
-- URUTAN EKSEKUSI MANUAL (wajib berurutan -- view di nomor 2 menunjuk tabel yang
-- dibuat di nomor 1, dan CREATE VIEW gagal kalau tabelnya belum ada):
--   1. sql/migrasi_86_qty_lost_ke_missing.sql   (FILE INI)
--   2. sql/v_84_reject_unified.sql              (cabang LAMA menyaring yang sudah dilipat)
--   3. sql/sp_BundleSplit_Select.sql            (LegacyMissingQty ikut menyaring)
--
-- SEKALI JALAN, idempotent (baris yang sudah terdaftar di qty_lost_migration_items
-- dilewati), SATU transaksi, verifikasi gagal = ROLLBACK seluruhnya.
-- ============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
GO

-- ---------------------------------------------------------------------------
-- Tabel penanda + pemetaan. DIBUAT DI LUAR transaksi dan SEBELUM penjaga
-- idempotensi: v_bundle_reject_unified dan SIS_BundleSplit_MissingByArticle
-- menunjuk qty_lost_migration_items, jadi tabelnya harus tetap ada walau migrasi
-- ini dilewati (mis. dijalankan ulang, atau database baru yang belum punya data lama).
-- Keduanya juga ada di sql/create_tables_tmos_final.sql.
-- ---------------------------------------------------------------------------
IF OBJECT_ID('qty_lost_migration', 'U') IS NULL
    CREATE TABLE qty_lost_migration(
        migration_id INT PRIMARY KEY IDENTITY(1,1),
        ran_at       DATETIME2 NOT NULL CONSTRAINT DF_qlmig_ran_at DEFAULT SYSDATETIME(),
        summary      NVARCHAR(MAX) NULL
    );
GO

IF OBJECT_ID('qty_lost_migration_items', 'U') IS NULL
    CREATE TABLE qty_lost_migration_items(
        -- PK = baris log ASAL: satu baris qty_lost hanya boleh dilipat sekali.
        workflow_log_id     INT PRIMARY KEY,
        bundle_id           INT NOT NULL,
        qty                 INT NOT NULL,   -- nilai qty_lost yang dilipat (boleh negatif)
        new_workflow_log_id INT NOT NULL,   -- baris log 'Hilang' penyerta yang dibuat
        ran_at              DATETIME2 NOT NULL CONSTRAINT DF_qlmigi_ran_at DEFAULT SYSDATETIME()
    );
GO

-- ---------------------------------------------------------------------------
-- Daftar kerja: baris log HIDUP, qty_lost <> 0, bundle HIDUP, belum pernah dilipat.
-- ---------------------------------------------------------------------------
DECLARE @Work TABLE (
    RowNo             INT IDENTITY(1,1) PRIMARY KEY,
    WorkflowLogId     INT,
    BundleId          INT,
    ArticleWorkflowId INT,
    DivisionId        INT,
    ResourceId        INT,
    EmployeeId        INT,
    Qty               INT,
    QtyAfter          INT,
    LockId            INT,
    CreatedAt         DATETIME2,
    CreatedBy         INT
);

INSERT INTO @Work (WorkflowLogId, BundleId, ArticleWorkflowId, DivisionId, ResourceId,
                   EmployeeId, Qty, QtyAfter, LockId, CreatedAt, CreatedBy)
SELECT l.workflow_log_id, l.bundle_id, l.article_workflow_id, l.division_id, l.resource_id,
       l.employee_id, l.qty_lost, l.qty_after, l.lock_id, l.created_at, l.created_by
FROM article_workflow_logs l
INNER JOIN bundles b ON b.bundle_id = l.bundle_id AND b.deleted_at IS NULL
WHERE l.deleted_at IS NULL
  AND l.qty_lost <> 0
  AND NOT EXISTS (SELECT 1 FROM qty_lost_migration_items i WHERE i.workflow_log_id = l.workflow_log_id)
ORDER BY l.created_at, l.workflow_log_id;

DECLARE @Total INT = (SELECT COUNT(*) FROM @Work);
DECLARE @TotalQty INT = ISNULL((SELECT SUM(Qty) FROM @Work), 0);

-- RETURN (bukan NOEXEC): @Work adalah variabel tabel, jadi daftar kerja dan
-- transaksinya WAJIB berada di SATU batch -- tidak boleh ada GO di antaranya.
IF @Total = 0
BEGIN
    PRINT 'Tidak ada baris qty_lost yang perlu dilipat -- semuanya sudah pernah dimigrasi. Dilewati.';
    RETURN;
END

BEGIN TRAN;
BEGIN TRY

    ------------------------------------------------------------------
    -- Snapshot saldo SEBELUM, untuk verifikasi di akhir.
    ------------------------------------------------------------------
    SELECT b.bundle_id, b.missing_qty AS MissingBefore
    INTO #saldo_before
    FROM bundles b
    WHERE b.bundle_id IN (SELECT BundleId FROM @Work);

    DECLARE @RowNo INT = 1, @MaxRowNo INT = (SELECT MAX(RowNo) FROM @Work);
    DECLARE @WLogId INT, @WBundleId INT, @WAwId INT, @WDivId INT, @WResId INT,
            @WEmpId INT, @WQty INT, @WQtyAfter INT, @WLockId INT,
            @WCreatedAt DATETIME2, @WCreatedBy INT;

    WHILE @RowNo <= @MaxRowNo
    BEGIN
        SELECT @WLogId = WorkflowLogId, @WBundleId = BundleId, @WAwId = ArticleWorkflowId,
               @WDivId = DivisionId, @WResId = ResourceId, @WEmpId = EmployeeId,
               @WQty = Qty, @WQtyAfter = QtyAfter, @WLockId = LockId,
               @WCreatedAt = CreatedAt, @WCreatedBy = CreatedBy
        FROM @Work WHERE RowNo = @RowNo;

        -- Baris penyerta 'Hilang'. Bentuknya PERSIS seperti yang ditulis
        -- SIS_BundleSplit_Manage: qty_ok/qty_delta 0, jumlah hanya di reason, tanpa
        -- tujuan serah. Dengan begitu ia tidak muncul di tab OUT/IN, tidak mengubah
        -- frontier WIP, dan tidak ikut hitungan upah mana pun -- fungsinya murni
        -- JEJAK + ATRIBUSI line. created_at memakai tanggal baris ASAL supaya laporan
        -- berbasis periode tetap menaruhnya di periode yang benar.
        INSERT INTO article_workflow_logs (
            article_workflow_id, bundle_id, article_size_id, division_id, resource_id,
            employee_id, qty_ok, log_type, qty_delta, qty_after, log_kind, reason,
            target_division_id, received_at, lock_id, created_at, created_by
        )
        VALUES (
            @WAwId, @WBundleId, NULL, @WDivId, @WResId,
            @WEmpId, 0, 'NORMAL', 0, @WQtyAfter, 'Hilang',
            'Migrasi: ' + CAST(@WQty AS VARCHAR(10)) + ' pcs hilang gaya lama (qty_lost baris #'
                + CAST(@WLogId AS VARCHAR(10)) + ')',
            NULL, NULL, @WLockId, @WCreatedAt, @WCreatedBy
        );

        DECLARE @NewLogId INT = CAST(SCOPE_IDENTITY() AS INT);

        UPDATE bundles
        SET missing_qty = missing_qty + @WQty
        WHERE bundle_id = @WBundleId;

        INSERT INTO qty_lost_migration_items (workflow_log_id, bundle_id, qty, new_workflow_log_id)
        VALUES (@WLogId, @WBundleId, @WQty, @NewLogId);

        SET @RowNo += 1;
    END

    ------------------------------------------------------------------
    -- Verifikasi 1: tiap bundle naik PERSIS sebesar total qty_lost-nya.
    ------------------------------------------------------------------
    DECLARE @BadBundle INT = (
        SELECT COUNT(*)
        FROM #saldo_before sb
        INNER JOIN bundles b ON b.bundle_id = sb.bundle_id
        CROSS APPLY (SELECT SUM(w.Qty) AS q FROM @Work w WHERE w.BundleId = sb.bundle_id) x
        WHERE b.missing_qty <> sb.MissingBefore + ISNULL(x.q, 0)
    );

    IF @BadBundle > 0
    BEGIN
        -- RAISERROR severity 16 di dalam TRY langsung melompat ke CATCH (yang rollback).
        RAISERROR('Verifikasi gagal: %d bundle saldonya tidak naik sesuai qty_lost.', 16, 1, @BadBundle);
    END

    ------------------------------------------------------------------
    -- Verifikasi 2: tidak boleh ada bundle yang jadi MINUS gara-gara ini.
    -- (missing_qty negatif = "Lebih", sah kalau dari Barang ketemu, TIDAK sah
    --  kalau lahir dari migrasi.)
    ------------------------------------------------------------------
    DECLARE @BadMinus INT = (
        SELECT COUNT(*)
        FROM #saldo_before sb
        INNER JOIN bundles b ON b.bundle_id = sb.bundle_id
        WHERE b.missing_qty < 0 AND sb.MissingBefore >= 0
    );

    IF @BadMinus > 0
    BEGIN
        RAISERROR('Verifikasi gagal: %d bundle jadi saldo minus setelah dilipat.', 16, 1, @BadMinus);
    END

    ------------------------------------------------------------------
    -- Verifikasi 3: jumlah baris yang tercatat = jumlah yang dikerjakan.
    ------------------------------------------------------------------
    DECLARE @Recorded INT = (
        SELECT COUNT(*) FROM qty_lost_migration_items i
        WHERE i.workflow_log_id IN (SELECT WorkflowLogId FROM @Work)
    );

    IF @Recorded <> @Total
    BEGIN
        RAISERROR('Verifikasi gagal: tercatat %d dari %d baris.', 16, 1, @Recorded, @Total);
    END

    DECLARE @Summary NVARCHAR(MAX) =
        N'Lipat qty_lost -> bundles.missing_qty. Baris: ' + CAST(@Total AS NVARCHAR(10))
        + N', pcs: ' + CAST(@TotalQty AS NVARCHAR(10))
        + N', bundle: ' + CAST((SELECT COUNT(DISTINCT BundleId) FROM @Work) AS NVARCHAR(10))
        + N'. qty_lost TIDAK dinolkan; pembaca jalur lama menyaring lewat qty_lost_migration_items.';

    INSERT INTO qty_lost_migration (summary) VALUES (@Summary);

    PRINT @Summary;

    DROP TABLE #saldo_before;
    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR('Migrasi 86 GAGAL, seluruhnya di-rollback: %s', 16, 1, @Err);
END CATCH
GO

-- ---------------------------------------------------------------------------
-- Pemeriksaan sesudah jalan (read-only) -- jalankan manual bila perlu:
--
--   -- saldo per line sesudah dilipat
--   SELECT r.resource_name, SUM(b.missing_qty) AS saldo
--   FROM bundles b
--   OUTER APPLY (SELECT TOP 1 l.resource_id FROM article_workflow_logs l
--                WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
--                ORDER BY l.created_at DESC, l.workflow_log_id DESC) lm
--   LEFT JOIN resources r ON r.resource_id = ISNULL(lm.resource_id, b.resource_id)
--   WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.missing_qty <> 0
--   GROUP BY r.resource_name ORDER BY 2 DESC;
--
--   -- pastikan tidak ada yang terhitung dua kali di view
--   SELECT Category, [Source], SUM(Qty) FROM v_bundle_reject_unified
--   WHERE Category = 'Hilang' GROUP BY Category, [Source];
-- ---------------------------------------------------------------------------

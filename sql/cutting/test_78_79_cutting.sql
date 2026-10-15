/* =============================================================
   Uji Prompt 78-79 -- module Cutting, dengan project/artikel UJI TERPISAH
   supaya tidak menyentuh PO produksi mana pun. Dibersihkan oleh
   sql/cutting/cleanup_test_78_79_cutting.sql.

   Skenario (persis "Verifikasi" Prompt 79 §5):
     1. Hamparan H01: 12 set x 220 lembar (6 set M, 6 set L), target 50
        -> 48 bundle, kode & rentang nomor benar.
     2. Hamparan H02 artikel sama -> numbering lanjut dari M-1321.
     3. Edit SATU bundle di set 2 jadi 60  -> DITOLAK (total 225 <> 220).
     4. Edit DUA bundle jadi 60 & 50       -> DITERIMA, rentang bergeser,
                                              needs_reprint benar.
   ============================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @UserId INT = (SELECT TOP 1 Id FROM Users WHERE Username = 'admin');

-- ---------- fixture ----------
DECLARE @ProjectId INT = (SELECT project_id FROM projects WHERE project_name = 'UJI CUTTING 78-80' AND deleted_at IS NULL);

IF @ProjectId IS NULL
BEGIN
    INSERT INTO projects (customer_id, project_name, no_po, material_name, order_date, created_at, created_by, is_urgent)
    VALUES ((SELECT MIN(buyer_id) FROM buyers WHERE deleted_at IS NULL),
            'UJI CUTTING 78-80', 'UJI.CUT.78', 'Kain Uji', CAST(SYSDATETIME() AS DATE), SYSDATETIME(), @UserId, 0);
    SET @ProjectId = CAST(SCOPE_IDENTITY() AS INT);
END

DECLARE @ArticleId INT = (SELECT article_id FROM articles WHERE project_id = @ProjectId AND deleted_at IS NULL);
DECLARE @SizePackId INT = (SELECT TOP 1 sp.size_pack_id FROM size_packs sp
                           WHERE sp.deleted_at IS NULL
                             AND EXISTS (SELECT 1 FROM size_pack_details d WHERE d.size_pack_id = sp.size_pack_id AND d.size_name = 'M' AND d.deleted_at IS NULL)
                             AND EXISTS (SELECT 1 FROM size_pack_details d WHERE d.size_pack_id = sp.size_pack_id AND d.size_name = 'L' AND d.deleted_at IS NULL)
                           ORDER BY sp.size_pack_id DESC);

IF @ArticleId IS NULL
BEGIN
    INSERT INTO articles (project_id, size_pack_id, article_name, style, color, bundle_target_qty, created_at, created_by)
    VALUES (@ProjectId, @SizePackId, 'ARTIKEL UJI CUTTING', 'UJI', 'Navy', 50, SYSDATETIME(), @UserId);
    SET @ArticleId = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO article_sizes (article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by)
    SELECT @ArticleId, d.size_pack_detail_id, 1320, 0, SYSDATETIME(), @UserId
    FROM size_pack_details d
    WHERE d.size_pack_id = @SizePackId AND d.size_name IN ('M', 'L') AND d.deleted_at IS NULL;
END

DECLARE @SizeM INT = (SELECT asz.article_size_id FROM article_sizes asz
                      JOIN size_pack_details d ON d.size_pack_detail_id = asz.size_pack_detail_id
                      WHERE asz.article_id = @ArticleId AND d.size_name = 'M' AND asz.deleted_at IS NULL);
DECLARE @SizeL INT = (SELECT asz.article_size_id FROM article_sizes asz
                      JOIN size_pack_details d ON d.size_pack_detail_id = asz.size_pack_detail_id
                      WHERE asz.article_id = @ArticleId AND d.size_name = 'L' AND asz.deleted_at IS NULL);

SELECT 'FIXTURE' AS tahap, @ProjectId AS project_id, @ArticleId AS article_id, @SizeM AS size_m, @SizeL AS size_l;

-- ---------- 1. hamparan pertama: 12 set x 220 (6 M, 6 L) ----------
DECLARE @SizesJson NVARCHAR(MAX) =
    '[{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setCount":6},' +
     '{"articleSizeId":' + CAST(@SizeL AS VARCHAR(20)) + ',"setCount":6}]';

-- 4 bundle x 55 per set, 6 set per size = 48 bundle (saran sistem utk 220/50).
DECLARE @BundlesJson NVARCHAR(MAX) = '[';
DECLARE @s INT = 1, @b INT;
WHILE @s <= 6
BEGIN
    SET @b = 1;
    WHILE @b <= 4
    BEGIN
        SET @BundlesJson += '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":' + CAST(@s AS VARCHAR(2)) + ',"qty":55},';
        SET @b += 1;
    END
    SET @s += 1;
END
SET @s = 1;
WHILE @s <= 6
BEGIN
    SET @b = 1;
    WHILE @b <= 4
    BEGIN
        SET @BundlesJson += '{"articleSizeId":' + CAST(@SizeL AS VARCHAR(20)) + ',"setNo":' + CAST(@s AS VARCHAR(2)) + ',"qty":55},';
        SET @b += 1;
    END
    SET @s += 1;
END
SET @BundlesJson = LEFT(@BundlesJson, LEN(@BundlesJson) - 1) + ']';

PRINT '--- 1. CREATE hamparan H01 (12 set x 220) ---';
EXEC SIS_Spread_Manage @Action = 'CREATE', @ArticleId = @ArticleId, @SpreadCode = 'H01',
     @SpreadDate = '2026-10-15', @SetCount = 12, @SheetsPerSet = 220,
     @SizesJson = @SizesJson, @BundlesJson = @BundlesJson, @UserId = @UserId;

DECLARE @Spread1 INT = (SELECT spread_id FROM spreads WHERE article_id = @ArticleId AND spread_code = 'H01' AND deleted_at IS NULL);

SELECT 'H01 ringkas' AS tahap, COUNT(*) AS bundle, SUM(qty) AS pcs,
       MIN(cutting_code) AS kode_min, MAX(cutting_code) AS kode_max
FROM bundles WHERE spread_id = @Spread1 AND deleted_at IS NULL;

SELECT 'H01 size M set 1-2' AS tahap, cutting_code, serial, set_no, bundle_seq, qty, number_from, number_to
FROM bundles WHERE spread_id = @Spread1 AND article_size_id = @SizeM AND set_no <= 2 AND deleted_at IS NULL
ORDER BY bundle_seq;

SELECT 'H01 rentang size' AS tahap, d.size_name, ss.number_from, ss.number_to
FROM spread_sizes ss
JOIN article_sizes asz ON asz.article_size_id = ss.article_size_id
JOIN size_pack_details d ON d.size_pack_detail_id = asz.size_pack_detail_id
WHERE ss.spread_id = @Spread1 ORDER BY d.sort_order;

-- ---------- 2. hamparan kedua artikel sama -> lanjut dari M-1321 ----------
PRINT '--- 2. next number setelah H01 (harus 1321) ---';
EXEC SIS_Cutting_NextNumber @ArticleId = @ArticleId, @ArticleSizeId = @SizeM;
EXEC SIS_Cutting_NextSpreadCode @ArticleId = @ArticleId;

DECLARE @Sizes2 NVARCHAR(MAX) = '[{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setCount":2}]';
DECLARE @Bundles2 NVARCHAR(MAX) =
    '[{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":1,"qty":55},' +
     '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":1,"qty":55},' +
     '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":1,"qty":55},' +
     '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":1,"qty":55},' +
     '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":2,"qty":55},' +
     '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":2,"qty":55},' +
     '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":2,"qty":55},' +
     '{"articleSizeId":' + CAST(@SizeM AS VARCHAR(20)) + ',"setNo":2,"qty":55}]';

EXEC SIS_Spread_Manage @Action = 'CREATE', @ArticleId = @ArticleId, @SpreadCode = 'H02',
     @SpreadDate = '2026-10-15', @SetCount = 2, @SheetsPerSet = 220,
     @SizesJson = @Sizes2, @BundlesJson = @Bundles2, @UserId = @UserId;

DECLARE @Spread2 INT = (SELECT spread_id FROM spreads WHERE article_id = @ArticleId AND spread_code = 'H02' AND deleted_at IS NULL);

SELECT 'H02 (lanjut nomor)' AS tahap, cutting_code, set_no, bundle_seq, qty, number_from, number_to
FROM bundles WHERE spread_id = @Spread2 AND deleted_at IS NULL ORDER BY bundle_seq;

-- ---------- 3. edit SATU bundle di set 2 jadi 60 -> harus DITOLAK ----------
DECLARE @B1 INT = (SELECT bundle_id FROM bundles WHERE spread_id = @Spread1 AND article_size_id = @SizeM AND set_no = 2 AND bundle_seq = 5 AND deleted_at IS NULL);
DECLARE @B2 INT = (SELECT bundle_id FROM bundles WHERE spread_id = @Spread1 AND article_size_id = @SizeM AND set_no = 2 AND bundle_seq = 6 AND deleted_at IS NULL);

PRINT '--- 3. UPDATE_QTY satu bundle jadi 60 (harus ditolak) ---';
BEGIN TRY
    DECLARE @Chg1 NVARCHAR(MAX) = '[{"bundleId":' + CAST(@B1 AS VARCHAR(20)) + ',"qty":60}]';
    EXEC SIS_SpreadBundle_Manage @Action = 'UPDATE_QTY', @BundlesJson = @Chg1, @UserId = @UserId;
    SELECT 'BUG: seharusnya ditolak' AS hasil;
END TRY
BEGIN CATCH
    SELECT 'DITOLAK (benar)' AS hasil, ERROR_MESSAGE() AS pesan;
END CATCH

-- ---------- 4. edit DUA bundle 60 & 50 -> harus DITERIMA ----------
PRINT '--- 4. UPDATE_QTY dua bundle 60 & 50 (harus diterima) ---';
DECLARE @Chg2 NVARCHAR(MAX) =
    '[{"bundleId":' + CAST(@B1 AS VARCHAR(20)) + ',"qty":60},' +
     '{"bundleId":' + CAST(@B2 AS VARCHAR(20)) + ',"qty":50}]';
EXEC SIS_SpreadBundle_Manage @Action = 'UPDATE_QTY', @BundlesJson = @Chg2, @UserId = @UserId;

SELECT 'set 2 setelah edit' AS tahap, cutting_code, bundle_seq, qty, number_from, number_to, needs_reprint
FROM bundles WHERE spread_id = @Spread1 AND article_size_id = @SizeM AND set_no = 2 AND deleted_at IS NULL
ORDER BY bundle_seq;

SELECT 'set 3 (tidak boleh bergeser)' AS tahap, cutting_code, bundle_seq, qty, number_from, number_to, needs_reprint
FROM bundles WHERE spread_id = @Spread1 AND article_size_id = @SizeM AND set_no = 3 AND deleted_at IS NULL
ORDER BY bundle_seq;
GO

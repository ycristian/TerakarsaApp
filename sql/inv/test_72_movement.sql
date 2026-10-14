/* =============================================================
   Uji skenario movement benang (Prompt 72).
   TIDAK MENINGGALKAN DATA: setiap blok dibungkus transaksi sendiri dan
   di-ROLLBACK di akhir.

   CATATAN PENTING (pelajaran dari seri TNI): inv.SIS_ThreadMovement_Manage
   memakai SET XACT_ABORT ON + CATCH yang me-ROLLBACK. Satu penolakan karena
   itu MEMBATALKAN SELURUH transaksi pemanggil -- jadi uji penolakan TIDAK
   BOLEH berada di transaksi yang sama dengan uji keberhasilan. Tiap blok di
   bawah punya setup + transaksinya sendiri.

   Jalankan dengan sqlcmd -I (QUOTED_IDENTIFIER ON, tabel inv punya filtered index).
   ============================================================= */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Tabel penampung hasil INSERT ... EXEC, dibuat DI LUAR transaksi.
IF OBJECT_ID('tempdb..#id') IS NOT NULL DROP TABLE #id;
IF OBJECT_ID('tempdb..#mv') IS NOT NULL DROP TABLE #mv;
CREATE TABLE #id (Value INT);
CREATE TABLE #mv (MovementId INT, ThreadSplitConeId INT, ConeCode VARCHAR(20), WeightGram INT);
GO

/* =============================================================
   BLOK 1 -- jalur sukses lengkap:
   RECEIVE 10 (ZZ1) -> ISSUE 6 (tanpa project, PAKAI keterangan)
   -> RETURN 420 g -> ISSUE_SPLIT -> RETURN_SPLIT 300 g -> MOVE 2 (ZZ1->ZZ2)
   Saldo akhir yang diharapkan: ZZ1 = 2, ZZ2 = 2, split 1 kones 300 g.
   ============================================================= */
PRINT '===== BLOK 1: jalur sukses =====';
BEGIN TRANSACTION;

DECLARE @u INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username = 'admin' ORDER BY Id);
DECLARE @t INT = (SELECT thread_type_id FROM inv.thread_types WHERE code = 'POLY' AND deleted_at IS NULL);
DECLARE @r INT = (SELECT TOP 1 resource_id FROM dbo.resources WHERE deleted_at IS NULL AND is_active = 1 ORDER BY resource_id);
DECLARE @b INT, @l1 INT, @l2 INT, @i INT, @cone INT;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action = 'CREATE', @Name = 'UJI MERK 72', @UserId = @u;
SELECT @b = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action = 'CREATE', @Code = 'ZZ1', @Name = 'Uji 72 A', @UserId = @u;
SELECT @l1 = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action = 'CREATE', @Code = 'ZZ2', @Name = 'Uji 72 B', @UserId = @u;
SELECT @l2 = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action = 'CREATE', @TypeId = @t, @BrandId = @b,
     @ColorName = 'Uji Merah', @ColorCode = 'U72', @ConeSize = 'BESAR', @UserId = @u;
SELECT @i = Value FROM #id;

SELECT 'SKU dibuat' AS Langkah, sku_code AS SkuCode,
       CASE WHEN sku_code = 'BN-POL-UJI-U72-B' THEN 'OK' ELSE 'PERIKSA' END AS Hasil
FROM inv.thread_items WHERE thread_item_id = @i;

EXEC inv.SIS_ThreadMovement_Manage @Action = 'RECEIVE', @ItemId = @i, @ToLocationId = @l1,
     @Qty = 10, @Note = 'uji terima', @UserId = @u;

-- Tanpa project TAPI dengan keterangan -> harus lolos.
EXEC inv.SIS_ThreadMovement_Manage @Action = 'ISSUE', @ItemId = @i, @FromLocationId = @l1,
     @Qty = 6, @ResourceId = @r, @ProjectId = NULL, @Note = 'uji ambil tanpa project', @UserId = @u;

DELETE #mv;
INSERT INTO #mv EXEC inv.SIS_ThreadMovement_Manage @Action = 'RETURN', @ItemId = @i,
     @WeightGram = 420, @ToLocationId = @l1, @ResourceId = @r, @UserId = @u;
SELECT @cone = ThreadSplitConeId FROM #mv;

SELECT 'RETURN membuat split' AS Langkah, ConeCode, WeightGram,
       CASE WHEN ConeCode LIKE 'SP-[0-9][0-9][0-9][0-9][0-9][0-9]' AND WeightGram = 420
            THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM #mv;

EXEC inv.SIS_ThreadMovement_Manage @Action = 'ISSUE_SPLIT', @SplitConeId = @cone,
     @ResourceId = @r, @Note = 'uji ambil split', @UserId = @u;

SELECT 'Setelah ISSUE_SPLIT' AS Langkah, [status] AS Status, thread_location_id AS LokasiHarusNull,
       CASE WHEN [status] = 'ISSUED' AND thread_location_id IS NULL THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_split_cones WHERE thread_split_cone_id = @cone;

EXEC inv.SIS_ThreadMovement_Manage @Action = 'RETURN_SPLIT', @SplitConeId = @cone,
     @WeightGram = 300, @ToLocationId = @l2, @UserId = @u;

SELECT 'Setelah RETURN_SPLIT' AS Langkah, [status] AS Status, weight_gram AS Berat,
       CASE WHEN [status] = 'IN_STOCK' AND weight_gram = 300 AND thread_location_id = @l2
            THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_split_cones WHERE thread_split_cone_id = @cone;

EXEC inv.SIS_ThreadMovement_Manage @Action = 'MOVE', @ItemId = @i,
     @FromLocationId = @l1, @ToLocationId = @l2, @Qty = 2, @UserId = @u;

PRINT '--- saldo akhir per rak (harus ZZ1=2, ZZ2=2) ---';
SELECT l.code AS Rak, st.qty_whole AS QtyWhole,
       CASE WHEN l.code = 'ZZ1' AND st.qty_whole = 2 THEN 'OK'
            WHEN l.code = 'ZZ2' AND st.qty_whole = 2 THEN 'OK'
            ELSE 'GAGAL' END AS Hasil
FROM inv.thread_stocks st
INNER JOIN inv.thread_locations l ON l.thread_location_id = st.thread_location_id
WHERE st.thread_item_id = @i AND st.deleted_at IS NULL
ORDER BY l.code;

PRINT '--- ringkasan view v_thread_item_stock (whole 4, split 1 kones 300 g) ---';
SELECT qty_whole_total AS Whole, split_count_in_stock AS SplitKones,
       split_gram_in_stock AS SplitGram, location_codes AS Rak,
       CASE WHEN qty_whole_total = 4 AND split_count_in_stock = 1 AND split_gram_in_stock = 300
            THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.v_thread_item_stock WHERE thread_item_id = @i;

PRINT '--- riwayat movement (harus 6 baris) ---';
EXEC inv.SIS_ThreadMovement_Recent @ItemId = @i, @Top = 20;

SELECT 'Jumlah movement' AS Langkah, COUNT(*) AS Jumlah,
       CASE WHEN COUNT(*) = 6 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_movements WHERE thread_item_id = @i AND deleted_at IS NULL;

ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 2 -- ISSUE tanpa project DAN tanpa keterangan harus DITOLAK
   dengan pesan 'Isi project atau keterangan.'
   ============================================================= */
PRINT '===== BLOK 2: ISSUE tanpa project & tanpa keterangan =====';
BEGIN TRANSACTION;

DECLARE @u2 INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username = 'admin' ORDER BY Id);
DECLARE @t2 INT = (SELECT thread_type_id FROM inv.thread_types WHERE code = 'POLY' AND deleted_at IS NULL);
DECLARE @r2 INT = (SELECT TOP 1 resource_id FROM dbo.resources WHERE deleted_at IS NULL AND is_active = 1 ORDER BY resource_id);
DECLARE @b2 INT, @la INT, @i2 INT;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action = 'CREATE', @Name = 'UJI MERK 72B', @UserId = @u2;
SELECT @b2 = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action = 'CREATE', @Code = 'ZZ3', @UserId = @u2;
SELECT @la = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action = 'CREATE', @TypeId = @t2, @BrandId = @b2,
     @ColorName = 'Uji Biru', @ColorCode = 'U72B', @ConeSize = 'KECIL', @UserId = @u2;
SELECT @i2 = Value FROM #id;

EXEC inv.SIS_ThreadMovement_Manage @Action = 'RECEIVE', @ItemId = @i2, @ToLocationId = @la,
     @Qty = 5, @UserId = @u2;

BEGIN TRY
    EXEC inv.SIS_ThreadMovement_Manage @Action = 'ISSUE', @ItemId = @i2, @FromLocationId = @la,
         @Qty = 1, @ResourceId = @r2, @ProjectId = NULL, @Note = NULL, @UserId = @u2;

    SELECT 'ISSUE tanpa project & keterangan' AS Uji, 'GAGAL (seharusnya ditolak)' AS Hasil;
END TRY
BEGIN CATCH
    SELECT 'ISSUE tanpa project & keterangan' AS Uji,
           CASE WHEN ERROR_MESSAGE() LIKE '%Isi project atau keterangan%' THEN 'OK' ELSE 'PERIKSA' END AS Hasil,
           ERROR_MESSAGE() AS Pesan;
END CATCH

IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 3 -- ISSUE melebihi saldo harus DITOLAK
   dengan pesan 'Stok di rak ZZ4 hanya 3 kones.'
   ============================================================= */
PRINT '===== BLOK 3: ISSUE melebihi saldo =====';
BEGIN TRANSACTION;

DECLARE @u3 INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username = 'admin' ORDER BY Id);
DECLARE @t3 INT = (SELECT thread_type_id FROM inv.thread_types WHERE code = 'POLY' AND deleted_at IS NULL);
DECLARE @r3 INT = (SELECT TOP 1 resource_id FROM dbo.resources WHERE deleted_at IS NULL AND is_active = 1 ORDER BY resource_id);
DECLARE @b3 INT, @lb INT, @i3 INT;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action = 'CREATE', @Name = 'UJI MERK 72C', @UserId = @u3;
SELECT @b3 = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action = 'CREATE', @Code = 'ZZ4', @UserId = @u3;
SELECT @lb = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action = 'CREATE', @TypeId = @t3, @BrandId = @b3,
     @ColorName = 'Uji Hijau', @ColorCode = 'U72C', @ConeSize = 'BESAR', @UserId = @u3;
SELECT @i3 = Value FROM #id;

EXEC inv.SIS_ThreadMovement_Manage @Action = 'RECEIVE', @ItemId = @i3, @ToLocationId = @lb,
     @Qty = 3, @UserId = @u3;

BEGIN TRY
    EXEC inv.SIS_ThreadMovement_Manage @Action = 'ISSUE', @ItemId = @i3, @FromLocationId = @lb,
         @Qty = 4, @ResourceId = @r3, @Note = 'uji minus', @UserId = @u3;

    SELECT 'ISSUE melebihi saldo' AS Uji, 'GAGAL (seharusnya ditolak)' AS Hasil;
END TRY
BEGIN CATCH
    SELECT 'ISSUE melebihi saldo' AS Uji,
           CASE WHEN ERROR_MESSAGE() LIKE '%hanya 3 kones%' THEN 'OK' ELSE 'PERIKSA' END AS Hasil,
           ERROR_MESSAGE() AS Pesan;
END CATCH

IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 4 -- RETURN_SPLIT dengan berat LEBIH BESAR dari berat terakhir
   harus DITOLAK (benang tidak mungkin bertambah di line).
   ============================================================= */
PRINT '===== BLOK 4: RETURN_SPLIT berat naik =====';
BEGIN TRANSACTION;

DECLARE @u4 INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username = 'admin' ORDER BY Id);
DECLARE @t4 INT = (SELECT thread_type_id FROM inv.thread_types WHERE code = 'POLY' AND deleted_at IS NULL);
DECLARE @r4 INT = (SELECT TOP 1 resource_id FROM dbo.resources WHERE deleted_at IS NULL AND is_active = 1 ORDER BY resource_id);
DECLARE @b4 INT, @lc INT, @i4 INT, @cone4 INT;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action = 'CREATE', @Name = 'UJI MERK 72D', @UserId = @u4;
SELECT @b4 = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action = 'CREATE', @Code = 'ZZ5', @UserId = @u4;
SELECT @lc = Value FROM #id;

DELETE #id;
INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action = 'CREATE', @TypeId = @t4, @BrandId = @b4,
     @ColorName = 'Uji Kuning', @ColorCode = 'U72D', @ConeSize = 'BESAR', @UserId = @u4;
SELECT @i4 = Value FROM #id;

DELETE #mv;
INSERT INTO #mv EXEC inv.SIS_ThreadMovement_Manage @Action = 'RETURN', @ItemId = @i4,
     @WeightGram = 200, @ToLocationId = @lc, @ResourceId = @r4, @UserId = @u4;
SELECT @cone4 = ThreadSplitConeId FROM #mv;

EXEC inv.SIS_ThreadMovement_Manage @Action = 'ISSUE_SPLIT', @SplitConeId = @cone4,
     @ResourceId = @r4, @Note = 'uji', @UserId = @u4;

BEGIN TRY
    EXEC inv.SIS_ThreadMovement_Manage @Action = 'RETURN_SPLIT', @SplitConeId = @cone4,
         @WeightGram = 250, @ToLocationId = @lc, @UserId = @u4;

    SELECT 'RETURN_SPLIT berat naik' AS Uji, 'GAGAL (seharusnya ditolak)' AS Hasil;
END TRY
BEGIN CATCH
    SELECT 'RETURN_SPLIT berat naik' AS Uji,
           CASE WHEN ERROR_MESSAGE() LIKE '%lebih besar dari berat terakhir%' THEN 'OK' ELSE 'PERIKSA' END AS Hasil,
           ERROR_MESSAGE() AS Pesan;
END CATCH

IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 5 -- lookup & scan split
   ============================================================= */
PRINT '===== BLOK 5: lookup & SP baca =====';

EXEC inv.SIS_ThreadLookup_Resources;
EXEC inv.SIS_ThreadLookup_Projects;
EXEC inv.SIS_ThreadSplitCone_GetByCode @ConeCode = 'TS:SP-999999';   -- tidak ada: 0 baris, cek binding kolom
EXEC inv.SIS_ThreadStock_ByItem @ItemId = -1, @HanyaAda = 0;
GO

PRINT '===== Bersih: tidak ada data uji yang tertinggal =====';
SELECT 'Sisa data uji' AS Cek, COUNT(*) AS Jumlah,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_items WHERE color_code LIKE 'U72%';

IF OBJECT_ID('tempdb..#id') IS NOT NULL DROP TABLE #id;
IF OBJECT_ID('tempdb..#mv') IS NOT NULL DROP TABLE #mv;
GO

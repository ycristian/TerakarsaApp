/* =============================================================
   Uji skenario stock opname benang (Prompt 74).
   TIDAK MENINGGALKAN DATA: setiap blok punya transaksi sendiri + ROLLBACK.

   Seperti test_72: uji PENOLAKAN dipisah dari uji keberhasilan, karena
   SP memakai XACT_ABORT + CATCH yang me-ROLLBACK seluruh transaksi.

   Skenario dari prompt:
     BLOK 1  stok A1=20, B5=8 -> fisik A1=18, B5=10
             PREVIEW harus mengusulkan MOVE A1->B5 2, TANPA ADJUST; CLOSE sukses.
     BLOK 2  stok A1=20, B5=8 -> fisik A1=18, B5=8
             PREVIEW mengusulkan ADJUST -2 (alasan wajib); CLOSE tanpa alasan GAGAL.
     BLOK 3  CLOSE dengan alasan -> saldo A1 jadi 18, movement ADJUST tercatat
             dengan opname_line_id.
     BLOK 4  ADJUST di luar opname harus DITOLAK.
     BLOK 5  ADD_LINE (jalur stok awal) + CLOSE dengan alasan STOK_AWAL.
   ============================================================= */

SET NOCOUNT ON;
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('tempdb..#id') IS NOT NULL DROP TABLE #id;
IF OBJECT_ID('tempdb..#mv') IS NOT NULL DROP TABLE #mv;
IF OBJECT_ID('tempdb..#prev') IS NOT NULL DROP TABLE #prev;
CREATE TABLE #id (Value INT);
CREATE TABLE #mv (MovementId INT, ThreadSplitConeId INT, ConeCode VARCHAR(20), WeightGram INT);
GO

/* =============================================================
   BLOK 1 -- selisih berpasangan: usulan MOVE, tanpa ADJUST
   ============================================================= */
PRINT '===== BLOK 1: A1 18 / B5 10 -> usulan MOVE 2 =====';
BEGIN TRANSACTION;

DECLARE @u INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username = 'admin' ORDER BY Id);
DECLARE @t INT = (SELECT thread_type_id FROM inv.thread_types WHERE code = 'POLY' AND deleted_at IS NULL);
DECLARE @b INT, @a1 INT, @b5 INT, @i INT, @sesi INT, @lineA1 INT, @lineB5 INT;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action='CREATE', @Name='UJI MERK 74', @UserId=@u;
SELECT @b = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action='CREATE', @Code='ZA1', @UserId=@u;
SELECT @a1 = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action='CREATE', @Code='ZB5', @UserId=@u;
SELECT @b5 = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action='CREATE', @TypeId=@t, @BrandId=@b,
     @ColorName='Uji Opname', @ColorCode='U74', @ConeSize='BESAR', @UserId=@u;
SELECT @i = Value FROM #id;

EXEC inv.SIS_ThreadMovement_Manage @Action='RECEIVE', @ItemId=@i, @ToLocationId=@a1, @Qty=20, @UserId=@u;
EXEC inv.SIS_ThreadMovement_Manage @Action='RECEIVE', @ItemId=@i, @ToLocationId=@b5, @Qty=8, @UserId=@u;

DECLARE @rakJson NVARCHAR(100) = '[' + CAST(@a1 AS VARCHAR(10)) + ',' + CAST(@b5 AS VARCHAR(10)) + ']';
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='OPEN', @LocationIdsJson=@rakJson, @UserId=@u;
SELECT @sesi = Value FROM #id;

SELECT 'Sesi dibuka' AS Langkah, session_no AS SessionNo,
       CASE WHEN session_no LIKE 'SO[0-9][0-9]-[0-9][0-9][0-9][0-9]' THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_opname_sessions WHERE thread_opname_session_id = @sesi;

SELECT @lineA1 = thread_opname_line_id FROM inv.thread_opname_lines
WHERE thread_opname_session_id = @sesi AND thread_location_id = @a1 AND thread_item_id = @i;
SELECT @lineB5 = thread_opname_line_id FROM inv.thread_opname_lines
WHERE thread_opname_session_id = @sesi AND thread_location_id = @b5 AND thread_item_id = @i;

SELECT 'Baris dibuat' AS Langkah, COUNT(*) AS Jumlah,
       CASE WHEN COUNT(*) = 2 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_opname_lines WHERE thread_opname_session_id = @sesi AND deleted_at IS NULL;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='COUNT', @LineId=@lineA1, @CountedQty=18, @UserId=@u;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='COUNT', @LineId=@lineB5, @CountedQty=10, @UserId=@u;

PRINT '--- preview: harus 1 usulan MOVE 2 dari ZA1 ke ZB5, tanpa ADJUST ---';
EXEC inv.SIS_ThreadOpname_Manage @Action='PREVIEW_CLOSE', @SessionId=@sesi;

-- CLOSE dengan resolusi MOVE sesuai usulan.
DECLARE @resMove NVARCHAR(MAX) =
    '[{"line_id":' + CAST(@lineA1 AS VARCHAR(10)) + ',"action":"MOVE","qty":2,"from_location_id":'
    + CAST(@a1 AS VARCHAR(10)) + ',"to_location_id":' + CAST(@b5 AS VARCHAR(10)) + '}]';

EXEC inv.SIS_ThreadOpname_Manage @Action='CLOSE', @SessionId=@sesi,
     @ResolutionsJson=@resMove, @UserId=@u;

PRINT '--- saldo setelah CLOSE (ZA1 harus 18, ZB5 harus 10) ---';
SELECT l.code AS Rak, st.qty_whole AS QtyWhole,
       CASE WHEN l.code='ZA1' AND st.qty_whole=18 THEN 'OK'
            WHEN l.code='ZB5' AND st.qty_whole=10 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_stocks st
INNER JOIN inv.thread_locations l ON l.thread_location_id = st.thread_location_id
WHERE st.thread_item_id = @i AND st.deleted_at IS NULL ORDER BY l.code;

SELECT 'Sesi tertutup' AS Langkah, [status] AS Status,
       CASE WHEN [status]='CLOSED' THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_opname_sessions WHERE thread_opname_session_id = @sesi;

SELECT 'Movement MOVE menunjuk baris opname' AS Langkah, COUNT(*) AS Jumlah,
       CASE WHEN COUNT(*) = 1 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_movements
WHERE thread_item_id = @i AND movement_type='MOVE' AND opname_line_id = @lineA1 AND deleted_at IS NULL;

SELECT 'Tidak ada ADJUST' AS Langkah, COUNT(*) AS Jumlah,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_movements WHERE thread_item_id = @i AND movement_type='ADJUST' AND deleted_at IS NULL;

ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 2 -- selisih tidak berpasangan: CLOSE tanpa alasan harus GAGAL
   ============================================================= */
PRINT '===== BLOK 2: A1 18 / B5 8 -> CLOSE tanpa alasan harus ditolak =====';
BEGIN TRANSACTION;

DECLARE @u2 INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username='admin' ORDER BY Id);
DECLARE @t2 INT = (SELECT thread_type_id FROM inv.thread_types WHERE code='POLY' AND deleted_at IS NULL);
DECLARE @b2 INT, @a1b INT, @b5b INT, @i2 INT, @sesi2 INT, @lineA1b INT, @lineB5b INT;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action='CREATE', @Name='UJI MERK 74B', @UserId=@u2;
SELECT @b2 = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action='CREATE', @Code='ZA2', @UserId=@u2;
SELECT @a1b = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action='CREATE', @Code='ZB6', @UserId=@u2;
SELECT @b5b = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action='CREATE', @TypeId=@t2, @BrandId=@b2,
     @ColorName='Uji Opname B', @ColorCode='U74B', @ConeSize='BESAR', @UserId=@u2;
SELECT @i2 = Value FROM #id;

EXEC inv.SIS_ThreadMovement_Manage @Action='RECEIVE', @ItemId=@i2, @ToLocationId=@a1b, @Qty=20, @UserId=@u2;
EXEC inv.SIS_ThreadMovement_Manage @Action='RECEIVE', @ItemId=@i2, @ToLocationId=@b5b, @Qty=8, @UserId=@u2;

DECLARE @rakJson2 NVARCHAR(100) = '[' + CAST(@a1b AS VARCHAR(10)) + ',' + CAST(@b5b AS VARCHAR(10)) + ']';
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='OPEN', @LocationIdsJson=@rakJson2, @UserId=@u2;
SELECT @sesi2 = Value FROM #id;

SELECT @lineA1b = thread_opname_line_id FROM inv.thread_opname_lines
WHERE thread_opname_session_id = @sesi2 AND thread_location_id = @a1b;
SELECT @lineB5b = thread_opname_line_id FROM inv.thread_opname_lines
WHERE thread_opname_session_id = @sesi2 AND thread_location_id = @b5b;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='COUNT', @LineId=@lineA1b, @CountedQty=18, @UserId=@u2;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='COUNT', @LineId=@lineB5b, @CountedQty=8, @UserId=@u2;

PRINT '--- preview: harus ADJUST -2 di ZA2 dengan ReasonRequired = 1 ---';
EXEC inv.SIS_ThreadOpname_Manage @Action='PREVIEW_CLOSE', @SessionId=@sesi2;

DECLARE @resTanpaAlasan NVARCHAR(MAX) =
    '[{"line_id":' + CAST(@lineA1b AS VARCHAR(10)) + ',"action":"ADJUST","qty":-2}]';

BEGIN TRY
    EXEC inv.SIS_ThreadOpname_Manage @Action='CLOSE', @SessionId=@sesi2,
         @ResolutionsJson=@resTanpaAlasan, @UserId=@u2;
    SELECT 'CLOSE tanpa alasan' AS Uji, 'GAGAL (seharusnya ditolak)' AS Hasil;
END TRY
BEGIN CATCH
    SELECT 'CLOSE tanpa alasan' AS Uji,
           CASE WHEN ERROR_MESSAGE() LIKE '%wajib punya alasan%' THEN 'OK' ELSE 'PERIKSA' END AS Hasil,
           ERROR_MESSAGE() AS Pesan;
END CATCH

IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 3 -- CLOSE dengan alasan: saldo ikut berubah, movement ADJUST tercatat
   ============================================================= */
PRINT '===== BLOK 3: CLOSE dengan alasan HILANG =====';
BEGIN TRANSACTION;

DECLARE @u3 INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username='admin' ORDER BY Id);
DECLARE @t3 INT = (SELECT thread_type_id FROM inv.thread_types WHERE code='POLY' AND deleted_at IS NULL);
DECLARE @b3 INT, @a1c INT, @i3 INT, @sesi3 INT, @lineA1c INT;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action='CREATE', @Name='UJI MERK 74C', @UserId=@u3;
SELECT @b3 = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action='CREATE', @Code='ZA3', @UserId=@u3;
SELECT @a1c = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action='CREATE', @TypeId=@t3, @BrandId=@b3,
     @ColorName='Uji Opname C', @ColorCode='U74C', @ConeSize='BESAR', @UserId=@u3;
SELECT @i3 = Value FROM #id;

EXEC inv.SIS_ThreadMovement_Manage @Action='RECEIVE', @ItemId=@i3, @ToLocationId=@a1c, @Qty=20, @UserId=@u3;

DECLARE @rakJson3 NVARCHAR(100) = '[' + CAST(@a1c AS VARCHAR(10)) + ']';
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='OPEN', @LocationIdsJson=@rakJson3, @UserId=@u3;
SELECT @sesi3 = Value FROM #id;

SELECT @lineA1c = thread_opname_line_id FROM inv.thread_opname_lines
WHERE thread_opname_session_id = @sesi3 AND thread_location_id = @a1c;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='COUNT', @LineId=@lineA1c, @CountedQty=18, @UserId=@u3;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='LOCATION_DONE', @SessionId=@sesi3, @LocationId=@a1c, @UserId=@u3;

DECLARE @resAlasan NVARCHAR(MAX) =
    '[{"line_id":' + CAST(@lineA1c AS VARCHAR(10)) + ',"action":"ADJUST","qty":-2,"reason_code":"HILANG"}]';

EXEC inv.SIS_ThreadOpname_Manage @Action='CLOSE', @SessionId=@sesi3,
     @ResolutionsJson=@resAlasan, @UserId=@u3;

SELECT 'Saldo setelah ADJUST' AS Langkah, st.qty_whole AS QtyWhole,
       CASE WHEN st.qty_whole = 18 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_stocks st WHERE st.thread_item_id = @i3 AND st.thread_location_id = @a1c;

SELECT 'Movement ADJUST' AS Langkah, m.qty_whole AS Qty, m.reason_code AS Alasan,
       m.opname_line_id AS OpnameLineId,
       CASE WHEN m.qty_whole = -2 AND m.reason_code = 'HILANG' AND m.opname_line_id = @lineA1c
            THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_movements m
WHERE m.thread_item_id = @i3 AND m.movement_type = 'ADJUST' AND m.deleted_at IS NULL;

PRINT '--- hasil sesi (SIS_ThreadOpname_GetById bagian HASIL) ---';
EXEC inv.SIS_ThreadOpname_GetById @SessionId=@sesi3, @Bagian='HASIL';

ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 4 -- ADJUST di luar opname harus DITOLAK
   ============================================================= */
PRINT '===== BLOK 4: ADJUST tanpa baris opname =====';
BEGIN TRANSACTION;

DECLARE @u4 INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username='admin' ORDER BY Id);
DECLARE @t4 INT = (SELECT thread_type_id FROM inv.thread_types WHERE code='POLY' AND deleted_at IS NULL);
DECLARE @b4 INT, @a1d INT, @i4 INT;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action='CREATE', @Name='UJI MERK 74D', @UserId=@u4;
SELECT @b4 = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action='CREATE', @Code='ZA4', @UserId=@u4;
SELECT @a1d = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action='CREATE', @TypeId=@t4, @BrandId=@b4,
     @ColorName='Uji Opname D', @ColorCode='U74D', @ConeSize='BESAR', @UserId=@u4;
SELECT @i4 = Value FROM #id;

EXEC inv.SIS_ThreadMovement_Manage @Action='RECEIVE', @ItemId=@i4, @ToLocationId=@a1d, @Qty=5, @UserId=@u4;

BEGIN TRY
    EXEC inv.SIS_ThreadMovement_Manage @Action='ADJUST', @ItemId=@i4, @LocationId=@a1d,
         @Qty=-1, @ReasonCode='HILANG', @UserId=@u4;
    SELECT 'ADJUST tanpa opname' AS Uji, 'GAGAL (seharusnya ditolak)' AS Hasil;
END TRY
BEGIN CATCH
    SELECT 'ADJUST tanpa opname' AS Uji,
           CASE WHEN ERROR_MESSAGE() LIKE '%hanya boleh dibuat dari stock opname%' THEN 'OK' ELSE 'PERIKSA' END AS Hasil,
           ERROR_MESSAGE() AS Pesan;
END CATCH

IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
GO

/* =============================================================
   BLOK 5 -- ADD_LINE: jalur STOK AWAL (sistem 0, fisik 25)
   ============================================================= */
PRINT '===== BLOK 5: stok awal lewat ADD_LINE + alasan STOK_AWAL =====';
BEGIN TRANSACTION;

DECLARE @u5 INT = (SELECT TOP 1 Id FROM dbo.Users WHERE Username='admin' ORDER BY Id);
DECLARE @t5 INT = (SELECT thread_type_id FROM inv.thread_types WHERE code='POLY' AND deleted_at IS NULL);
DECLARE @b5c INT, @a1e INT, @i5 INT, @sesi5 INT, @line5 INT;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadBrand_Manage @Action='CREATE', @Name='UJI MERK 74E', @UserId=@u5;
SELECT @b5c = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadLocation_Manage @Action='CREATE', @Code='ZA5', @UserId=@u5;
SELECT @a1e = Value FROM #id;
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadItem_Manage @Action='CREATE', @TypeId=@t5, @BrandId=@b5c,
     @ColorName='Uji Stok Awal', @ColorCode='U74E', @ConeSize='KECIL', @UserId=@u5;
SELECT @i5 = Value FROM #id;

DECLARE @rakJson5 NVARCHAR(100) = '[' + CAST(@a1e AS VARCHAR(10)) + ']';
DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='OPEN', @LocationIdsJson=@rakJson5, @UserId=@u5;
SELECT @sesi5 = Value FROM #id;

SELECT 'Sesi kosong (belum ada stok)' AS Langkah, COUNT(*) AS Baris,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_opname_lines WHERE thread_opname_session_id = @sesi5 AND deleted_at IS NULL;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='ADD_LINE',
     @SessionId=@sesi5, @LocationId=@a1e, @ItemId=@i5, @UserId=@u5;
SELECT @line5 = Value FROM #id;

DELETE #id; INSERT INTO #id EXEC inv.SIS_ThreadOpname_Manage @Action='COUNT', @LineId=@line5, @CountedQty=25, @UserId=@u5;

DECLARE @resAwal NVARCHAR(MAX) =
    '[{"line_id":' + CAST(@line5 AS VARCHAR(10)) + ',"action":"ADJUST","qty":25,"reason_code":"STOK_AWAL"}]';

EXEC inv.SIS_ThreadOpname_Manage @Action='CLOSE', @SessionId=@sesi5,
     @ResolutionsJson=@resAwal, @UserId=@u5;

SELECT 'Stok awal masuk' AS Langkah, st.qty_whole AS QtyWhole,
       CASE WHEN st.qty_whole = 25 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_stocks st WHERE st.thread_item_id = @i5 AND st.thread_location_id = @a1e;

SELECT 'Alasan STOK_AWAL tercatat' AS Langkah, m.reason_code AS Alasan,
       CASE WHEN m.reason_code = 'STOK_AWAL' AND m.qty_whole = 25 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_movements m
WHERE m.thread_item_id = @i5 AND m.movement_type = 'ADJUST' AND m.deleted_at IS NULL;

ROLLBACK TRANSACTION;
GO

PRINT '===== Bersih: tidak ada data uji yang tertinggal =====';
SELECT 'Sisa SKU uji' AS Cek, COUNT(*) AS Jumlah,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_items WHERE color_code LIKE 'U74%'
UNION ALL
SELECT 'Sisa sesi opname', COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'GAGAL' END
FROM inv.thread_opname_sessions;

IF OBJECT_ID('tempdb..#id') IS NOT NULL DROP TABLE #id;
IF OBJECT_ID('tempdb..#mv') IS NOT NULL DROP TABLE #mv;
GO

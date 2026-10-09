/* =============================================================
   Verifikasi alter_76 -- header setoran stok (2026-10-07).
   Pola sama dengan verify_64 (SIS_Stok_Manage memakai XACT_ABORT ON):
     FASE A -- penolakan tanpa transaksi
     FASE B -- uji berhasil, transaksi di-ROLLBACK
     FASE C -- penolakan yang butuh data, transaksi sendiri di-ROLLBACK
   Tidak ada data yang tertinggal. Aman dijalankan berulang.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(40), hasil VARCHAR(40), pesan VARCHAR(300));

DECLARE @K102 INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='LD_102_P' AND deleted_at IS NULL);
DECLARE @K104 INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='LD_104_P' AND deleted_at IS NULL);
DECLARE @C32  INT = (SELECT pola_celana_id FROM tni.pola_celana WHERE kode='32_P'     AND deleted_at IS NULL);
DECLARE @Tgl DATE = '2001-01-01';   -- tanggal uji, tidak bentrok dengan data asli

/* ============================ FASE A ============================ */
DECLARE @Isi NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":1}]');
BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='SETORAN_EDIT', @OrderId=@O, @SetoranId=-1, @Tanggal=@Tgl, @Items=@Isi, @UserId=@U;
    INSERT INTO @h VALUES (1, 'EDIT setoran tidak ada', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (1, 'EDIT setoran tidak ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='SETORAN_HAPUS', @OrderId=@O, @SetoranId=-1, @UserId=@U;
    INSERT INTO @h VALUES (2, 'HAPUS setoran tidak ada', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (2, 'HAPUS setoran tidak ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

/* ============================ FASE B ============================ */
BEGIN TRANSACTION;

DECLARE @Saldo102 INT = (SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102);

DECLARE @I1 NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":10},',
                                     '{"jenisItem":"CELANA","polaId":', @C32,  ',"qty":5}]');
EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Tanggal=@Tgl, @Supplier='UJI76', @Items=@I1, @UserId=@U;

DECLARE @S1 INT = (SELECT setoran_id FROM tni.stok_setoran
                   WHERE order_id=@O AND tanggal=@Tgl AND supplier='UJI76' AND deleted_at IS NULL);
INSERT INTO @h VALUES (3, 'SETORAN baru -> 1 header, 2 baris', '1/2',
    CONCAT(CASE WHEN @S1 IS NULL THEN 0 ELSE 1 END, '/',
           (SELECT COUNT(*) FROM tni.stok_mutasi WHERE setoran_id=@S1 AND deleted_at IS NULL)), '');

-- tanggal & supplier sama -> DIGABUNG (pola sama ditambah, pola baru baris baru)
DECLARE @I2 NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":3},',
                                     '{"jenisItem":"KEMEJA","polaId":', @K104, ',"qty":4}]');
EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Tanggal=@Tgl, @Supplier='  UJI76 ', @Items=@I2, @UserId=@U;

INSERT INTO @h VALUES (4, 'kunci sama -> tetap 1 header', '1',
    CAST((SELECT COUNT(*) FROM tni.stok_setoran WHERE order_id=@O AND tanggal=@Tgl AND supplier='UJI76' AND deleted_at IS NULL) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (5, 'digabung: 3 baris, LD_102_P = 13', '3/13',
    CONCAT((SELECT COUNT(*) FROM tni.stok_mutasi WHERE setoran_id=@S1 AND deleted_at IS NULL), '/',
           (SELECT qty FROM tni.stok_mutasi WHERE setoran_id=@S1 AND pola_kemeja_id=@K102 AND deleted_at IS NULL)), '');

-- supplier lain -> header baru
EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Tanggal=@Tgl, @Supplier='UJI76B', @Items=@I1, @UserId=@U;
DECLARE @S2 INT = (SELECT setoran_id FROM tni.stok_setoran
                   WHERE order_id=@O AND tanggal=@Tgl AND supplier='UJI76B' AND deleted_at IS NULL);
INSERT INTO @h VALUES (6, 'supplier lain -> header lain', 'YA',
    CASE WHEN @S2 IS NOT NULL AND @S2 <> @S1 THEN 'YA' ELSE 'TIDAK' END, '');

-- EDIT: ganti supplier + isi (LD_102 jadi 20, LD_104 tetap, 32_P dibuang)
DECLARE @E1 NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":20},',
                                     '{"jenisItem":"KEMEJA","polaId":', @K104, ',"qty":4}]');
EXEC tni.SIS_Stok_Manage @Action='SETORAN_EDIT', @OrderId=@O, @SetoranId=@S1, @Tanggal=@Tgl,
     @Supplier='UJI76X', @Items=@E1, @UserId=@U;

INSERT INTO @h VALUES (7, 'EDIT: 2 baris hidup, LD_102_P = 20', '2/20',
    CONCAT((SELECT COUNT(*) FROM tni.stok_mutasi WHERE setoran_id=@S1 AND deleted_at IS NULL), '/',
           (SELECT qty FROM tni.stok_mutasi WHERE setoran_id=@S1 AND pola_kemeja_id=@K102 AND deleted_at IS NULL)), '');
INSERT INTO @h VALUES (8, 'EDIT: supplier header & baris ikut', 'UJI76X/0',
    CONCAT((SELECT supplier FROM tni.stok_setoran WHERE setoran_id=@S1), '/',
           (SELECT COUNT(*) FROM tni.stok_mutasi WHERE setoran_id=@S1 AND deleted_at IS NULL
                                                  AND ISNULL(supplier,'') <> 'UJI76X')), '');

-- riwayat manual: entri setoran S1 berisi 2 baris, kemeja urut LD_102 sebelum LD_104
CREATE TABLE #r (EntriTipe VARCHAR(10), EntriId INT, EntriUrut INT, TotalEntri INT,
    Tanggal DATE, Supplier VARCHAR(150), CreatedAt DATETIME2, CreatedByNama NVARCHAR(200),
    UpdatedAt DATETIME2, MutasiId INT, JenisMutasi VARCHAR(20), JenisItem VARCHAR(10),
    PolaId INT, Kode VARCHAR(30), Qty INT, Alasan VARCHAR(500));
INSERT INTO #r EXEC tni.SIS_Stok_RiwayatManual @OrderId=@O, @JenisMutasi='MASUK', @PageSize=500;
INSERT INTO @h VALUES (9, 'RiwayatManual: entri S1 = LD_102_P LD_104_P', 'LD_102_P LD_104_P',
    (SELECT STRING_AGG(Kode, ' ') WITHIN GROUP (ORDER BY rn)
       FROM (SELECT Kode, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) rn FROM #r
             WHERE EntriTipe='SETORAN' AND EntriId=@S1) x), '');
INSERT INTO @h VALUES (10, 'RiwayatManual MASUK: tanpa RUSAK/KOREKSI', '0',
    CAST((SELECT COUNT(*) FROM #r WHERE EntriTipe <> 'SETORAN') AS VARCHAR(10)), '');

-- HAPUS satu setoran: header + isi
EXEC tni.SIS_Stok_Manage @Action='SETORAN_HAPUS', @OrderId=@O, @SetoranId=@S2, @UserId=@U;
INSERT INTO @h VALUES (11, 'HAPUS: header & isi S2 terhapus', '1/0',
    CONCAT((SELECT COUNT(*) FROM tni.stok_setoran WHERE setoran_id=@S2 AND deleted_at IS NOT NULL), '/',
           (SELECT COUNT(*) FROM tni.stok_mutasi WHERE setoran_id=@S2 AND deleted_at IS NULL)), '');

INSERT INTO @h VALUES (12, 'saldo LD_102_P = awal + 20', CAST(@Saldo102 + 20 AS VARCHAR(10)),
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');

-- hapus baris terakhir lewat DELETE per mutasi -> header ikut terhapus
DECLARE @M1 INT, @M2 INT;
SELECT @M1 = MIN(mutasi_id), @M2 = MAX(mutasi_id) FROM tni.stok_mutasi WHERE setoran_id=@S1 AND deleted_at IS NULL;
EXEC tni.SIS_Stok_Manage @Action='DELETE', @OrderId=@O, @MutasiId=@M1, @UserId=@U;
EXEC tni.SIS_Stok_Manage @Action='DELETE', @OrderId=@O, @MutasiId=@M2, @UserId=@U;
INSERT INTO @h VALUES (13, 'DELETE baris terakhir -> header ikut terhapus', 'YA',
    CASE WHEN (SELECT deleted_at FROM tni.stok_setoran WHERE setoran_id=@S1) IS NOT NULL THEN 'YA' ELSE 'TIDAK' END, '');

ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #r;   -- sudah ikut hilang oleh ROLLBACK

/* ============================ FASE C ============================ */
BEGIN TRANSACTION;
EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Tanggal=@Tgl, @Supplier='UJI76', @Items=@I1, @UserId=@U;
EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Tanggal=@Tgl, @Supplier='UJI76B', @Items=@I1, @UserId=@U;
DECLARE @C1 INT = (SELECT setoran_id FROM tni.stok_setoran
                   WHERE order_id=@O AND tanggal=@Tgl AND supplier='UJI76' AND deleted_at IS NULL);
BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='SETORAN_EDIT', @OrderId=@O, @SetoranId=@C1, @Tanggal=@Tgl,
         @Supplier='UJI76B', @Items=@I1, @UserId=@U;
    INSERT INTO @h VALUES (14, 'EDIT ke tanggal+supplier setoran lain', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (14, 'EDIT ke tanggal+supplier setoran lain', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

/* ============================================================ */
SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 90) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

SELECT (SELECT COUNT(*) FROM tni.stok_setoran WHERE tanggal = '2001-01-01') AS sisa_header_uji;
GO

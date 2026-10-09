/* =============================================================
   Verifikasi tni.SIS_Box_Manage @Action = 'UNCLOSE' (batal tutup, 2026-10-07).
   SP memakai XACT_ABORT ON: penolakan di dalam transaksi luar membuat
   transaksi itu "doomed". Karena itu SETIAP penolakan yang butuh data uji
   dijalankan di transaksi sendiri (selalu di-ROLLBACK), sebagai langkah
   TERAKHIR transaksinya. Box uji dibuat lewat CREATE lalu "ditutup"
   langsung (CLOSE menolak box kosong). Tidak ada data yang tertinggal.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @S INT = (SELECT TOP 1 s.satuan_id FROM tni.satuan s
                  JOIN tni.area_rawatan a ON a.area_id = s.area_id AND a.deleted_at IS NULL
                  WHERE s.deleted_at IS NULL AND a.order_id = @O ORDER BY s.satuan_id);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(40), hasil VARCHAR(40), pesan VARCHAR(300));
DECLARE @r TABLE (BoxId INT, BoxCode VARCHAR(30), Urut INT, BoxNo INT);
DECLARE @B INT;

/* ---------- 1. box tidak ada (tanpa transaksi) ---------- */
BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='UNCLOSE', @BoxId=-1, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (1, 'UNCLOSE box tidak ada', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (1, 'UNCLOSE box tidak ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

/* ---------- 2. tanpa alasan ---------- */
BEGIN TRANSACTION;
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@S, @UserId=@U;
SET @B = (SELECT BoxId FROM @r);
UPDATE tni.box SET packed_at = SYSDATETIME(), packed_by = @U WHERE box_id = @B;
BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='UNCLOSE', @BoxId=@B, @Alasan='   ', @UserId=@U;
    INSERT INTO @h VALUES (2, 'UNCLOSE tanpa alasan', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (2, 'UNCLOSE tanpa alasan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

/* ---------- 3. box sudah terkirim ---------- */
BEGIN TRANSACTION;
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@S, @UserId=@U;
SET @B = (SELECT BoxId FROM @r);
UPDATE tni.box SET packed_at = SYSDATETIME(), packed_by = @U,
                   shipped_at = SYSDATETIME(), shipped_by = @U WHERE box_id = @B;
BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='UNCLOSE', @BoxId=@B, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (3, 'UNCLOSE box terkirim', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (3, 'UNCLOSE box terkirim', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

/* ---------- 4-6. berhasil, lalu ditolak karena sudah terbuka ---------- */
BEGIN TRANSACTION;
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@S, @UserId=@U;
SET @B = (SELECT BoxId FROM @r);
UPDATE tni.box SET packed_at = SYSDATETIME(), packed_by = @U WHERE box_id = @B;

EXEC tni.SIS_Box_Manage @Action='UNCLOSE', @BoxId=@B, @Alasan='Uji 78 salah tutup', @UserId=@U;

INSERT INTO @h VALUES (4, 'UNCLOSE: packed_at kosong -> TERBUKA', 'TERBUKA',
    (SELECT CASE WHEN packed_at IS NULL AND packed_by IS NULL THEN 'TERBUKA' ELSE 'TERTUTUP' END
       FROM tni.box WHERE box_id = @B), '');
INSERT INTO @h VALUES (5, 'alasan tercatat di keterangan', 'ADA',
    (SELECT CASE WHEN keterangan LIKE '%Batal tutup%Uji 78 salah tutup%' THEN 'ADA' ELSE 'TIDAK' END
       FROM tni.box WHERE box_id = @B), '');

BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='UNCLOSE', @BoxId=@B, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (6, 'UNCLOSE box yang sudah terbuka', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (6, 'UNCLOSE box yang sudah terbuka', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

/* ============================================================ */
SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 90) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;
GO

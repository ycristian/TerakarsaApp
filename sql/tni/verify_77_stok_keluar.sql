/* =============================================================
   Verifikasi alter_77 -- header pengeluaran stok (2026-10-07).
   Pola sama dengan verify_64/76 (SIS_Stok_Manage memakai XACT_ABORT ON):
     FASE A -- penolakan tanpa transaksi
     FASE B -- uji berhasil, transaksi di-ROLLBACK
   Tidak ada data yang tertinggal. Aman dijalankan berulang.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(40), hasil VARCHAR(40), pesan VARCHAR(300));

DECLARE @K102 INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='LD_102_P' AND deleted_at IS NULL);
DECLARE @K104 INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='LD_104_P' AND deleted_at IS NULL);
DECLARE @C32  INT = (SELECT pola_celana_id FROM tni.pola_celana WHERE kode='32_P'     AND deleted_at IS NULL);
DECLARE @Tgl DATE = '2001-01-02';

/* ============================ FASE A ============================ */
DECLARE @Isi NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":2}]');
DECLARE @Nol NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":0}]');

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='KOREKSI', @Items=@Isi, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (1, 'KOREKSI banyak baris tanpa arah', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (1, 'KOREKSI banyak baris tanpa arah', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='RUSAK', @Items=@Nol, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (2, 'RUSAK banyak baris qty 0', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (2, 'RUSAK banyak baris qty 0', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='RUSAK', @Items=@Isi, @Alasan='  ', @UserId=@U;
    INSERT INTO @h VALUES (3, 'RUSAK banyak baris tanpa alasan', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (3, 'RUSAK banyak baris tanpa alasan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR_EDIT', @OrderId=@O, @KeluarId=-1, @JenisMutasi='RUSAK',
         @Tanggal=@Tgl, @Items=@Isi, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (4, 'EDIT pengeluaran tidak ada', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (4, 'EDIT pengeluaran tidak ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR_HAPUS', @OrderId=@O, @KeluarId=-1, @UserId=@U;
    INSERT INTO @h VALUES (5, 'HAPUS pengeluaran tidak ada', 'DITOLAK', 'LOLOS', '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (5, 'HAPUS pengeluaran tidak ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

/* ============================ FASE B ============================ */
BEGIN TRANSACTION;

DECLARE @Saldo102 INT = (SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102);

-- RUSAK 2 pola sekaligus -> 1 header, qty disimpan negatif
DECLARE @R1 NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":3},',
                                     '{"jenisItem":"CELANA","polaId":', @C32,  ',"qty":2}]');
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @Tanggal=@Tgl, @JenisMutasi='RUSAK',
     @Items=@R1, @Alasan='Uji 77 noda', @UserId=@U;
DECLARE @KA INT = (SELECT MAX(keluar_id) FROM tni.stok_keluar WHERE order_id=@O AND tanggal=@Tgl AND deleted_at IS NULL);

INSERT INTO @h VALUES (6, 'RUSAK 2 pola -> 2 baris, total -5', '2/-5',
    CONCAT((SELECT COUNT(*) FROM tni.stok_mutasi WHERE keluar_id=@KA AND deleted_at IS NULL), '/',
           (SELECT SUM(qty) FROM tni.stok_mutasi WHERE keluar_id=@KA AND deleted_at IS NULL)), '');
INSERT INTO @h VALUES (7, 'header RUSAK arah -1, alasan ikut ke baris', '-1/0',
    CONCAT((SELECT arah FROM tni.stok_keluar WHERE keluar_id=@KA), '/',
           (SELECT COUNT(*) FROM tni.stok_mutasi WHERE keluar_id=@KA AND alasan <> 'Uji 77 noda')), '');

-- simpan kedua dengan master sama -> TIDAK digabung (beda dengan setoran)
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @Tanggal=@Tgl, @JenisMutasi='RUSAK',
     @Items=@R1, @Alasan='Uji 77 noda', @UserId=@U;
INSERT INTO @h VALUES (8, 'master sama -> header kedua (tidak digabung)', '2',
    CAST((SELECT COUNT(*) FROM tni.stok_keluar WHERE order_id=@O AND tanggal=@Tgl AND deleted_at IS NULL) AS VARCHAR(10)), '');
DECLARE @KB INT = (SELECT MAX(keluar_id) FROM tni.stok_keluar WHERE order_id=@O AND tanggal=@Tgl AND deleted_at IS NULL);

-- KOREKSI tambah banyak baris -> positif
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @Tanggal=@Tgl, @JenisMutasi='KOREKSI', @Arah=1,
     @Items=@Isi, @Alasan='Uji 77 hitung ulang', @UserId=@U;
DECLARE @KC INT = (SELECT MAX(keluar_id) FROM tni.stok_keluar WHERE order_id=@O AND tanggal=@Tgl AND deleted_at IS NULL);
INSERT INTO @h VALUES (9, 'KOREKSI tambah -> qty +2', '2',
    CAST((SELECT SUM(qty) FROM tni.stok_mutasi WHERE keluar_id=@KC AND deleted_at IS NULL) AS VARCHAR(10)), '');

-- pemanggil lama (satu item tanpa @Items) tetap jalan & dapat header
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @Tanggal=@Tgl, @JenisMutasi='KOREKSI',
     @JenisItem='KEMEJA', @PolaId=@K104, @Qty=-4, @Alasan='Uji 77 lama', @UserId=@U;
DECLARE @KD INT = (SELECT MAX(keluar_id) FROM tni.stok_keluar WHERE order_id=@O AND tanggal=@Tgl AND deleted_at IS NULL);
INSERT INTO @h VALUES (10, 'satu item lama: header arah -1, qty -4', '-1/-4',
    CONCAT((SELECT arah FROM tni.stok_keluar WHERE keluar_id=@KD), '/',
           (SELECT SUM(qty) FROM tni.stok_mutasi WHERE keluar_id=@KD AND deleted_at IS NULL)), '');

-- EDIT @KA: jadi KOREKSI kurangi; LD_102 jadi 7, 32_P dibuang, LD_104 baru 1
DECLARE @E1 NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":7},',
                                     '{"jenisItem":"KEMEJA","polaId":', @K104, ',"qty":1}]');
EXEC tni.SIS_Stok_Manage @Action='KELUAR_EDIT', @OrderId=@O, @KeluarId=@KA, @Tanggal=@Tgl,
     @JenisMutasi='KOREKSI', @Arah=-1, @Items=@E1, @Alasan='Uji 77 diedit', @UserId=@U;
INSERT INTO @h VALUES (11, 'EDIT: 2 baris hidup, total -8, semua KOREKSI', '2/-8/0',
    CONCAT((SELECT COUNT(*) FROM tni.stok_mutasi WHERE keluar_id=@KA AND deleted_at IS NULL), '/',
           (SELECT SUM(qty) FROM tni.stok_mutasi WHERE keluar_id=@KA AND deleted_at IS NULL), '/',
           (SELECT COUNT(*) FROM tni.stok_mutasi WHERE keluar_id=@KA AND deleted_at IS NULL
                                                  AND (jenis_mutasi <> 'KOREKSI' OR alasan <> 'Uji 77 diedit'))), '');

-- EDIT ke KOREKSI tambah: tanda berbalik
EXEC tni.SIS_Stok_Manage @Action='KELUAR_EDIT', @OrderId=@O, @KeluarId=@KA, @Tanggal=@Tgl,
     @JenisMutasi='KOREKSI', @Arah=1, @Items=@E1, @Alasan='Uji 77 diedit', @UserId=@U;
INSERT INTO @h VALUES (12, 'EDIT arah tambah -> total +8', '8',
    CAST((SELECT SUM(qty) FROM tni.stok_mutasi WHERE keluar_id=@KA AND deleted_at IS NULL) AS VARCHAR(10)), '');

-- riwayat manual: filter KOREKSI hanya entri KELUAR berjenis KOREKSI
CREATE TABLE #r (EntriTipe VARCHAR(10), EntriId INT, EntriUrut INT, TotalEntri INT,
    Tanggal DATE, Supplier VARCHAR(150), CreatedAt DATETIME2, CreatedByNama NVARCHAR(200),
    UpdatedAt DATETIME2, MutasiId INT, JenisMutasi VARCHAR(20), JenisItem VARCHAR(10),
    PolaId INT, Kode VARCHAR(30), Qty INT, Alasan VARCHAR(500));
INSERT INTO #r EXEC tni.SIS_Stok_RiwayatManual @OrderId=@O, @JenisMutasi='KOREKSI', @PageSize=500;
INSERT INTO @h VALUES (13, 'RiwayatManual KOREKSI: entri KA berisi 2 baris', '2',
    CAST((SELECT COUNT(*) FROM #r WHERE EntriTipe='KELUAR' AND EntriId=@KA) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (14, 'RiwayatManual KOREKSI: tanpa RUSAK/setoran', '0',
    CAST((SELECT COUNT(*) FROM #r WHERE EntriTipe <> 'KELUAR' OR JenisMutasi <> 'KOREKSI') AS VARCHAR(10)), '');

-- HAPUS satu pengeluaran
EXEC tni.SIS_Stok_Manage @Action='KELUAR_HAPUS', @OrderId=@O, @KeluarId=@KB, @UserId=@U;
INSERT INTO @h VALUES (15, 'HAPUS: header & isi KB terhapus', '1/0',
    CONCAT((SELECT COUNT(*) FROM tni.stok_keluar WHERE keluar_id=@KB AND deleted_at IS NOT NULL), '/',
           (SELECT COUNT(*) FROM tni.stok_mutasi WHERE keluar_id=@KB AND deleted_at IS NULL)), '');

-- DELETE baris terakhir -> header ikut terhapus
DECLARE @MD INT = (SELECT MIN(mutasi_id) FROM tni.stok_mutasi WHERE keluar_id=@KD AND deleted_at IS NULL);
EXEC tni.SIS_Stok_Manage @Action='DELETE', @OrderId=@O, @MutasiId=@MD, @UserId=@U;
INSERT INTO @h VALUES (16, 'DELETE baris terakhir -> header ikut terhapus', 'YA',
    CASE WHEN (SELECT deleted_at FROM tni.stok_keluar WHERE keluar_id=@KD) IS NOT NULL THEN 'YA' ELSE 'TIDAK' END, '');

-- saldo LD_102: KA +7, KC +2 (KB dihapus)
INSERT INTO @h VALUES (17, 'saldo LD_102_P = awal + 7 + 2', CAST(@Saldo102 + 9 AS VARCHAR(10)),
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');

ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #r;   -- sudah ikut hilang oleh ROLLBACK

/* ============================================================ */
SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 90) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

SELECT (SELECT COUNT(*) FROM tni.stok_keluar WHERE tanggal = '2001-01-02') AS sisa_header_uji;
GO

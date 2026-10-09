/* =============================================================
   Verifikasi Prompt 64 -- stok kemeja & celana.

   STRUKTUR PENTING: tni.SIS_Stok_Manage memakai SET XACT_ABORT ON (dibutuhkan
   transaksi SETORAN-nya). Akibatnya, kalau SP menolak sesuatu sementara kita
   sedang di dalam transaksi luar, transaksi itu jadi "doomed" -- semua tulisan
   setelahnya gagal. Karena itu uji dipisah:
     FASE A -- uji PENOLAKAN, tanpa transaksi (SP menolak sebelum menulis apa pun)
     FASE B -- uji yang BERHASIL, di dalam transaksi sendiri yang di-ROLLBACK
     FASE C -- uji penolakan yang butuh menyiapkan data, transaksi sendiri
   Tidak ada mutasi stok yang tertinggal. Aman dijalankan berulang.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(40), hasil VARCHAR(40), pesan VARCHAR(300));

DECLARE @K102 INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='LD_102_P' AND deleted_at IS NULL);
DECLARE @K104 INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='LD_104_P' AND deleted_at IS NULL);
DECLARE @C32  INT = (SELECT pola_celana_id FROM tni.pola_celana WHERE kode='32_P'     AND deleted_at IS NULL);

/* ============================================================
   FASE A -- uji PENOLAKAN (tanpa transaksi; SP tidak menulis apa pun)
   ============================================================ */

DECLARE @Nol NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":0}]');
BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Items=@Nol, @UserId=@U;
    INSERT INTO @h VALUES (1, 'SETORAN qty 0', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (1, 'SETORAN qty 0', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

DECLARE @Neg NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":-5}]');
BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Items=@Neg, @UserId=@U;
    INSERT INTO @h VALUES (2, 'SETORAN qty negatif', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (2, 'SETORAN qty negatif', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='RUSAK',
         @JenisItem='KEMEJA', @PolaId=@K102, @Qty=2, @Alasan=NULL, @UserId=@U;
    INSERT INTO @h VALUES (3, 'RUSAK 2 tanpa alasan', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (3, 'RUSAK 2 tanpa alasan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='KOREKSI',
         @JenisItem='KEMEJA', @PolaId=@K102, @Qty=0, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (4, 'KOREKSI qty 0', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (4, 'KOREKSI qty 0', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='KOREKSI',
         @JenisItem='KEMEJA', @PolaId=@K102, @Qty=5, @Alasan=NULL, @UserId=@U;
    INSERT INTO @h VALUES (5, 'KOREKSI tanpa alasan', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (5, 'KOREKSI tanpa alasan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- TERPAKAI & BONGKAR tidak boleh bisa diinput manual (hanya lahir dari
-- scan Set Jadi Prompt 66 dan persetujuan pembatalan Prompt 68).
BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='TERPAKAI',
         @JenisItem='KEMEJA', @PolaId=@K102, @Qty=1, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (6, 'KELUAR jenis TERPAKAI', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (6, 'KELUAR jenis TERPAKAI', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='BONGKAR',
         @JenisItem='KEMEJA', @PolaId=@K102, @Qty=1, @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (7, 'KELUAR jenis BONGKAR', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (7, 'KELUAR jenis BONGKAR', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH


/* ============================================================
   FASE B -- uji yang BERHASIL, dalam transaksi yang di-ROLLBACK
   ============================================================ */
BEGIN TRANSACTION;

DECLARE @Items NVARCHAR(MAX) = CONCAT(
    '[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":80},',
     '{"jenisItem":"KEMEJA","polaId":', @K104, ',"qty":60},',
     '{"jenisItem":"CELANA","polaId":', @C32,  ',"qty":70}]');

-- dihitung SELISIH, bukan total -- order aktif bisa sudah punya setoran asli
DECLARE @MasukSebelum INT = (SELECT COUNT(*) FROM tni.stok_mutasi
                              WHERE order_id=@O AND jenis_mutasi='MASUK' AND deleted_at IS NULL);

EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Items=@Items, @UserId=@U;

INSERT INTO @h VALUES (9, 'SETORAN 3 baris (kemeja+celana sekaligus)', '3',
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi WHERE order_id=@O AND jenis_mutasi='MASUK' AND deleted_at IS NULL)
         - @MasukSebelum AS VARCHAR(10)), '');
INSERT INTO @h VALUES (10, 'saldo LD_102_P', '80',
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (11, 'saldo 32_P', '70',
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='CELANA' AND pola_id=@C32) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (12, 'stok_bebas = saldo saat dijatah 0', '80',
    CAST((SELECT stok_bebas FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');

-- pola dobel dalam satu setoran DIGABUNG (bukan ditolak)
DECLARE @Dobel NVARCHAR(MAX) = CONCAT(
    '[{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":5},',
     '{"jenisItem":"KEMEJA","polaId":', @K102, ',"qty":7}]');
EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Items=@Dobel, @UserId=@U;
INSERT INTO @h VALUES (13, 'pola dobel digabung (+12) -> 92', '92',
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');

-- RUSAK dengan alasan: disimpan NEGATIF, saldo turun
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='RUSAK',
     @JenisItem='KEMEJA', @PolaId=@K102, @Qty=2, @Alasan='Kena noda oli', @UserId=@U;
INSERT INTO @h VALUES (14, 'RUSAK 2 -> saldo 92-2', '90',
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (15, 'RUSAK disimpan NEGATIF', '-2',
    CAST((SELECT TOP 1 qty FROM tni.stok_mutasi WHERE order_id=@O AND jenis_mutasi='RUSAK' ORDER BY mutasi_id DESC) AS VARCHAR(10)), '');

-- KOREKSI +3 lalu -1
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='KOREKSI',
     @JenisItem='KEMEJA', @PolaId=@K102, @Qty=3, @Alasan='Setoran 1/10 kurang dihitung', @UserId=@U;
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='KOREKSI',
     @JenisItem='KEMEJA', @PolaId=@K102, @Qty=-1, @Alasan='Dobel hitung', @UserId=@U;
INSERT INTO @h VALUES (16, 'KOREKSI +3 lalu -1 -> 92', '92',
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');

-- stok_bebas memperhitungkan kartu yang sudah DICETAK (dianggap sudah dijatah)
UPDATE TOP (10) p
SET printed_at = SYSDATETIME(), printed_by = @U, print_count = 1
FROM tni.personel p
WHERE p.order_id = @O AND p.pola_kemeja_id = @K102 AND p.deleted_at IS NULL AND p.printed_at IS NULL;

INSERT INTO @h VALUES (17, 'dijatah setelah 10 kartu dicetak', '10',
    CAST((SELECT dijatah FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (18, 'stok_bebas = saldo - dijatah (92-10)', '82',
    CAST((SELECT stok_bebas FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102) AS VARCHAR(10)), '');

-- kebutuhan_sisa = BELUM_CETAK + DICETAK, jadi tidak berubah karena pencetakan
DECLARE @Keb INT = (SELECT kebutuhan_sisa FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@K102);
DECLARE @KebHarusnya INT = (SELECT COUNT(*) FROM tni.v_personel WHERE order_id=@O AND pola_kemeja_id=@K102 AND status_progres IN ('BELUM_CETAK','DICETAK'));
INSERT INTO @h VALUES (19, 'kebutuhan_sisa = BELUM_CETAK + DICETAK', CAST(@KebHarusnya AS VARCHAR(10)), CAST(@Keb AS VARCHAR(10)), '');

-- saldo BOLEH minus (setoran mungkin belum dicatat) -- tidak pernah diblok
EXEC tni.SIS_Stok_Manage @Action='KELUAR', @OrderId=@O, @JenisMutasi='KOREKSI',
     @JenisItem='CELANA', @PolaId=@C32, @Qty=-200, @Alasan='Uji saldo minus', @UserId=@U;
INSERT INTO @h VALUES (20, 'saldo boleh minus (70-200)', '-130',
    CAST((SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='CELANA' AND pola_id=@C32) AS VARCHAR(10)), '');

-- semua pola muncul walau tanpa mutasi. Jumlah dihitung dari master pola,
-- bukan angka mati -- pola bisa bertambah lewat Master Pola.
INSERT INTO @h VALUES (21, 'v_stok_pola memuat semua pola',
    CAST((SELECT COUNT(*) FROM tni.pola_kemeja WHERE deleted_at IS NULL)
       + (SELECT COUNT(*) FROM tni.pola_celana WHERE deleted_at IS NULL) AS VARCHAR(10)),
    CAST((SELECT COUNT(*) FROM tni.v_stok_pola WHERE order_id=@O) AS VARCHAR(10)), '');

-- SIS_Stok_Saldo terurut grup gender (2026-10-07) lalu angka pola, bukan abjad
-- (LD_98 sebelum LD_100)
CREATE TABLE #s (JenisItem VARCHAR(10), PolaId INT, Kode VARCHAR(30), IsActive BIT,
    Masuk INT, Terpakai INT, KeluarLain INT, Bongkar INT, Saldo INT,
    Dijatah INT, StokBebas INT, KebutuhanSisa INT, GrupGender VARCHAR(10));
INSERT INTO #s EXEC tni.SIS_Stok_Saldo @OrderId=@O, @JenisItem='KEMEJA';
DECLARE @Urut VARCHAR(100) = (
    SELECT STRING_AGG(Kode, ' ') WITHIN GROUP (ORDER BY rn)
    FROM (SELECT TOP 3 Kode, ROW_NUMBER() OVER (ORDER BY (SELECT 0)) AS rn FROM #s) x);
-- 2026-10-06: pola nonaktif tanpa kebutuhan & tanpa saldo disembunyikan,
-- jadi harapan dihitung dari view dengan filter & urutan yang sama.
DECLARE @UrutHarus VARCHAR(100) = (
    SELECT STRING_AGG(kode, ' ') WITHIN GROUP (ORDER BY rn)
    FROM (SELECT TOP 3 v.kode,
                 ROW_NUMBER() OVER (ORDER BY v.urut_gender, v.urut_varian, v.urut_size, v.kode) AS rn
          FROM tni.v_stok_pola v
          WHERE v.order_id = @O AND v.jenis_item = 'KEMEJA'
            AND (v.is_active = 1 OR v.kebutuhan_sisa > 0 OR v.saldo <> 0)
          ORDER BY v.urut_gender, v.urut_varian, v.urut_size, v.kode) x);
INSERT INTO @h VALUES (22, 'SIS_Stok_Saldo urut gender, acuan, kode (3 pertama)', @UrutHarus, @Urut, '');

-- @HanyaAda = 1 hanya menampilkan yang saldonya <> 0
TRUNCATE TABLE #s;
INSERT INTO #s EXEC tni.SIS_Stok_Saldo @OrderId=@O, @JenisItem='KEMEJA', @HanyaAda=1;
INSERT INTO @h VALUES (23, 'HanyaAda=1 -> hanya pola bersaldo',
    CAST((SELECT COUNT(*) FROM tni.v_stok_pola
           WHERE order_id = @O AND jenis_item = 'KEMEJA' AND saldo <> 0) AS VARCHAR(10)),
    CAST((SELECT COUNT(*) FROM #s) AS VARCHAR(10)), (SELECT STRING_AGG(Kode, ', ') FROM #s));

ROLLBACK TRANSACTION;

/* ============================================================
   FASE C -- penolakan yang butuh menyiapkan data lebih dulu
   ============================================================ */
BEGIN TRANSACTION;
DECLARE @KN INT = (SELECT TOP 1 pola_kemeja_id FROM tni.pola_kemeja WHERE deleted_at IS NULL ORDER BY pola_kemeja_id DESC);
UPDATE tni.pola_kemeja SET is_active = 0 WHERE pola_kemeja_id = @KN;
DECLARE @NonAktif NVARCHAR(MAX) = CONCAT('[{"jenisItem":"KEMEJA","polaId":', @KN, ',"qty":5}]');
BEGIN TRY
    EXEC tni.SIS_Stok_Manage @Action='SETORAN', @OrderId=@O, @Items=@NonAktif, @UserId=@U;
    INSERT INTO @h VALUES (24, 'SETORAN ke pola NONAKTIF', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (24, 'SETORAN ke pola NONAKTIF', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

/* ============================================================ */

SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 75) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

-- bukti tidak ada sisa: mutasi 0, tidak ada kartu tercetak, semua pola aktif
SELECT (SELECT COUNT(*) FROM tni.stok_mutasi)                                      AS sisa_mutasi,
       (SELECT COUNT(*) FROM tni.personel WHERE printed_at IS NOT NULL)            AS personel_tercetak,
       (SELECT COUNT(*) FROM tni.pola_kemeja WHERE is_active = 0 AND deleted_at IS NULL) AS pola_nonaktif;
GO

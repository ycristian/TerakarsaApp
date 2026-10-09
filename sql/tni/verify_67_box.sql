/* =============================================================
   Verifikasi Prompt 67 -- box & scan "Masuk Box".

   Uji penolakan SIS_Box_Manage memakai RAISERROR + XACT_ABORT ON, jadi
   dipisah ke transaksinya sendiri (lihat catatan di verify_64_stok.sql).
   SIS_Scan_MasukBox mengembalikan hasil sebagai RESULT SET, jadi aman
   dipanggil berulang di dalam satu transaksi.
   Aman dijalankan berulang -- tidak ada data yang tertinggal.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(60), hasil VARCHAR(60), pesan VARCHAR(300));

-- bentuk result set SIS_Scan_MasukBox
DECLARE @r TABLE (Hasil VARCHAR(20), Pesan VARCHAR(300), PersonelId INT, KodeRef VARCHAR(30),
                  Pangkat VARCHAR(50), Nama VARCHAR(150), SatuanName VARCHAR(150),
                  PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                  BoxCode VARCHAR(30), Isi INT, Kapasitas INT,
                  SetAt DATETIME2, SetByNama VARCHAR(150), SaldoKemeja INT, SaldoCelana INT);

DECLARE @Buat TABLE (BoxId INT, BoxCode VARCHAR(30), Urut INT, BoxNo INT);   -- BoxNo: alter_72

BEGIN TRANSACTION;

/* ---------- Ditajenad (DTJ) di rawatan Bandung (BDG) ---------- */
DECLARE @SatDtj INT, @AreaBdg INT, @SatLain INT, @AreaCmh INT;

SELECT @SatDtj = s.satuan_id, @AreaBdg = a.area_id
FROM tni.satuan s JOIN tni.area_rawatan a ON a.area_id = s.area_id
WHERE a.order_id = @O AND s.satuan_code = 'DTJ' AND s.deleted_at IS NULL;

-- satuan lain DI RAWATAN YANG SAMA (untuk uji box gabungan)
SELECT TOP 1 @SatLain = s.satuan_id
FROM tni.satuan s
WHERE s.area_id = @AreaBdg AND s.satuan_id <> @SatDtj AND s.deleted_at IS NULL
ORDER BY s.satuan_id;

-- rawatan BERBEDA (Cimahi) untuk uji penolakan box gabungan
SELECT @AreaCmh = area_id FROM tni.area_rawatan
WHERE order_id = @O AND area_code = 'CMH' AND deleted_at IS NULL;

-- Box ASLI yang sudah ada di order aktif (uji 23-24 menghitung SELISIH, bukan total).
DECLARE @BoxAwal INT = (SELECT COUNT(*) FROM tni.box WHERE order_id = @O AND deleted_at IS NULL);
DECLARE @BoxAwalTerbuka INT = (SELECT COUNT(*) FROM tni.box
                               WHERE order_id = @O AND deleted_at IS NULL AND packed_at IS NULL);

/* ---------- 1. buka box DTJ dua kali -> BDG-DTJ-01, BDG-DTJ-02 ---------- */
DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@SatDtj, @UserId=@U;
DECLARE @Box1 INT = (SELECT TOP 1 BoxId FROM @Buat);
INSERT INTO @h VALUES (1, 'box DTJ pertama', 'BDG-DTJ-01', (SELECT TOP 1 BoxCode FROM @Buat), '');

DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@SatDtj, @UserId=@U;
DECLARE @Box2 INT = (SELECT TOP 1 BoxId FROM @Buat);
INSERT INTO @h VALUES (2, 'box DTJ kedua', 'BDG-DTJ-02', (SELECT TOP 1 BoxCode FROM @Buat), '');

/* ---------- 2. box GABUNGAN Bandung -> BDG-GAB-01 ---------- */
DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @AreaId=@AreaBdg, @UserId=@U;
DECLARE @BoxGab INT = (SELECT TOP 1 BoxId FROM @Buat);
INSERT INTO @h VALUES (3, 'box gabungan Bandung', 'BDG-GAB-01', (SELECT TOP 1 BoxCode FROM @Buat), '');

/* ---------- siapkan personel: 3 DTJ sudah set jadi, 1 DTJ belum ---------- */
DECLARE @P1 INT, @P2 INT, @P3 INT, @PBelumSet INT, @PLain INT, @PCmh INT;
DECLARE @T1 VARCHAR(16), @KodeRef1 VARCHAR(30), @SatuanNameLain VARCHAR(150);

SELECT TOP 1 @P1 = personel_id, @T1 = qr_token, @KodeRef1 = kode_ref
FROM tni.personel WHERE order_id=@O AND satuan_id=@SatDtj AND deleted_at IS NULL ORDER BY no_urut;

SELECT TOP 1 @P2 = personel_id FROM tni.personel
WHERE order_id=@O AND satuan_id=@SatDtj AND deleted_at IS NULL AND personel_id<>@P1 ORDER BY no_urut;

SELECT TOP 1 @P3 = personel_id FROM tni.personel
WHERE order_id=@O AND satuan_id=@SatDtj AND deleted_at IS NULL AND personel_id NOT IN (@P1,@P2) ORDER BY no_urut;

SELECT TOP 1 @PBelumSet = personel_id FROM tni.personel
WHERE order_id=@O AND satuan_id=@SatDtj AND deleted_at IS NULL AND personel_id NOT IN (@P1,@P2,@P3) ORDER BY no_urut;

SELECT TOP 1 @PLain = p.personel_id, @SatuanNameLain = v.satuan_name
FROM tni.personel p JOIN tni.v_personel v ON v.personel_id = p.personel_id
WHERE p.order_id=@O AND p.satuan_id=@SatLain AND p.deleted_at IS NULL ORDER BY p.no_urut;

SELECT TOP 1 @PCmh = p.personel_id FROM tni.personel p
JOIN tni.satuan s ON s.satuan_id = p.satuan_id
WHERE p.order_id=@O AND s.area_id=@AreaCmh AND p.deleted_at IS NULL ORDER BY p.no_urut;

-- set jadi: semua kecuali @PBelumSet
UPDATE tni.personel SET set_at = SYSDATETIME(), set_by = @U
WHERE personel_id IN (@P1, @P2, @P3, @PLain, @PCmh);

/* ---------- 3. scan OK ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@T1, @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (4, 'scan personel DTJ yang sudah set -> OK', 'OK',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));
INSERT INTO @h VALUES (5, 'isi box jadi 1', '1', CAST((SELECT TOP 1 Isi FROM @r) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (6, 'status personel jadi MASUK_BOX', 'MASUK_BOX',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id=@P1), '');
INSERT INTO @h VALUES (7, 'urut_dalam_box = 1', '1',
    CAST((SELECT urut_dalam_box FROM tni.personel WHERE personel_id=@P1) AS VARCHAR(10)), '');

/* ---------- 4. scan ULANG box yang sama -> SUDAH ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@T1, @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (8, 'scan ulang box sama -> SUDAH', 'SUDAH',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

/* ---------- 5. scan ke box LAIN -> DITOLAK "sudah di box ..." ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@T1, @BoxId=@Box2, @UserId=@U;
INSERT INTO @h VALUES (9, 'sudah di box lain -> DITOLAK', 'DITOLAK',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

/* ---------- 6. BELUM set jadi -> DITOLAK ---------- */
DECLARE @KodeBelum VARCHAR(30) = (SELECT kode_ref FROM tni.personel WHERE personel_id=@PBelumSet);
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@KodeBelum, @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (10, 'belum Set Jadi -> DITOLAK', 'DITOLAK',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

/* ---------- 7. satuan BERBEDA ke box satuan -> KONFIRMASI (2026-10-07) ----------
   Dulu DITOLAK; kini diizinkan setelah konfirmasi UI (@Paksa = 1). */
DECLARE @KodeLain VARCHAR(30) = (SELECT kode_ref FROM tni.personel WHERE personel_id=@PLain);
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@KodeLain, @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (11, 'satuan beda ke box satuan -> KONFIRMASI', 'KONFIRMASI',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));
INSERT INTO @h VALUES (31, 'KONFIRMASI belum menulis (personel belum di box)', 'BELUM',
    (SELECT CASE WHEN boxed_at IS NULL THEN 'BELUM' ELSE 'SUDAH' END FROM tni.personel WHERE personel_id=@PLain), '');
INSERT INTO @h VALUES (12, 'pesan menyebut nama satuan personel', @SatuanNameLain,
    CASE WHEN (SELECT TOP 1 Pesan FROM @r) LIKE '%' + @SatuanNameLain + '%'
         THEN @SatuanNameLain ELSE '(tidak disebut)' END, '');

/* ---------- 8. box GABUNGAN menerima satuan mana pun DI RAWATANNYA ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@KodeLain, @BoxId=@BoxGab, @UserId=@U;
INSERT INTO @h VALUES (13, 'box gabungan terima satuan lain serawatan -> OK', 'OK',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

/* ---------- 9. box GABUNGAN + rawatan lain (Cimahi) -> KONFIRMASI (2026-10-07) ----------
   Harapan bergantung data: personel Cimahi yang sudah ada di box lain tetap DITOLAK. */
DECLARE @KodeCmh VARCHAR(30) = (SELECT kode_ref FROM tni.personel WHERE personel_id=@PCmh);
DECLARE @CmhSudahBox BIT = (SELECT CASE WHEN boxed_at IS NULL THEN 0 ELSE 1 END FROM tni.personel WHERE personel_id=@PCmh);
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@KodeCmh, @BoxId=@BoxGab, @UserId=@U;
INSERT INTO @h VALUES (14, 'box gabungan + rawatan lain -> KONFIRMASI',
    CASE WHEN @CmhSudahBox = 1 THEN 'DITOLAK' ELSE 'KONFIRMASI' END,
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

-- setelah dikonfirmasi (@Paksa = 1) personel rawatan lain masuk box gabungan
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@KodeCmh, @BoxId=@BoxGab, @UserId=@U, @Paksa=1;
INSERT INTO @h VALUES (32, '@Paksa=1 rawatan lain -> OK',
    CASE WHEN @CmhSudahBox = 1 THEN 'DITOLAK' ELSE 'OK' END,
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

/* ---------- 10. kode ngawur ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode='NGAWUR_XYZ', @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (15, 'kode ngawur -> TIDAK_DIKENAL', 'TIDAK_DIKENAL',
    (SELECT TOP 1 Hasil FROM @r), '');

/* ---------- 11. box PENUH ---------- */
-- kecilkan kapasitas box2 jadi 1, isi 1 orang, lalu coba orang kedua
UPDATE tni.box SET kapasitas = 1 WHERE box_id = @Box2;
DECLARE @Kode2 VARCHAR(30) = (SELECT kode_ref FROM tni.personel WHERE personel_id=@P2);
DECLARE @Kode3 VARCHAR(30) = (SELECT kode_ref FROM tni.personel WHERE personel_id=@P3);

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@Kode2, @BoxId=@Box2, @UserId=@U;
INSERT INTO @h VALUES (16, 'isi box2 orang pertama -> OK', 'OK', (SELECT TOP 1 Hasil FROM @r), '');

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@Kode3, @BoxId=@Box2, @UserId=@U;
INSERT INTO @h VALUES (17, 'box penuh -> DITOLAK', 'DITOLAK',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

/* ---------- 12. TUTUP box -> scan ditolak "sudah ditutup" ---------- */
EXEC tni.SIS_Box_Manage @Action='CLOSE', @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (18, 'status box setelah CLOSE', 'TERTUTUP',
    (SELECT [Status] FROM (SELECT CASE WHEN shipped_at IS NOT NULL THEN 'TERKIRIM'
                                       WHEN packed_at IS NOT NULL THEN 'TERTUTUP'
                                       ELSE 'TERBUKA' END AS [Status]
                           FROM tni.box WHERE box_id=@Box1) z), '');

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_MasukBox @Kode=@Kode3, @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (19, 'scan ke box tertutup -> DITOLAK', 'DITOLAK',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

/* ---------- 13. SHIP -> personel di dalamnya jadi TERKIRIM ---------- */
EXEC tni.SIS_Box_Manage @Action='SHIP', @BoxId=@Box1, @UserId=@U;
INSERT INTO @h VALUES (20, 'personel dalam box terkirim -> TERKIRIM', 'TERKIRIM',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id=@P1), '');

/* ---------- 14. SIS_Box_GetById 3 result set ---------- */
CREATE TABLE #isi (PersonelId INT, UrutDalamBox INT, KodeRef VARCHAR(30), Pangkat VARCHAR(50),
                   Nama VARCHAR(150), Nrp VARCHAR(30), SatuanCode VARCHAR(10), SatuanName VARCHAR(150),
                   PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30), BoxedAt DATETIME2);
-- hanya result set ke-2 yang bisa ditangkap INSERT..EXEC, jadi dicek lewat view saja
INSERT INTO @h VALUES (21, 'isi box1 lewat view', '1',
    CAST((SELECT COUNT(*) FROM tni.v_personel WHERE box_id=@Box1) AS VARCHAR(10)), '');
-- +1 bila uji 32 (@Paksa=1) berhasil memasukkan personel Cimahi
INSERT INTO @h VALUES (22, 'isi box gabungan lewat view', CASE WHEN @CmhSudahBox = 1 THEN '1' ELSE '2' END,
    CAST((SELECT COUNT(*) FROM tni.v_personel WHERE box_id=@BoxGab) AS VARCHAR(10)), '');

/* ---------- 15. SIS_Box_List status turunan ---------- */
CREATE TABLE #list (BoxId INT, BoxCode VARCHAR(30), BoxNo INT,   -- BoxNo: alter_72
                    AreaId INT, AreaCode VARCHAR(10), AreaName VARCHAR(150),
                    SatuanId INT, SatuanCode VARCHAR(10), SatuanName VARCHAR(150), Gabungan BIT,
                    Urut INT, Kapasitas INT, Isi INT, JumlahSatuan INT,
                    PackedAt DATETIME2, PackedByNama VARCHAR(150), ShippedAt DATETIME2,
                    ShippedByNama VARCHAR(150), Keterangan VARCHAR(255), [Status] VARCHAR(20));

INSERT INTO #list EXEC tni.SIS_Box_List @OrderId=@O;
INSERT INTO @h VALUES (23, 'SIS_Box_List: 3 box', '3', CAST((SELECT COUNT(*) FROM #list) - @BoxAwal AS VARCHAR(10)),
    (SELECT STRING_AGG(CONCAT(BoxCode,'=',[Status]), ' ') FROM #list));

TRUNCATE TABLE #list;
INSERT INTO #list EXEC tni.SIS_Box_List @OrderId=@O, @Status='TERBUKA';
INSERT INTO @h VALUES (24, 'filter TERBUKA -> 2 box (box2 + gabungan)', '2',
    CAST((SELECT COUNT(*) FROM #list) - @BoxAwalTerbuka AS VARCHAR(10)), '');

TRUNCATE TABLE #list;
INSERT INTO #list EXEC tni.SIS_Box_List @OrderId=@O, @Gabungan=1;
INSERT INTO @h VALUES (25, 'filter Gabungan=1 -> 1 box', '1',
    CAST((SELECT COUNT(*) FROM #list) AS VARCHAR(10)), (SELECT TOP 1 BoxCode FROM #list));

ROLLBACK TRANSACTION;

/* ============================================================
   Uji PENOLAKAN SIS_Box_Manage -- transaksi sendiri (RAISERROR + XACT_ABORT)
   ============================================================ */

-- CLOSE box kosong
BEGIN TRANSACTION;
DECLARE @Sat2 INT = (SELECT TOP 1 satuan_id FROM tni.satuan s
                      JOIN tni.area_rawatan a ON a.area_id=s.area_id
                      WHERE a.order_id=@O AND s.deleted_at IS NULL ORDER BY s.satuan_id);
DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@Sat2, @UserId=@U;
DECLARE @BoxKosong INT = (SELECT TOP 1 BoxId FROM @Buat);
BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='CLOSE', @BoxId=@BoxKosong, @UserId=@U;
    INSERT INTO @h VALUES (26, 'CLOSE box kosong', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (26, 'CLOSE box kosong', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

-- SHIP box yang belum ditutup
BEGIN TRANSACTION;
DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@Sat2, @UserId=@U;
DECLARE @BoxBelumTutup INT = (SELECT TOP 1 BoxId FROM @Buat);
BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='SHIP', @BoxId=@BoxBelumTutup, @UserId=@U;
    INSERT INTO @h VALUES (27, 'SHIP box belum ditutup', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (27, 'SHIP box belum ditutup', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

-- DELETE box kosong & belum ditutup -> BOLEH
BEGIN TRANSACTION;
DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@Sat2, @UserId=@U;
DECLARE @BoxHapus INT = (SELECT TOP 1 BoxId FROM @Buat);
DECLARE @UrutHapus INT = (SELECT urut FROM tni.box WHERE box_id=@BoxHapus);
BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='DELETE', @BoxId=@BoxHapus, @Alasan='Salah buka', @UserId=@U;
    INSERT INTO @h VALUES (28, 'DELETE box kosong', '1 (terhapus)',
        CONCAT((SELECT COUNT(*) FROM tni.box WHERE box_id=@BoxHapus AND deleted_at IS NOT NULL), ' (terhapus)'), '');

    -- nomor TIDAK didaur ulang: box berikutnya dapat urut berikutnya
    DELETE FROM @Buat;
    INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@Sat2, @UserId=@U;
    INSERT INTO @h VALUES (29, 'nomor box TIDAK didaur ulang', CAST(@UrutHapus + 1 AS VARCHAR(10)),
        CAST((SELECT TOP 1 Urut FROM @Buat) AS VARCHAR(10)), (SELECT TOP 1 BoxCode FROM @Buat));
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (28, 'DELETE box kosong', '1 (terhapus)', 'ERROR', ERROR_MESSAGE());
END CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

-- CREATE gabungan tanpa AreaId
BEGIN TRY
    EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @UserId=@U;
    INSERT INTO @h VALUES (30, 'CREATE tanpa satuan & rawatan', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (30, 'CREATE tanpa satuan & rawatan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 68) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

-- bukti bersih
SELECT (SELECT COUNT(*) FROM tni.box)                                   AS sisa_box,
       (SELECT COUNT(*) FROM tni.personel WHERE boxed_at IS NOT NULL)   AS sisa_boxed,
       (SELECT COUNT(*) FROM tni.personel WHERE set_at IS NOT NULL)     AS sisa_set;
GO

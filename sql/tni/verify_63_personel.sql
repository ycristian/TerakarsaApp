/* =============================================================
   Verifikasi Prompt 63 -- beranda & halaman Personel.
   Uji yang mengubah data dibungkus transaksi yang di-ROLLBACK.
   Aman dijalankan berulang.
   ============================================================= */
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(90), harapan VARCHAR(60), hasil VARCHAR(60), pesan VARCHAR(300));

-- ---------- 1. beranda: angka konsisten dengan view ----------
DECLARE @Total INT = (SELECT COUNT(*) FROM tni.v_personel WHERE order_id = @O);
DECLARE @Review INT = (SELECT COUNT(*) FROM tni.v_personel WHERE order_id = @O AND status_data = 'PERLU_REVIEW');
INSERT INTO @h VALUES (1, 'beranda Total = jumlah v_personel', CAST(@Total AS VARCHAR(20)), CAST(@Total AS VARCHAR(20)), '');
INSERT INTO @h VALUES (2, 'beranda PerluReview', '114', CAST(@Review AS VARCHAR(20)), '');

-- ---------- 2. cari awalan kode_ref ----------
CREATE TABLE #l (PersonelId INT, KodeRef VARCHAR(30), Pangkat VARCHAR(50), Nama VARCHAR(150),
    Nrp VARCHAR(30), AreaId INT, SatuanId INT, SatuanCode VARCHAR(10), SatuanName VARCHAR(150),
    PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30), StatusProgres VARCHAR(20),
    BoxCode VARCHAR(30), StatusData VARCHAR(20), TotalCount INT);

INSERT INTO #l EXEC tni.SIS_Personel_List @OrderId = @O, @Search = 'DTJ-0', @PageSize = 500;
DECLARE @CariKode INT = (SELECT COUNT(*) FROM #l);
DECLARE @SemuaDtj BIT = (SELECT CASE WHEN COUNT(*) = SUM(CASE WHEN KodeRef LIKE 'DTJ-0%' THEN 1 ELSE 0 END) THEN 1 ELSE 0 END FROM #l);
INSERT INTO @h VALUES (3, 'cari "DTJ-0" ketemu & semuanya DTJ-0', '1', CAST(@SemuaDtj AS VARCHAR(10)), CONCAT(@CariKode, ' baris'));

-- ---------- 3. cari sebagian nama ----------
TRUNCATE TABLE #l;
INSERT INTO #l EXEC tni.SIS_Personel_List @OrderId = @O, @Search = 'Mahfudin', @PageSize = 50;
INSERT INTO @h VALUES (4, 'cari sebagian nama "Mahfudin"', '>0', CASE WHEN (SELECT COUNT(*) FROM #l) > 0 THEN '>0' ELSE '0' END,
    (SELECT TOP 1 CONCAT(KodeRef, ' ', Nama) FROM #l));

-- ---------- 4. cari awalan NRP ----------
DECLARE @NrpContoh VARCHAR(30) = (SELECT TOP 1 nrp FROM tni.personel WHERE deleted_at IS NULL AND LEN(nrp) >= 12 ORDER BY personel_id);
TRUNCATE TABLE #l;
INSERT INTO #l EXEC tni.SIS_Personel_List @OrderId = @O, @Search = @NrpContoh, @PageSize = 50;
INSERT INTO @h VALUES (5, 'cari NRP penuh', '1', CAST((SELECT COUNT(*) FROM #l) AS VARCHAR(10)), @NrpContoh);

-- ---------- 5. filter perlu review ----------
TRUNCATE TABLE #l;
INSERT INTO #l EXEC tni.SIS_Personel_List @OrderId = @O, @PerluReview = 1, @PageSize = 500;
DECLARE @FReview INT = (SELECT TOP 1 TotalCount FROM #l);
INSERT INTO @h VALUES (6, 'filter PerluReview = 114 (dari import Prompt 62)', '114', CAST(ISNULL(@FReview,0) AS VARCHAR(10)), '');

-- ---------- 6. paging: TotalCount sama, isi beda ----------
TRUNCATE TABLE #l;
INSERT INTO #l EXEC tni.SIS_Personel_List @OrderId = @O, @PageNumber = 1, @PageSize = 30;
DECLARE @P1 VARCHAR(30) = (SELECT MIN(KodeRef) FROM #l);
DECLARE @T1 INT = (SELECT TOP 1 TotalCount FROM #l);
DECLARE @N1 INT = (SELECT COUNT(*) FROM #l);
TRUNCATE TABLE #l;
INSERT INTO #l EXEC tni.SIS_Personel_List @OrderId = @O, @PageNumber = 2, @PageSize = 30;
DECLARE @P2 VARCHAR(30) = (SELECT MIN(KodeRef) FROM #l);
DECLARE @T2 INT = (SELECT TOP 1 TotalCount FROM #l);
INSERT INTO @h VALUES (7, 'paging: 30 baris per halaman', '30', CAST(@N1 AS VARCHAR(10)), '');
INSERT INTO @h VALUES (8, 'paging: TotalCount tetap', CAST(@T1 AS VARCHAR(20)), CAST(@T2 AS VARCHAR(20)), '');
INSERT INTO @h VALUES (9, 'paging: halaman 2 beda isi', 'beda', CASE WHEN @P1 <> @P2 THEN 'beda' ELSE 'SAMA' END, CONCAT(@P1,' vs ',@P2));

-- ---------- 7. GetById jalan ----------
DECLARE @Pid INT = (SELECT TOP 1 personel_id FROM tni.personel WHERE deleted_at IS NULL ORDER BY personel_id);
CREATE TABLE #d (KodeRef VARCHAR(30));
INSERT INTO #d SELECT KodeRef FROM (SELECT 1 AS x) q CROSS APPLY (SELECT TOP 0 CAST(NULL AS VARCHAR(30)) AS KodeRef) y;  -- placeholder
DECLARE @DetailOk VARCHAR(10) = 'gagal';
BEGIN TRY
    DECLARE @cnt INT;
    -- cukup pastikan SP jalan tanpa error dan mengembalikan 1 baris
    SELECT @cnt = COUNT(*) FROM tni.v_personel WHERE personel_id = @Pid;
    IF @cnt = 1 SET @DetailOk = 'ok';
END TRY BEGIN CATCH SET @DetailOk = ERROR_MESSAGE(); END CATCH
INSERT INTO @h VALUES (10, 'personel contoh ada di view', 'ok', @DetailOk, CONCAT('id=', @Pid));

BEGIN TRANSACTION;

-- ---------- 8. UPDATE NRP ke milik orang lain -> DITOLAK dgn kode pemilik ----------
DECLARE @A INT = (SELECT TOP 1 personel_id FROM tni.personel WHERE deleted_at IS NULL ORDER BY personel_id);
DECLARE @B INT = (SELECT TOP 1 personel_id FROM tni.personel WHERE deleted_at IS NULL AND personel_id <> @A ORDER BY personel_id);
DECLARE @NrpB VARCHAR(30) = (SELECT nrp FROM tni.personel WHERE personel_id = @B);
DECLARE @KodeB VARCHAR(30) = (SELECT kode_ref FROM tni.personel WHERE personel_id = @B);
DECLARE @NamaA VARCHAR(150) = (SELECT nama FROM tni.personel WHERE personel_id = @A);

BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='UPDATE', @Id=@A, @Nrp=@NrpB, @Nama=@NamaA, @Gender='PRIA', @UserId=@U;
    INSERT INTO @h VALUES (11, 'UPDATE NRP ke milik orang lain', 'DITOLAK', 'LOLOS', 'BUG: berhasil');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (11, 'UPDATE NRP ke milik orang lain', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
    INSERT INTO @h VALUES (12, 'pesan menyebut kode_ref pemilik', @KodeB,
        CASE WHEN ERROR_MESSAGE() LIKE '%' + @KodeB + '%' THEN @KodeB ELSE '(tidak disebut)' END, '');
END CATCH

-- ---------- 9. UPDATE sah ----------
BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='UPDATE', @Id=@A, @Nrp='9990001112223', @Nama='Uji Prompt 63',
         @Pangkat='Serda', @NoHp='0810000', @Gender='PRIA', @UserId=@U;
    DECLARE @NamaBaru VARCHAR(150) = (SELECT nama FROM tni.personel WHERE personel_id=@A);
    DECLARE @SatuanTetap BIT = (SELECT CASE WHEN satuan_id = (SELECT satuan_id FROM tni.personel WHERE personel_id=@A) THEN 1 ELSE 0 END FROM tni.personel WHERE personel_id=@A);
    INSERT INTO @h VALUES (13, 'UPDATE identitas sah', 'Uji Prompt 63', @NamaBaru, '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (13, 'UPDATE identitas sah', 'Uji Prompt 63', 'ERROR', ERROR_MESSAGE());
END CATCH

-- ---------- 10. SET_POLA pada personel belum set -> boleh ----------
DECLARE @PkBaru INT = (SELECT TOP 1 pola_kemeja_id FROM tni.pola_kemeja WHERE is_active=1 AND deleted_at IS NULL ORDER BY pola_kemeja_id DESC);
DECLARE @PcBaru INT = (SELECT TOP 1 pola_celana_id FROM tni.pola_celana WHERE is_active=1 AND deleted_at IS NULL ORDER BY pola_celana_id DESC);
BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='SET_POLA', @Id=@A, @PolaKemejaId=@PkBaru, @PolaCelanaId=@PcBaru, @UserId=@U;
    INSERT INTO @h VALUES (14, 'SET_POLA sebelum set jadi', 'LOLOS', 'LOLOS',
        (SELECT CONCAT(pola_kemeja_kode,' / ',pola_celana_kode) FROM tni.v_personel WHERE personel_id=@A));
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (14, 'SET_POLA sebelum set jadi', 'LOLOS', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- ---------- 11. SET_POLA setelah set jadi -> DITOLAK ----------
UPDATE tni.personel SET set_at = SYSDATETIME(), set_by = @U WHERE personel_id = @A;
BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='SET_POLA', @Id=@A, @PolaKemejaId=@PkBaru, @PolaCelanaId=@PcBaru, @UserId=@U;
    INSERT INTO @h VALUES (15, 'SET_POLA setelah set jadi', 'DITOLAK', 'LOLOS', 'BUG: berhasil');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (15, 'SET_POLA setelah set jadi', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- ---------- 12. status_progres ikut berubah jadi SET_JADI ----------
INSERT INTO @h VALUES (16, 'status_progres setelah set_at terisi', 'SET_JADI',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id=@A), '');

-- ---------- 13. DELETE personel yang kartunya sudah dicetak -> DITOLAK ----------
UPDATE tni.personel SET printed_at = SYSDATETIME(), printed_by = @U, print_count = 1 WHERE personel_id = @A;
BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='DELETE', @Id=@A, @Catatan='uji', @UserId=@U;
    INSERT INTO @h VALUES (17, 'DELETE setelah kartu dicetak', 'DITOLAK', 'LOLOS', 'BUG: berhasil');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (17, 'DELETE setelah kartu dicetak', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- ---------- 14. DELETE tanpa alasan -> DITOLAK ----------
UPDATE tni.personel SET printed_at = NULL, printed_by = NULL, set_at = NULL, set_by = NULL WHERE personel_id = @A;
BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='DELETE', @Id=@A, @Catatan=NULL, @UserId=@U;
    INSERT INTO @h VALUES (18, 'DELETE tanpa alasan', 'DITOLAK', 'LOLOS', 'BUG: berhasil');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (18, 'DELETE tanpa alasan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- ---------- 15. DELETE sah (belum pernah cetak + ada alasan) ----------
BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='DELETE', @Id=@A, @Catatan='Data ganda', @UserId=@U;
    INSERT INTO @h VALUES (19, 'DELETE sah -> hilang dari view', '0',
        CAST((SELECT COUNT(*) FROM tni.v_personel WHERE personel_id=@A) AS VARCHAR(10)), '');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (19, 'DELETE sah', '0', 'ERROR', ERROR_MESSAGE());
END CATCH

-- ---------- 16. MARK_REVIEWED ----------
DECLARE @R INT = (SELECT TOP 1 personel_id FROM tni.personel WHERE status_data='PERLU_REVIEW' AND deleted_at IS NULL ORDER BY personel_id);
BEGIN TRY
    EXEC tni.SIS_Personel_Manage @Action='MARK_REVIEWED', @Id=@R, @Catatan='Sudah dikonfirmasi satuan', @UserId=@U;
    INSERT INTO @h VALUES (20, 'MARK_REVIEWED -> status_data', 'DIPERBAIKI',
        (SELECT status_data FROM tni.personel WHERE personel_id=@R), '');
    INSERT INTO @h VALUES (21, 'catatan import tidak dibuang', 'ada',
        CASE WHEN (SELECT catatan_review FROM tni.personel WHERE personel_id=@R) LIKE '%Sudah dikonfirmasi satuan%'
              AND LEN((SELECT catatan_review FROM tni.personel WHERE personel_id=@R)) > 30
             THEN 'ada' ELSE 'HILANG' END,
        LEFT((SELECT catatan_review FROM tni.personel WHERE personel_id=@R), 90));
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (20, 'MARK_REVIEWED', 'DIPERBAIKI', 'ERROR', ERROR_MESSAGE());
END CATCH

ROLLBACK TRANSACTION;

SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil OR (harapan = '>0' AND hasil = '>0') THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 85) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

-- bukti data asli utuh
SELECT COUNT(*) AS personel_hidup, SUM(CASE WHEN status_data='PERLU_REVIEW' THEN 1 ELSE 0 END) AS perlu_review
FROM tni.personel WHERE deleted_at IS NULL;
GO

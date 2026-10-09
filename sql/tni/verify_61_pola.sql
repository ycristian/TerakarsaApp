/* =============================================================
   Verifikasi Prompt 61 -- master pola.
   Seluruh uji yang MENGUBAH data dibungkus transaksi yang di-ROLLBACK,
   jadi master hasil seed tidak tersentuh. Aman dijalankan berulang.
   ============================================================= */
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @hasil TABLE (no_uji INT, uji VARCHAR(90), harapan VARCHAR(90), hasil VARCHAR(90), pesan VARCHAR(300));

-- ---------- 1. jumlah master hasil seed ----------
DECLARE @K INT = (SELECT COUNT(*) FROM tni.pola_kemeja WHERE deleted_at IS NULL);
DECLARE @C INT = (SELECT COUNT(*) FROM tni.pola_celana WHERE deleted_at IS NULL);
INSERT INTO @hasil VALUES (1, 'jumlah pola kemeja hidup', '98', CAST(@K AS VARCHAR(10)), '');
INSERT INTO @hasil VALUES (2, 'jumlah pola celana hidup', '59', CAST(@C AS VARCHAR(10)), '');

-- ---------- 2. cari lewat kode_alt ----------
DECLARE @KodeAlt VARCHAR(30) = (SELECT kode FROM tni.pola_kemeja WHERE kode_alt = '14,5-3' AND deleted_at IS NULL);
INSERT INTO @hasil VALUES (3, 'cari kode_alt "14,5-3"', 'LD_102_P', ISNULL(@KodeAlt,'(tidak ketemu)'), '');

-- ---------- 3. LD_118_PG memang TIDAK ada di master ----------
DECLARE @Ada118 INT = (SELECT COUNT(*) FROM tni.pola_kemeja WHERE kode = 'LD_118_PG' AND deleted_at IS NULL);
INSERT INTO @hasil VALUES (4, 'LD_118_PG tidak ada di master (akan TOLAK di Prompt 62)', '0', CAST(@Ada118 AS VARCHAR(10)), '');

-- ---------- 4. manset: hijab terisi, non-hijab NULL ----------
DECLARE @MansetWH DECIMAL(5,1) = (SELECT lingkar_manset FROM tni.pola_kemeja WHERE kode = 'LD_96_WH' AND deleted_at IS NULL);
DECLARE @MansetW  DECIMAL(5,1) = (SELECT lingkar_manset FROM tni.pola_kemeja WHERE kode = 'LD_96_W'  AND deleted_at IS NULL);
INSERT INTO @hasil VALUES (5, 'LD_96_WH punya lingkar_manset', 'ada', CASE WHEN @MansetWH IS NULL THEN 'NULL' ELSE 'ada' END, '');
INSERT INTO @hasil VALUES (6, 'LD_96_W tanpa lingkar_manset', 'NULL', CASE WHEN @MansetW IS NULL THEN 'NULL' ELSE 'ada' END, '');

BEGIN TRANSACTION;

-- ---------- 5. kode dobel harus DITOLAK ----------
BEGIN TRY
    EXEC tni.SIS_Pola_Manage @Action='CREATE', @JenisItem='KEMEJA', @Kode='LD_102_P',
         @TargetGender='P', @LingkarDadaAcuan=102, @UserId=@U;
    INSERT INTO @hasil VALUES (7, 'CREATE kode kemeja yang sudah ada', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (7, 'CREATE kode kemeja yang sudah ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- ---------- 6. target_gender salah jenis harus DITOLAK ----------
BEGIN TRY
    EXEC tni.SIS_Pola_Manage @Action='CREATE', @JenisItem='CELANA', @Kode='UJI_61_C',
         @TargetGender='WH', @SizeAngka=32, @UserId=@U;
    INSERT INTO @hasil VALUES (8, 'CREATE celana target_gender WH', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (8, 'CREATE celana target_gender WH', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- ---------- 7. kemeja tanpa lingkar_dada_acuan harus DITOLAK ----------
BEGIN TRY
    EXEC tni.SIS_Pola_Manage @Action='CREATE', @JenisItem='KEMEJA', @Kode='UJI_61_K2',
         @TargetGender='P', @UserId=@U;
    INSERT INTO @hasil VALUES (9, 'CREATE kemeja tanpa lingkar_dada_acuan', 'DITOLAK', 'LOLOS', 'BUG: berhasil masuk');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (9, 'CREATE kemeja tanpa lingkar_dada_acuan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- ---------- 8. CREATE sah + manset dipaksa NULL untuk non-hijab ----------
BEGIN TRY
    EXEC tni.SIS_Pola_Manage @Action='CREATE', @JenisItem='KEMEJA', @Kode='UJI_61_K',
         @TargetGender='P', @LingkarDadaAcuan=99, @LingkarKerah=37.5, @LingkarManset=22, @UserId=@U;

    DECLARE @NewId INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='UJI_61_K' AND deleted_at IS NULL);
    DECLARE @NewManset DECIMAL(5,1) = (SELECT lingkar_manset FROM tni.pola_kemeja WHERE pola_kemeja_id=@NewId);
    DECLARE @NewKerah DECIMAL(5,1) = (SELECT lingkar_kerah FROM tni.pola_kemeja WHERE pola_kemeja_id=@NewId);

    INSERT INTO @hasil VALUES (10, 'CREATE kemeja sah', 'LOLOS', 'LOLOS', CONCAT('id=', @NewId));
    INSERT INTO @hasil VALUES (11, 'manset dipaksa NULL untuk gender P', 'NULL',
        CASE WHEN @NewManset IS NULL THEN 'NULL' ELSE CAST(@NewManset AS VARCHAR(10)) END, '');
    INSERT INTO @hasil VALUES (12, 'decimal 37.5 tidak dibulatkan', '37.5', CAST(@NewKerah AS VARCHAR(10)), '');

    -- ---------- 9. SET_AKTIF ----------
    EXEC tni.SIS_Pola_Manage @Action='SET_AKTIF', @JenisItem='KEMEJA', @Id=@NewId, @IsActive=0, @UserId=@U;
    DECLARE @Aktif BIT = (SELECT is_active FROM tni.pola_kemeja WHERE pola_kemeja_id=@NewId);
    INSERT INTO @hasil VALUES (13, 'SET_AKTIF 0', '0', CAST(@Aktif AS VARCHAR(10)), '');

    -- ---------- 10. pola nonaktif hilang dari list @HanyaAktif = 1 ----------
    DECLARE @AdaDiAktif INT;
    CREATE TABLE #l (PolaId INT, JenisItem VARCHAR(10), Kode VARCHAR(30), KodeAlt VARCHAR(30),
        TargetGender VARCHAR(10), SizeAngka INT, LingkarDadaAcuan DECIMAL(5,1), IsActive BIT,
        LingkarKerah DECIMAL(5,1), LebarBahu DECIMAL(5,1), LingkarDada DECIMAL(5,1),
        LingkarPerut DECIMAL(5,1), LingkarPinggul DECIMAL(5,1), PanjangBaju DECIMAL(5,1),
        LingkarLengan DECIMAL(5,1), LingkarKerungLengan DECIMAL(5,1), PanjangLengan DECIMAL(5,1),
        LingkarManset DECIMAL(5,1), LingkarPinggang DECIMAL(5,1), LingkarSelangkang DECIMAL(5,1),
        LingkarPaha DECIMAL(5,1), LingkarLutut DECIMAL(5,1), LingkarKaki DECIMAL(5,1),
        PanjangCelana DECIMAL(5,1), JumlahPemakai INT);
    INSERT INTO #l EXEC tni.SIS_Pola_List @JenisItem='KEMEJA', @HanyaAktif=1;
    SELECT @AdaDiAktif = COUNT(*) FROM #l WHERE Kode='UJI_61_K';
    INSERT INTO @hasil VALUES (14, 'pola nonaktif hilang dari list HanyaAktif=1', '0', CAST(@AdaDiAktif AS VARCHAR(10)), '');

    -- ---------- 11. DELETE pola tanpa pemakai -> boleh ----------
    EXEC tni.SIS_Pola_Manage @Action='DELETE', @JenisItem='KEMEJA', @Id=@NewId, @UserId=@U;
    DECLARE @Sisa INT = (SELECT COUNT(*) FROM tni.pola_kemeja WHERE pola_kemeja_id=@NewId AND deleted_at IS NULL);
    INSERT INTO @hasil VALUES (15, 'DELETE pola 0 pemakai', '0 (terhapus)', CONCAT(@Sisa, CASE WHEN @Sisa=0 THEN ' (terhapus)' ELSE ' (masih hidup)' END), '');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (99, 'blok CREATE/SET_AKTIF/DELETE', 'LOLOS', 'ERROR', ERROR_MESSAGE());
END CATCH

-- ---------- 12. DELETE pola yang masih dipakai personel -> DITOLAK ----------
-- Buat satu personel sementara yang memakai LD_102_P + celana apa pun.
BEGIN TRY
    DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active=1 AND deleted_at IS NULL ORDER BY order_id DESC);
    DECLARE @S INT = (SELECT TOP 1 s.satuan_id FROM tni.satuan s
                        JOIN tni.area_rawatan a ON a.area_id=s.area_id
                       WHERE a.order_id=@O AND s.deleted_at IS NULL ORDER BY s.satuan_id);
    DECLARE @PK INT = (SELECT pola_kemeja_id FROM tni.pola_kemeja WHERE kode='LD_102_P' AND deleted_at IS NULL);
    DECLARE @PC INT = (SELECT TOP 1 pola_celana_id FROM tni.pola_celana WHERE deleted_at IS NULL ORDER BY pola_celana_id);

    INSERT INTO tni.personel (order_id, satuan_id, kode_ref, no_urut, qr_token, nama, nrp, gender,
                              pola_kemeja_id, pola_celana_id, created_by)
    VALUES (@O, @S, 'UJI-999', 999, 'UJI61TOKEN', 'Uji Prompt 61', 'UJI61NRP', 'PRIA', @PK, @PC, @U);

    -- jumlah pemakai lewat SP list harus ikut naik
    CREATE TABLE #l2 (PolaId INT, JenisItem VARCHAR(10), Kode VARCHAR(30), KodeAlt VARCHAR(30),
        TargetGender VARCHAR(10), SizeAngka INT, LingkarDadaAcuan DECIMAL(5,1), IsActive BIT,
        LingkarKerah DECIMAL(5,1), LebarBahu DECIMAL(5,1), LingkarDada DECIMAL(5,1),
        LingkarPerut DECIMAL(5,1), LingkarPinggul DECIMAL(5,1), PanjangBaju DECIMAL(5,1),
        LingkarLengan DECIMAL(5,1), LingkarKerungLengan DECIMAL(5,1), PanjangLengan DECIMAL(5,1),
        LingkarManset DECIMAL(5,1), LingkarPinggang DECIMAL(5,1), LingkarSelangkang DECIMAL(5,1),
        LingkarPaha DECIMAL(5,1), LingkarLutut DECIMAL(5,1), LingkarKaki DECIMAL(5,1),
        PanjangCelana DECIMAL(5,1), JumlahPemakai INT);
    INSERT INTO #l2 EXEC tni.SIS_Pola_List @JenisItem='KEMEJA', @Search='LD_102_P';
    DECLARE @Pemakai INT = (SELECT TOP 1 JumlahPemakai FROM #l2 WHERE Kode='LD_102_P');
    INSERT INTO @hasil VALUES (16, 'JumlahPemakai LD_102_P setelah 1 personel', '1', CAST(ISNULL(@Pemakai,-1) AS VARCHAR(10)), '');

    BEGIN TRY
        EXEC tni.SIS_Pola_Manage @Action='DELETE', @JenisItem='KEMEJA', @Id=@PK, @UserId=@U;
        INSERT INTO @hasil VALUES (17, 'DELETE pola yang dipakai personel', 'DITOLAK', 'LOLOS', 'BUG: berhasil dihapus');
    END TRY
    BEGIN CATCH
        INSERT INTO @hasil VALUES (17, 'DELETE pola yang dipakai personel', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
    END CATCH

    -- ---------- 13. status_progres personel baru = BELUM_CETAK ----------
    DECLARE @Status VARCHAR(20) = (SELECT status_progres FROM tni.v_personel WHERE kode_ref='UJI-999');
    INSERT INTO @hasil VALUES (18, 'status_progres personel baru', 'BELUM_CETAK', ISNULL(@Status,'(NULL)'), '');
END TRY
BEGIN CATCH
    INSERT INTO @hasil VALUES (98, 'blok personel', 'LOLOS', 'ERROR', ERROR_MESSAGE());
END CATCH

ROLLBACK TRANSACTION;

SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil OR (harapan = 'DITOLAK' AND hasil = 'DITOLAK')
            THEN 'SESUAI' ELSE '*** TIDAK SESUAI ***' END AS kesimpulan,
       LEFT(pesan, 90) AS pesan
FROM @hasil
ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ',
              (SELECT COUNT(*) FROM @hasil WHERE harapan = hasil), ' dari ',
              (SELECT COUNT(*) FROM @hasil)) AS ringkasan;

-- bukti tidak ada sisa data uji
SELECT (SELECT COUNT(*) FROM tni.personel     WHERE kode_ref = 'UJI-999')        AS sisa_personel,
       (SELECT COUNT(*) FROM tni.pola_kemeja  WHERE kode LIKE 'UJI_61%')         AS sisa_pola_uji,
       (SELECT COUNT(*) FROM tni.pola_kemeja  WHERE deleted_at IS NULL)          AS pola_kemeja_hidup,
       (SELECT COUNT(*) FROM tni.pola_celana  WHERE deleted_at IS NULL)          AS pola_celana_hidup;
GO

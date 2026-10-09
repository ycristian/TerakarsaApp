/* =============================================================
   Verifikasi Prompt 69 -- dashboard progres & kebutuhan size.

   Kedua SP READ-ONLY, jadi seluruh uji aman dalam satu transaksi yang
   di-ROLLBACK. Uji 6-9 memang MENULIS (scan set jadi) untuk membuktikan
   angka dashboard ikut berubah -- semuanya ikut di-rollback.
   Aman dijalankan berulang -- tidak ada data yang tertinggal.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(70), hasil VARCHAR(70), pesan VARCHAR(300));

-- bentuk kedua result set SIS_Dashboard_Progres
DECLARE @area TABLE (AreaId INT, AreaCode VARCHAR(10), AreaName VARCHAR(150), Kota VARCHAR(100),
                     Total INT, BelumCetak INT, Dicetak INT, SetJadi INT, MasukBox INT, Terkirim INT,
                     PersenBox DECIMAL(5,1), PersenKirim DECIMAL(5,1),
                     BoxTerbuka INT, BoxTertutup INT, BoxTerkirim INT);

DECLARE @sat TABLE (AreaId INT, AreaCode VARCHAR(10), AreaName VARCHAR(150),
                    SatuanId INT, SatuanCode VARCHAR(10), SatuanName VARCHAR(150),
                    Total INT, BelumCetak INT, Dicetak INT, SetJadi INT, MasukBox INT, Terkirim INT,
                    PersenBox DECIMAL(5,1), PersenKirim DECIMAL(5,1),
                    BoxTerbuka INT, BoxTertutup INT, BoxTerkirim INT);

DECLARE @size TABLE (PolaId INT, JenisItem VARCHAR(10), Kode VARCHAR(30), IsActive BIT,
                     Butuh INT, Saldo INT, StokBebas INT, Dijatah INT, Selisih INT,
                     GrupGender VARCHAR(10));

-- INSERT ... EXEC menolak SP yang mengembalikan LEBIH DARI SATU result set
-- ("Column name or number of supplied values does not match table definition"),
-- jadi SP-nya menerima @Bagian untuk meminta satu result set saja. Aplikasi
-- tetap memanggil tanpa @Bagian dan mendapat keduanya sekali jalan.
BEGIN TRANSACTION;

/* ============================================================
   1-3. kolom status per area berjumlah = total personel area
   ============================================================ */
INSERT INTO @area EXEC tni.SIS_Dashboard_Progres @OrderId = @O, @Bagian = 'AREA';

INSERT INTO @h VALUES (1, 'jumlah 5 kolom status = Total, tiap area', '0 area menyimpang',
    CONCAT((SELECT COUNT(*) FROM @area
             WHERE BelumCetak + Dicetak + SetJadi + MasukBox + Terkirim <> Total), ' area menyimpang'), '');

INSERT INTO @h VALUES (2, 'SUM(Total) semua area = personel order ini',
    CAST((SELECT COUNT(*) FROM tni.v_personel WHERE order_id = @O) AS VARCHAR(10)),
    CAST((SELECT SUM(Total) FROM @area) AS VARCHAR(10)), '');

INSERT INTO @h VALUES (3, 'jumlah area = area hidup di order ini',
    CAST((SELECT COUNT(*) FROM tni.area_rawatan WHERE order_id = @O AND deleted_at IS NULL) AS VARCHAR(10)),
    CAST((SELECT COUNT(*) FROM @area) AS VARCHAR(10)), '');

/* ============================================================
   4-5. angka per area = penjumlahan satuan-satuannya
   ============================================================ */
-- result set KEDUA, langsung dari SP yang sama
INSERT INTO @sat EXEC tni.SIS_Dashboard_Progres @OrderId = @O, @Bagian = 'SATUAN';

INSERT INTO @h VALUES (4, 'Total area = SUM(Total) satuannya', '0 area menyimpang',
    CONCAT((SELECT COUNT(*) FROM @area a
             WHERE a.Total <> (SELECT ISNULL(SUM(s.Total),0) FROM @sat s WHERE s.AreaId = a.AreaId)),
           ' area menyimpang'), '');

INSERT INTO @h VALUES (5, 'BelumCetak area = SUM(BelumCetak) satuannya', '0 area menyimpang',
    CONCAT((SELECT COUNT(*) FROM @area a
             WHERE a.BelumCetak <> (SELECT ISNULL(SUM(s.BelumCetak),0) FROM @sat s WHERE s.AreaId = a.AreaId)),
           ' area menyimpang'), '');

/* ============================================================
   6-9. setelah satu scan Set Jadi: belum-dapat-set turun 1 dan
        butuh pola terkait turun 1
   ============================================================ */
DECLARE @SatDtj INT, @AreaBdg INT;
SELECT @SatDtj = s.satuan_id, @AreaBdg = a.area_id
FROM tni.satuan s JOIN tni.area_rawatan a ON a.area_id = s.area_id
WHERE a.order_id = @O AND s.satuan_code = 'DTJ' AND s.deleted_at IS NULL;

DECLARE @Pid INT, @Tok VARCHAR(40), @PolaK INT, @KodeK VARCHAR(30);
SELECT TOP 1 @Pid = personel_id, @Tok = qr_token, @PolaK = pola_kemeja_id
FROM tni.personel
WHERE order_id = @O AND satuan_id = @SatDtj AND deleted_at IS NULL
  AND set_at IS NULL AND boxed_at IS NULL
ORDER BY no_urut;

SELECT @KodeK = kode FROM tni.pola_kemeja WHERE pola_kemeja_id = @PolaK;

-- angka SEBELUM scan
DECLARE @BelumSetSebelum INT = (SELECT BelumCetak + Dicetak FROM @area WHERE AreaId = @AreaBdg);

DELETE FROM @size;
INSERT INTO @size EXEC tni.SIS_Dashboard_KebutuhanSize @OrderId=@O, @AreaId=@AreaBdg, @JenisItem='KEMEJA';
DECLARE @ButuhSebelum INT = (SELECT Butuh FROM @size WHERE PolaId = @PolaK);
DECLARE @SelisihSebelum INT = (SELECT Selisih FROM @size WHERE PolaId = @PolaK);

-- scan Set Jadi satu kartu
DECLARE @scan TABLE (Hasil VARCHAR(20), Pesan VARCHAR(300), PersonelId INT, KodeRef VARCHAR(30),
                     Pangkat VARCHAR(50), Nama VARCHAR(150), SatuanName VARCHAR(150),
                     PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                     SetAt DATETIME2, SetByNama VARCHAR(150), SaldoKemeja INT, SaldoCelana INT,
                     BoxCode VARCHAR(30), Isi INT, Kapasitas INT);
INSERT INTO @scan EXEC tni.SIS_Scan_SetJadi @Kode=@Tok, @UserId=@U;
INSERT INTO @h VALUES (6, 'scan Set Jadi untuk uji berhasil', 'OK',
    (SELECT TOP 1 Hasil FROM @scan), (SELECT TOP 1 KodeRef FROM @scan));

-- angka SESUDAH scan
DELETE FROM @area;
INSERT INTO @area EXEC tni.SIS_Dashboard_Progres @OrderId = @O, @Bagian = 'AREA';

INSERT INTO @h VALUES (7, 'belum-dapat-set area turun 1', CAST(@BelumSetSebelum - 1 AS VARCHAR(10)),
    CAST((SELECT BelumCetak + Dicetak FROM @area WHERE AreaId = @AreaBdg) AS VARCHAR(10)), '');

INSERT INTO @h VALUES (8, 'SetJadi area naik 1 (total tetap)',
    CAST((SELECT COUNT(*) FROM tni.v_personel WHERE order_id = @O AND area_id = @AreaBdg) AS VARCHAR(10)),
    CAST((SELECT BelumCetak + Dicetak + SetJadi + MasukBox + Terkirim FROM @area WHERE AreaId = @AreaBdg) AS VARCHAR(10)), '');

DELETE FROM @size;
INSERT INTO @size EXEC tni.SIS_Dashboard_KebutuhanSize @OrderId=@O, @AreaId=@AreaBdg, @JenisItem='KEMEJA';

INSERT INTO @h VALUES (9, CONCAT('butuh pola ', @KodeK, ' turun 1'), CAST(@ButuhSebelum - 1 AS VARCHAR(10)),
    CAST((SELECT Butuh FROM @size WHERE PolaId = @PolaK) AS VARCHAR(10)), '');

-- Selisih = Saldo - Butuh. Scan Set Jadi menurunkan KEDUANYA satu (butuh -1
-- karena personel sudah dapat set, saldo -1 karena mutasi TERPAKAI), jadi
-- selisih justru TIDAK BERUBAH -- kekurangan produksi tetap sama.
INSERT INTO @h VALUES (10, 'selisih TETAP (butuh -1 dan saldo -1 saling menutup)',
    CAST(@SelisihSebelum AS VARCHAR(10)),
    CAST((SELECT Selisih FROM @size WHERE PolaId = @PolaK) AS VARCHAR(10)), '');

/* ============================================================
   11-15. kebutuhan size: rumus, urutan, stok global
   ============================================================ */
INSERT INTO @h VALUES (11, 'Selisih = Saldo - Butuh, semua baris', '0 baris menyimpang',
    CONCAT((SELECT COUNT(*) FROM @size WHERE Selisih <> Saldo - Butuh), ' baris menyimpang'), '');

INSERT INTO @h VALUES (12, 'StokBebas = Saldo - Dijatah, semua baris', '0 baris menyimpang',
    CONCAT((SELECT COUNT(*) FROM @size WHERE StokBebas <> Saldo - Dijatah), ' baris menyimpang'), '');

-- 2026-10-07: urut grup gender P, PG, W, WH (bukan lagi paling kurang di atas)
INSERT INTO @h VALUES (13, 'urut grup gender P, PG, W, WH', 'URUT',
    CASE WHEN EXISTS (
        SELECT 1 FROM (SELECT CHARINDEX('|' + GrupGender + '|', '|P|PG|W|WH|') g, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) rn FROM @size) x
        JOIN (SELECT CHARINDEX('|' + GrupGender + '|', '|P|PG|W|WH|') g, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) rn FROM @size) y
          ON y.rn = x.rn + 1
        WHERE y.g < x.g
    ) THEN 'TIDAK URUT' ELSE 'URUT' END, '');

INSERT INTO @h VALUES (14, 'hanya pola dengan Butuh > 0 atau Saldo <> 0', '0 baris menyimpang',
    CONCAT((SELECT COUNT(*) FROM @size WHERE Butuh = 0 AND Saldo = 0), ' baris menyimpang'), '');

-- butuh per area < butuh global; saldo IDENTIK (stok tidak dibagi per area)
DECLARE @ButuhArea INT = (SELECT SUM(Butuh) FROM @size);
DECLARE @SaldoArea INT = (SELECT SUM(Saldo) FROM @size);

DELETE FROM @size;
INSERT INTO @size EXEC tni.SIS_Dashboard_KebutuhanSize @OrderId=@O, @JenisItem='KEMEJA';

INSERT INTO @h VALUES (15, 'butuh global = total personel belum dapat set',
    CAST((SELECT COUNT(*) FROM tni.v_personel
           WHERE order_id = @O AND status_progres IN ('BELUM_CETAK','DICETAK')) AS VARCHAR(10)),
    CAST((SELECT SUM(Butuh) FROM @size) AS VARCHAR(10)), '');

INSERT INTO @h VALUES (16, 'butuh per rawatan LEBIH KECIL dari butuh global', 'YA',
    CASE WHEN @ButuhArea < (SELECT SUM(Butuh) FROM @size) THEN 'YA' ELSE 'TIDAK' END,
    CONCAT('BDG=', @ButuhArea, ' global=', (SELECT SUM(Butuh) FROM @size)));

INSERT INTO @h VALUES (17, 'SALDO TIDAK dibagi per area (sama dengan global)',
    CAST((SELECT SUM(Saldo) FROM @size) AS VARCHAR(10)), CAST(@SaldoArea AS VARCHAR(10)), '');

-- celana juga jalan
DELETE FROM @size;
INSERT INTO @size EXEC tni.SIS_Dashboard_KebutuhanSize @OrderId=@O, @JenisItem='CELANA';
INSERT INTO @h VALUES (18, 'jenis CELANA mengembalikan baris', 'ADA',
    CASE WHEN (SELECT COUNT(*) FROM @size) > 0 THEN 'ADA' ELSE 'KOSONG' END,
    CONCAT((SELECT COUNT(*) FROM @size), ' pola celana'));

INSERT INTO @h VALUES (19, 'semua baris CELANA berjenis CELANA', '0 baris menyimpang',
    CONCAT((SELECT COUNT(*) FROM @size WHERE JenisItem <> 'CELANA'), ' baris menyimpang'), '');

ROLLBACK TRANSACTION;

/* ---------- jenis ngawur ditolak (di luar transaksi: RAISERROR) ---------- */
BEGIN TRY
    EXEC tni.SIS_Dashboard_KebutuhanSize @OrderId=@O, @JenisItem='SEPATU';
    INSERT INTO @h VALUES (20, 'jenis item tidak dikenal', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (20, 'jenis item tidak dikenal', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

/* ============================================================
   HASIL
   ============================================================ */
SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 68) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

-- bukti bersih
SELECT (SELECT COUNT(*) FROM tni.personel WHERE set_at IS NOT NULL) AS sisa_set,
       (SELECT COUNT(*) FROM tni.stok_mutasi)                       AS sisa_mutasi,
       (SELECT COUNT(*) FROM tni.personel)                          AS total_personel;
GO

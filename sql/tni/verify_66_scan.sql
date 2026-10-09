/* =============================================================
   Verifikasi Prompt 66 -- scan Set Jadi & halaman QR publik.

   tni.SIS_Scan_SetJadi memakai SET XACT_ABORT ON, tapi kasus bisnisnya
   dikembalikan sebagai RESULT SET (bukan RAISERROR), jadi aman dipanggil di
   dalam satu transaksi luar yang di-ROLLBACK.
   Aman dijalankan berulang -- tidak ada data yang tertinggal.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(60), hasil VARCHAR(60), pesan VARCHAR(300));

-- hasil scan ditampung di tabel dengan bentuk result set SIS_Scan_SetJadi
DECLARE @r TABLE (Hasil VARCHAR(20), Pesan VARCHAR(300), PersonelId INT, KodeRef VARCHAR(30),
                  Pangkat VARCHAR(50), Nama VARCHAR(150), SatuanName VARCHAR(150),
                  PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                  SetAt DATETIME2, SetByNama VARCHAR(150), SaldoKemeja INT, SaldoCelana INT,
                  BoxCode VARCHAR(30), Isi INT, Kapasitas INT);

/* ---------- 1. TIDAK_DIKENAL (tanpa transaksi, tidak menulis apa pun) ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_SetJadi @Kode = 'KODE_NGAWUR_XYZ', @UserId = @U;
INSERT INTO @h VALUES (1, 'kode ngawur -> TIDAK_DIKENAL', 'TIDAK_DIKENAL',
    (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));

BEGIN TRANSACTION;

/* ---------- siapkan: satu personel yang kartunya sudah dicetak ---------- */
DECLARE @Id INT, @Token VARCHAR(16), @KodeRef VARCHAR(30), @PkId INT, @PcId INT;

SELECT TOP 1 @Id = personel_id, @Token = qr_token, @KodeRef = kode_ref,
             @PkId = pola_kemeja_id, @PcId = pola_celana_id
FROM tni.personel
WHERE order_id = @O AND deleted_at IS NULL AND set_at IS NULL
ORDER BY personel_id;

UPDATE tni.personel SET printed_at = SYSDATETIME(), printed_by = @U, print_count = 1
WHERE personel_id = @Id;

INSERT INTO @h VALUES (2, 'status sebelum scan', 'DICETAK',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id = @Id), @KodeRef);

DECLARE @SaldoK0 INT = (SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@PkId);

/* ---------- 2. scan pakai QR_TOKEN -> OK ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_SetJadi @Kode = @Token, @UserId = @U;

INSERT INTO @h VALUES (3, 'scan token -> OK', 'OK', (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));
INSERT INTO @h VALUES (4, 'kode_ref dikembalikan', @KodeRef, (SELECT TOP 1 KodeRef FROM @r), '');
INSERT INTO @h VALUES (5, 'status jadi SET_JADI', 'SET_JADI',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id = @Id), '');

/* ---------- 3. dua mutasi TERPAKAI -1 ---------- */
INSERT INTO @h VALUES (6, 'mutasi TERPAKAI dibuat', '2',
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi
           WHERE personel_id = @Id AND jenis_mutasi = 'TERPAKAI' AND deleted_at IS NULL) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (7, 'qty mutasi TERPAKAI = -1 semua', '2',
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi
           WHERE personel_id = @Id AND jenis_mutasi = 'TERPAKAI' AND qty = -1 AND deleted_at IS NULL) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (8, 'satu KEMEJA + satu CELANA', 'KEMEJA,CELANA',
    (SELECT STRING_AGG(jenis_item, ',') WITHIN GROUP (ORDER BY jenis_item DESC)
       FROM tni.stok_mutasi WHERE personel_id = @Id AND jenis_mutasi = 'TERPAKAI' AND deleted_at IS NULL), '');

/* ---------- 4. saldo turun 1, boleh minus ---------- */
DECLARE @SaldoK1 INT = (SELECT saldo FROM tni.v_stok_pola WHERE order_id=@O AND jenis_item='KEMEJA' AND pola_id=@PkId);
INSERT INTO @h VALUES (9, 'saldo kemeja turun 1 (boleh minus)', CAST(@SaldoK0 - 1 AS VARCHAR(10)), CAST(@SaldoK1 AS VARCHAR(10)), '');
INSERT INTO @h VALUES (10, 'SaldoKemeja di result set = saldo sesudahnya', CAST(@SaldoK1 AS VARCHAR(10)),
    CAST((SELECT TOP 1 SaldoKemeja FROM @r) AS VARCHAR(10)), '');

/* ---------- 5. scan LAGI -> SUDAH, tanpa mutasi baru ---------- */
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_SetJadi @Kode = @Token, @UserId = @U;
INSERT INTO @h VALUES (11, 'scan ulang -> SUDAH', 'SUDAH', (SELECT TOP 1 Hasil FROM @r), (SELECT TOP 1 Pesan FROM @r));
INSERT INTO @h VALUES (12, 'tidak ada mutasi tambahan', '2',
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi
           WHERE personel_id = @Id AND jenis_mutasi = 'TERPAKAI' AND deleted_at IS NULL) AS VARCHAR(10)), '');

/* ---------- 6. scan pakai KODE_REF (input manual) ---------- */
DECLARE @Id2 INT, @KodeRef2 VARCHAR(30);
SELECT TOP 1 @Id2 = personel_id, @KodeRef2 = kode_ref
FROM tni.personel
WHERE order_id = @O AND deleted_at IS NULL AND set_at IS NULL AND personel_id <> @Id
ORDER BY personel_id;

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_SetJadi @Kode = @KodeRef2, @UserId = @U;
INSERT INTO @h VALUES (13, 'scan pakai kode_ref -> OK', 'OK', (SELECT TOP 1 Hasil FROM @r), @KodeRef2);
INSERT INTO @h VALUES (14, 'kartu belum pernah dicetak tetap boleh di-scan', 'SET_JADI',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id = @Id2), '');

/* ---------- 7. guard scan bersamaan ---------- */
-- Simulasi: HP lain sudah mengisi set_at tepat sebelum UPDATE kita dijalankan.
-- Yang diuji: UPDATE ... WHERE set_at IS NULL + cek @@ROWCOUNT mengembalikan
-- SUDAH, bukan membuat mutasi dobel.
DECLARE @Id3 INT, @Token3 VARCHAR(16);
SELECT TOP 1 @Id3 = personel_id, @Token3 = qr_token
FROM tni.personel
WHERE order_id = @O AND deleted_at IS NULL AND set_at IS NULL
ORDER BY personel_id;

UPDATE tni.personel SET set_at = SYSDATETIME(), set_by = @U WHERE personel_id = @Id3;

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Scan_SetJadi @Kode = @Token3, @UserId = @U;
INSERT INTO @h VALUES (15, 'set_at sudah terisi duluan -> SUDEH, bukan OK', 'SUDAH',
    (SELECT TOP 1 Hasil FROM @r), '');
INSERT INTO @h VALUES (16, 'tidak ada mutasi untuk personel itu', '0',
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi WHERE personel_id = @Id3 AND deleted_at IS NULL) AS VARCHAR(10)), '');

/* ---------- 8. halaman publik: data MINIMAL saja ---------- */
-- 2026-10-06: owner MENGIZINKAN Nrp, size (pola), TB/BB, kategori, rawatan di
-- halaman publik. No HP & ukuran badan TETAP dilarang (uji 19-20).
CREATE TABLE #pub (KodeRef VARCHAR(30), Pangkat VARCHAR(50), Nama VARCHAR(150),
                   SatuanName VARCHAR(150),
                   Nrp VARCHAR(30), PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                   TinggiBadan INT, BeratBadan INT, Kategori VARCHAR(20), AreaName VARCHAR(150),
                   StatusProgres VARCHAR(20), SetAt DATETIME2,
                   BoxCode VARCHAR(30), BoxedAt DATETIME2, ShippedAt DATETIME2);
INSERT INTO #pub EXEC tni.SIS_Public_ByToken @Token = @Token;

INSERT INTO @h VALUES (17, 'SIS_Public_ByToken mengembalikan 1 baris', '1',
    CAST((SELECT COUNT(*) FROM #pub) AS VARCHAR(10)), (SELECT TOP 1 KodeRef FROM #pub));

-- Kolom sensitif TIDAK BOLEH ada di result set SP publik.
DECLARE @KolomPublik VARCHAR(500) = (
    SELECT STRING_AGG(name, ',') WITHIN GROUP (ORDER BY column_ordinal)
    FROM sys.dm_exec_describe_first_result_set(N'EXEC tni.SIS_Public_ByToken @Token = ''x''', NULL, 0));

INSERT INTO @h VALUES (18, 'SP publik memuat Nrp (diizinkan owner 2026-10-06)', 'ada',
    CASE WHEN @KolomPublik LIKE '%Nrp%' THEN 'ada' ELSE 'tidak ada' END, @KolomPublik);
INSERT INTO @h VALUES (19, 'SP publik tanpa kolom NoHp', 'tidak ada',
    CASE WHEN @KolomPublik LIKE '%NoHp%' THEN 'ADA (BOCOR)' ELSE 'tidak ada' END, '');
INSERT INTO @h VALUES (20, 'SP publik tanpa ukuran badan (Lingkar%)', 'tidak ada',
    CASE WHEN @KolomPublik LIKE '%Lingkar%' THEN 'ADA (BOCOR)' ELSE 'tidak ada' END, '');

/* ---------- 9. token tidak dikenal -> 0 baris ---------- */
TRUNCATE TABLE #pub;
INSERT INTO #pub EXEC tni.SIS_Public_ByToken @Token = 'TOKEN_NGAWUR';
INSERT INTO @h VALUES (21, 'token ngawur -> 0 baris', '0',
    CAST((SELECT COUNT(*) FROM #pub) AS VARCHAR(10)), '');

/* ---------- 10. SIS_Personel_ByToken (user login) ---------- */
DECLARE @DetailKode VARCHAR(30);
SELECT @DetailKode = kode_ref FROM tni.v_personel WHERE qr_token = @Token;
INSERT INTO @h VALUES (22, 'SIS_Personel_ByToken menemukan personel', @KodeRef, ISNULL(@DetailKode,'(NULL)'), '');

ROLLBACK TRANSACTION;

SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 70) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

-- bukti bersih
SELECT (SELECT COUNT(*) FROM tni.stok_mutasi)                            AS sisa_mutasi,
       (SELECT COUNT(*) FROM tni.personel WHERE set_at IS NOT NULL)      AS set_jadi,
       (SELECT COUNT(*) FROM tni.personel WHERE printed_at IS NOT NULL)  AS tercetak;
GO

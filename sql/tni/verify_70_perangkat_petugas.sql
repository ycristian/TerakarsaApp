/* =============================================================
   Verifikasi: perangkat TNI tanpa login (pairing) & nama petugas
   per perangkat (alter_75 -- tidak ada lagi tabel petugas).

   SP memakai SET XACT_ABORT ON, jadi uji dipisah per FASE:
     FASE A -- jalur sukses, satu transaksi yang di-ROLLBACK
     FASE B -- jalur penolakan, TANPA transaksi luar (RAISERROR di dalam
               transaksi luar membuatnya DOOMED), dibereskan manual
   Aman dijalankan berulang -- tidak ada data yang tertinggal.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Username = 'tni_system');
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders
                   WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

DECLARE @h TABLE (no_uji INT, uji VARCHAR(90), harapan VARCHAR(60), hasil VARCHAR(60), pesan VARCHAR(250));
DECLARE @r TABLE (v INT);
DECLARE @p TABLE (PairingCode VARCHAR(10), ExpiresAt DATETIME2);
DECLARE @me TABLE (PerangkatId INT, PerangkatCode VARCHAR(30),
                   PerangkatName VARCHAR(150), NamaPetugas VARCHAR(150),   -- alter_75
                   PairedAt DATETIME2,
                   MenuAkses NVARCHAR(400));                               -- alter_74

/* ============================================================
   FASE A -- jalur sukses
   ============================================================ */
BEGIN TRANSACTION;

-- 1. buat perangkat (nama petugas wajib)
INSERT INTO @r EXEC tni.SIS_Perangkat_Manage @Action = 'CREATE', @PerangkatCode = 'UJI01',
    @PerangkatName = 'Tablet Uji', @NamaPetugas = 'Budi Uji', @UserId = @U;
DECLARE @Pid INT = (SELECT TOP 1 v FROM @r);
INSERT INTO @h VALUES (1, 'CREATE perangkat', 'ADA', IIF(@Pid > 0, 'ADA', 'TIDAK'), '');

-- 2-3. kode pairing + masa berlaku
INSERT INTO @p EXEC tni.SIS_Perangkat_Manage @Action = 'GENERATE_PAIRING', @Id = @Pid,
    @PairingCode = 'ABC23', @UserId = @U;
INSERT INTO @h VALUES (2, 'GENERATE_PAIRING mengembalikan kode', 'ABC23',
    (SELECT TOP 1 PairingCode FROM @p), '');
-- Rentang, bukan nilai pas: DATEDIFF MINUTE memotong pecahan sehingga hasilnya
-- bergantung pada selisih milidetik antara SP dan baris ini.
INSERT INTO @h VALUES (3, 'kode berlaku ~15 menit', 'YA',
    IIF(DATEDIFF(SECOND, SYSDATETIME(), (SELECT TOP 1 ExpiresAt FROM @p)) BETWEEN 840 AND 900,
        'YA', 'TIDAK'),
    CONCAT(DATEDIFF(SECOND, SYSDATETIME(), (SELECT TOP 1 ExpiresAt FROM @p)), ' detik'));

-- 4. klaim kode -> token
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Perangkat_Manage @Action = 'CLAIM_PAIRING',
    @PairingCode = 'ABC23', @NewToken = 'tokenujicoba0001';
INSERT INTO @h VALUES (4, 'CLAIM_PAIRING berhasil', CAST(@Pid AS VARCHAR(10)),
    CAST((SELECT TOP 1 v FROM @r) AS VARCHAR(10)), '');

-- 5-6. token dikenali, paired_at terisi; 7. nama petugas ikut dari perangkat
INSERT INTO @me EXEC tni.SIS_Perangkat_GetByToken @Token = 'tokenujicoba0001';
INSERT INTO @h VALUES (5, 'GetByToken mengenali perangkat', 'Tablet Uji',
    (SELECT TOP 1 PerangkatName FROM @me), '');
INSERT INTO @h VALUES (6, 'paired_at terisi', 'ADA',
    IIF((SELECT TOP 1 PairedAt FROM @me) IS NOT NULL, 'ADA', 'TIDAK'), '');
INSERT INTO @h VALUES (7, 'GetByToken membawa nama petugas perangkat', 'Budi Uji',
    (SELECT TOP 1 NamaPetugas FROM @me), '');

-- 8. kode hangus setelah diklaim
INSERT INTO @h VALUES (8, 'pairing_code dikosongkan setelah klaim', 'NULL',
    ISNULL((SELECT pairing_code FROM tni.perangkat WHERE perangkat_id = @Pid), 'NULL'), '');

-- 9. UNPAIR -> token lama mati
EXEC tni.SIS_Perangkat_Manage @Action = 'UNPAIR', @Id = @Pid, @UserId = @U;
DELETE FROM @me;
INSERT INTO @me EXEC tni.SIS_Perangkat_GetByToken @Token = 'tokenujicoba0001';
INSERT INTO @h VALUES (9, 'token lama MATI setelah UNPAIR', '0',
    CAST((SELECT COUNT(*) FROM @me) AS VARCHAR(10)), '');

-- 10-15. jejak scan memakai PERANGKAT
DECLARE @Tok VARCHAR(40), @PersId INT;
SELECT TOP 1 @Tok = qr_token, @PersId = personel_id
FROM tni.personel
WHERE order_id = @O AND deleted_at IS NULL AND set_at IS NULL
ORDER BY no_urut;

DECLARE @scan TABLE (Hasil VARCHAR(20), Pesan VARCHAR(300), PersonelId INT, KodeRef VARCHAR(30),
                     Pangkat VARCHAR(50), Nama VARCHAR(150), SatuanName VARCHAR(150),
                     PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                     SetAt DATETIME2, SetByNama VARCHAR(150), SaldoKemeja INT, SaldoCelana INT,
                     BoxCode VARCHAR(30), Isi INT, Kapasitas INT);

INSERT INTO @scan EXEC tni.SIS_Scan_SetJadi @Kode = @Tok, @UserId = @U, @PerangkatId = @Pid;

INSERT INTO @h VALUES (10, 'scan Set Jadi lewat perangkat', 'OK',
    (SELECT TOP 1 Hasil FROM @scan), '');
INSERT INTO @h VALUES (11, 'set_perangkat_id tersimpan', CAST(@Pid AS VARCHAR(10)),
    CAST((SELECT set_perangkat_id FROM tni.personel WHERE personel_id = @PersId) AS VARCHAR(10)), '');
-- created_by TETAP user id (aturan CLAUDE.md), yaitu user sistem tni_system
INSERT INTO @h VALUES (12, 'set_by = user sistem tni_system', CAST(@U AS VARCHAR(10)),
    CAST((SELECT set_by FROM tni.personel WHERE personel_id = @PersId) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (13, 'mutasi TERPAKAI ikut bawa perangkat', '2',
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi
           WHERE personel_id = @PersId AND perangkat_id = @Pid) AS VARCHAR(10)), '');
-- Yang DITAMPILKAN ke layar harus nama PETUGAS perangkat, bukan "TNI System"
INSERT INTO @h VALUES (14, 'SetByNama = nama petugas perangkat', 'Budi Uji',
    (SELECT TOP 1 SetByNama FROM @scan), '');

-- 15. ganti nama petugas perangkat -> riwayat ikut berganti (dibaca dari perangkat)
EXEC tni.SIS_Perangkat_Manage @Action = 'UPDATE', @Id = @Pid, @PerangkatCode = 'UJI01',
    @PerangkatName = 'Tablet Uji', @NamaPetugas = 'Sari Uji', @UserId = @U;
INSERT INTO @h VALUES (15, 'riwayat ikut nama petugas terbaru', 'Sari Uji',
    (SELECT TOP 1 SetByNama FROM (
        SELECT COALESCE(pr.nama_petugas, u.FullName) AS SetByNama
        FROM tni.v_personel v
        LEFT JOIN Users u ON u.Id = v.set_by
        LEFT JOIN tni.perangkat pr ON pr.perangkat_id = v.set_perangkat_id
        WHERE v.personel_id = @PersId) x), '');

ROLLBACK TRANSACTION;

/* ============================================================
   FASE B -- jalur penolakan, di LUAR transaksi
   ============================================================ */
DECLARE @r2 TABLE (v INT);
INSERT INTO @r2 EXEC tni.SIS_Perangkat_Manage @Action = 'CREATE', @PerangkatCode = 'UJI02',
    @PerangkatName = 'Tablet Fase B', @NamaPetugas = 'Petugas Fase B', @UserId = @U;
DECLARE @Pid2 INT = (SELECT TOP 1 v FROM @r2);

DECLARE @p2 TABLE (PairingCode VARCHAR(10), ExpiresAt DATETIME2);
INSERT INTO @p2 EXEC tni.SIS_Perangkat_Manage @Action = 'GENERATE_PAIRING', @Id = @Pid2,
    @PairingCode = 'XYZ47', @UserId = @U;

DECLARE @r3 TABLE (v INT);
INSERT INTO @r3 EXEC tni.SIS_Perangkat_Manage @Action = 'CLAIM_PAIRING',
    @PairingCode = 'XYZ47', @NewToken = 'tokenfaseb000001';

-- 16. kode SEKALI PAKAI
BEGIN TRY
    EXEC tni.SIS_Perangkat_Manage @Action = 'CLAIM_PAIRING',
        @PairingCode = 'XYZ47', @NewToken = 'tokenlain00000002';
    INSERT INTO @h VALUES (16, 'klaim kode yang sama dua kali', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (16, 'klaim kode yang sama dua kali', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 17. kode ngawur
BEGIN TRY
    EXEC tni.SIS_Perangkat_Manage @Action = 'CLAIM_PAIRING',
        @PairingCode = 'ZZZZZ', @NewToken = 'tokenlain00000003';
    INSERT INTO @h VALUES (17, 'klaim kode yang tidak ada', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (17, 'klaim kode yang tidak ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 18. kode perangkat dobel
BEGIN TRY
    EXEC tni.SIS_Perangkat_Manage @Action = 'CREATE', @PerangkatCode = 'UJI02',
        @PerangkatName = 'Tablet Kembar', @NamaPetugas = 'Siapa Saja', @UserId = @U;
    INSERT INTO @h VALUES (18, 'kode perangkat dobel', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (18, 'kode perangkat dobel', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 19. perangkat NONAKTIF tidak bisa diklaim
EXEC tni.SIS_Perangkat_Manage @Action = 'GENERATE_PAIRING', @Id = @Pid2,
    @PairingCode = 'QWE89', @UserId = @U;
UPDATE tni.perangkat SET is_active = 0 WHERE perangkat_id = @Pid2;
BEGIN TRY
    EXEC tni.SIS_Perangkat_Manage @Action = 'CLAIM_PAIRING',
        @PairingCode = 'QWE89', @NewToken = 'tokenlain00000004';
    INSERT INTO @h VALUES (19, 'klaim perangkat nonaktif', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (19, 'klaim perangkat nonaktif', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH
UPDATE tni.perangkat SET is_active = 1 WHERE perangkat_id = @Pid2;

-- 20. CREATE tanpa nama petugas
BEGIN TRY
    EXEC tni.SIS_Perangkat_Manage @Action = 'CREATE', @PerangkatCode = 'UJI03',
        @PerangkatName = 'Tanpa Petugas', @NamaPetugas = '   ', @UserId = @U;
    INSERT INTO @h VALUES (20, 'CREATE tanpa nama petugas', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (20, 'CREATE tanpa nama petugas', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 21. UPDATE mengosongkan nama petugas
BEGIN TRY
    EXEC tni.SIS_Perangkat_Manage @Action = 'UPDATE', @Id = @Pid2, @PerangkatCode = 'UJI02',
        @PerangkatName = 'Tablet Fase B', @NamaPetugas = NULL, @UserId = @U;
    INSERT INTO @h VALUES (21, 'UPDATE mengosongkan nama petugas', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (21, 'UPDATE mengosongkan nama petugas', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 22. tabel petugas sudah tidak ada (alter_75)
INSERT INTO @h VALUES (22, 'tabel tni.petugas sudah dihapus', 'TIDAK ADA',
    IIF(OBJECT_ID('tni.petugas','U') IS NULL, 'TIDAK ADA', 'MASIH ADA'), '');

/* ---------- bereskan FASE B ---------- */
DELETE FROM tni.perangkat_menu WHERE perangkat_id = @Pid2;   -- alter_74: CREATE ikut membuat baris menu
DELETE FROM tni.perangkat      WHERE perangkat_id = @Pid2;

/* ============================================================
   HASIL
   ============================================================ */
SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 62) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

-- bukti bersih
SELECT (SELECT COUNT(*) FROM tni.perangkat)                          AS sisa_perangkat,
       (SELECT COUNT(*) FROM tni.perangkat_menu)                     AS sisa_menu,
       (SELECT COUNT(*) FROM tni.personel WHERE set_at IS NOT NULL)  AS sisa_set,
       (SELECT COUNT(*) FROM tni.stok_mutasi)                        AS sisa_mutasi,
       (SELECT COUNT(*) FROM tni.personel)                           AS total_personel;
GO

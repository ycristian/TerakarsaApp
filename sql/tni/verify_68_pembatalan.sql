/* =============================================================
   Verifikasi Prompt 68 -- pengajuan & persetujuan pembatalan scan.

   SIS_Pembatalan_Manage memakai RAISERROR + XACT_ABORT ON. Transaksi luar
   yang kena RAISERROR jadi DOOMED, jadi uji dipisah per FASE:
     FASE A  -- jalur sukses (satu transaksi, di-ROLLBACK di akhir)
     FASE B  -- jalur penolakan (tanpa transaksi luar; disiapkan & dibereskan
                manual supaya tidak meninggalkan data)
   Aman dijalankan berulang -- tidak ada data yang tertinggal.
   ============================================================= */
SET NOCOUNT ON;

DECLARE @U INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);
DECLARE @O INT = (SELECT TOP 1 order_id FROM tni.orders WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);
DECLARE @h TABLE (no_uji INT, uji VARCHAR(95), harapan VARCHAR(70), hasil VARCHAR(70), pesan VARCHAR(300));

-- bentuk result set SIS_Pembatalan_Manage
DECLARE @r TABLE (PembatalanId INT, KodeRef VARCHAR(30), Jenis VARCHAR(10),
                  BoxCode VARCHAR(30), BoxDibukaUlang BIT);
DECLARE @Buat TABLE (BoxId INT, BoxCode VARCHAR(30), Urut INT, BoxNo INT);   -- BoxNo: alter_72

/* ============================================================
   FASE A -- jalur sukses
   ============================================================ */
BEGIN TRANSACTION;

DECLARE @SatDtj INT, @AreaBdg INT;
SELECT @SatDtj = s.satuan_id, @AreaBdg = a.area_id
FROM tni.satuan s JOIN tni.area_rawatan a ON a.area_id = s.area_id
WHERE a.order_id = @O AND s.satuan_code = 'DTJ' AND s.deleted_at IS NULL;

-- dua box DTJ
DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@SatDtj, @UserId=@U;
DECLARE @BoxA INT = (SELECT TOP 1 BoxId FROM @Buat), @BoxACode VARCHAR(30) = (SELECT TOP 1 BoxCode FROM @Buat);

DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@SatDtj, @UserId=@U;
DECLARE @BoxB INT = (SELECT TOP 1 BoxId FROM @Buat), @BoxBCode VARCHAR(30) = (SELECT TOP 1 BoxCode FROM @Buat);

-- empat personel DTJ: P1/P2 dipakai uji BOX, P3 uji SET, P4 uji BOX pada box TERTUTUP
DECLARE @P TABLE (rn INT, personel_id INT, qr_token VARCHAR(40), kode_ref VARCHAR(30),
                  pola_kemeja_id INT, pola_celana_id INT);
INSERT INTO @P
SELECT TOP 4 ROW_NUMBER() OVER (ORDER BY no_urut), personel_id, qr_token, kode_ref,
       pola_kemeja_id, pola_celana_id
FROM tni.personel
WHERE order_id = @O AND satuan_id = @SatDtj AND deleted_at IS NULL
  AND set_at IS NULL AND boxed_at IS NULL
ORDER BY no_urut;

DECLARE @P1 INT = (SELECT personel_id FROM @P WHERE rn=1),
        @P3 INT = (SELECT personel_id FROM @P WHERE rn=3),
        @P4 INT = (SELECT personel_id FROM @P WHERE rn=4);
DECLARE @T1 VARCHAR(40) = (SELECT qr_token FROM @P WHERE rn=1),
        @T2 VARCHAR(40) = (SELECT qr_token FROM @P WHERE rn=2),
        @T4 VARCHAR(40) = (SELECT qr_token FROM @P WHERE rn=4);
DECLARE @K3 INT = (SELECT pola_kemeja_id FROM @P WHERE rn=3),
        @C3 INT = (SELECT pola_celana_id FROM @P WHERE rn=3);

-- Kartunya dianggap SUDAH DICETAK: status_progres mundur ke DICETAK (bukan
-- BELUM_CETAK) setelah batal SET hanya kalau printed_at terisi.
UPDATE tni.personel
SET printed_at = SYSDATETIME(), printed_by = @U, print_count = 1
WHERE personel_id IN (SELECT personel_id FROM @P);

-- semuanya di-set jadi dulu (lewat SP supaya mutasi TERPAKAI ikut tercatat).
--
-- SIS_Scan_SetJadi dan SIS_Scan_MasukBox BENTUK RESULT SET-nya BERBEDA
-- (set jadi membawa saldo stok, masuk box membawa kode & isi box), jadi
-- masing-masing punya tabel penampung sendiri.
DECLARE @set TABLE (Hasil VARCHAR(20), Pesan VARCHAR(300), PersonelId INT, KodeRef VARCHAR(30),
                    Pangkat VARCHAR(50), Nama VARCHAR(150), SatuanName VARCHAR(150),
                    PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                    SetAt DATETIME2, SetByNama VARCHAR(150), SaldoKemeja INT, SaldoCelana INT,
                    BoxCode VARCHAR(30), Isi INT, Kapasitas INT);
DECLARE @scan TABLE (Hasil VARCHAR(20), Pesan VARCHAR(300), PersonelId INT, KodeRef VARCHAR(30),
                     Pangkat VARCHAR(50), Nama VARCHAR(150), SatuanName VARCHAR(150),
                     PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                     BoxCode VARCHAR(30), Isi INT, Kapasitas INT,
                     SetAt DATETIME2, SetByNama VARCHAR(150), SaldoKemeja INT, SaldoCelana INT);

DECLARE @T3 VARCHAR(40) = (SELECT qr_token FROM @P WHERE rn=3);
INSERT INTO @set EXEC tni.SIS_Scan_SetJadi @Kode=@T1, @UserId=@U;
INSERT INTO @set EXEC tni.SIS_Scan_SetJadi @Kode=@T2, @UserId=@U;
INSERT INTO @set EXEC tni.SIS_Scan_SetJadi @Kode=@T3, @UserId=@U;
INSERT INTO @set EXEC tni.SIS_Scan_SetJadi @Kode=@T4, @UserId=@U;
DELETE FROM @set;

-- P1 & P2 masuk BoxA (box TERBUKA), P4 masuk BoxB lalu BoxB ditutup
INSERT INTO @scan EXEC tni.SIS_Scan_MasukBox @Kode=@T1, @BoxId=@BoxA, @UserId=@U;
DELETE FROM @scan;
INSERT INTO @scan EXEC tni.SIS_Scan_MasukBox @Kode=@T2, @BoxId=@BoxA, @UserId=@U;
DELETE FROM @scan;
INSERT INTO @scan EXEC tni.SIS_Scan_MasukBox @Kode=@T4, @BoxId=@BoxB, @UserId=@U;
DELETE FROM @scan;
EXEC tni.SIS_Box_Manage @Action='CLOSE', @BoxId=@BoxB, @UserId=@U;

/* ---------- 1. AJUKAN batal BOX pada box TERBUKA ----------
   2026-10-07: BOX TIDAK PERLU PERSETUJUAN -- AJUKAN langsung dieksekusi. */
DECLARE @IsiSebelum INT = (SELECT COUNT(*) FROM tni.personel WHERE box_id=@BoxA AND deleted_at IS NULL);
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@P1,
    @Jenis='BOX', @Alasan='Salah ambil box', @UserId=@U;
DECLARE @Pb1 INT = (SELECT TOP 1 PembatalanId FROM @r);

INSERT INTO @h VALUES (1, 'AJUKAN batal BOX -> langsung DISETUJUI', 'DISETUJUI',
    (SELECT [status] FROM tni.pembatalan WHERE pembatalan_id=@Pb1), '');
INSERT INTO @h VALUES (2, 'box_id_asal tersimpan', @BoxACode,
    (SELECT b.box_code FROM tni.pembatalan pb JOIN tni.box b ON b.box_id=pb.box_id_asal
      WHERE pb.pembatalan_id=@Pb1), '');

/* ---------- 2. tanpa SETUJUI -> personel sudah keluar, isi box berkurang ---------- */
INSERT INTO @h VALUES (3, 'tidak ada pengajuan BOX MENUNGGU', '0',
    CAST((SELECT COUNT(*) FROM tni.pembatalan WHERE personel_id=@P1 AND jenis='BOX'
           AND [status]='MENUNGGU' AND deleted_at IS NULL) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (4, 'personel keluar dari box', 'SET_JADI',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id=@P1), '');
INSERT INTO @h VALUES (5, 'box_id/urut/boxed_at/boxed_by dikosongkan', '0 kolom terisi',
    CONCAT((SELECT (CASE WHEN box_id IS NULL THEN 0 ELSE 1 END)
                 + (CASE WHEN urut_dalam_box IS NULL THEN 0 ELSE 1 END)
                 + (CASE WHEN boxed_at IS NULL THEN 0 ELSE 1 END)
                 + (CASE WHEN boxed_by IS NULL THEN 0 ELSE 1 END)
            FROM tni.personel WHERE personel_id=@P1), ' kolom terisi'), '');
INSERT INTO @h VALUES (6, 'isi box berkurang 1', CAST(@IsiSebelum - 1 AS VARCHAR(10)),
    CAST((SELECT COUNT(*) FROM tni.personel WHERE box_id=@BoxA AND deleted_at IS NULL) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (7, 'diputus_oleh/at & catatan otomatis', 'Langsung -- keluar box tanpa persetujuan',
    (SELECT catatan_keputusan FROM tni.pembatalan WHERE pembatalan_id=@Pb1
       AND diputus_oleh IS NOT NULL AND diputus_at IS NOT NULL), '');

/* ---------- 3. bisa di-scan ulang ke box LAIN ---------- */
DELETE FROM @scan;
INSERT INTO @scan EXEC tni.SIS_Scan_MasukBox @Kode=@T1, @BoxId=@BoxA, @UserId=@U;
INSERT INTO @h VALUES (8, 'bisa di-scan masuk box lagi setelah dibatalkan', 'OK',
    (SELECT TOP 1 Hasil FROM @scan), (SELECT TOP 1 Pesan FROM @scan));
DELETE FROM @scan;

/* ---------- 4. batal BOX pada box TERTUTUP -> box TERBUKA lagi ---------- */
INSERT INTO @h VALUES (9, 'BoxB sebelum pembatalan', 'TERTUTUP',
    (SELECT CASE WHEN shipped_at IS NOT NULL THEN 'TERKIRIM'
                 WHEN packed_at IS NOT NULL THEN 'TERTUTUP' ELSE 'TERBUKA' END
       FROM tni.box WHERE box_id=@BoxB), @BoxBCode);

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@P4,
    @Jenis='BOX', @Alasan='Celana salah ukuran', @UserId=@U;
DECLARE @Pb4 INT = (SELECT TOP 1 PembatalanId FROM @r);

INSERT INTO @h VALUES (10, 'SP melaporkan BoxDibukaUlang', '1',
    CAST((SELECT TOP 1 BoxDibukaUlang FROM @r) AS VARCHAR(5)), '');
INSERT INTO @h VALUES (11, 'box tertutup jadi TERBUKA lagi', 'TERBUKA',
    (SELECT CASE WHEN shipped_at IS NOT NULL THEN 'TERKIRIM'
                 WHEN packed_at IS NOT NULL THEN 'TERTUTUP' ELSE 'TERBUKA' END
       FROM tni.box WHERE box_id=@BoxB), '');
INSERT INTO @h VALUES (12, 'keterangan box mencatat pembatalan', CONCAT('Dibuka ulang karena pembatalan #', @Pb4),
    (SELECT keterangan FROM tni.box WHERE box_id=@BoxB), '');
INSERT INTO @h VALUES (13, 'packed_by juga dikosongkan', 'NULL',
    (SELECT ISNULL(CAST(packed_by AS VARCHAR(10)), 'NULL') FROM tni.box WHERE box_id=@BoxB), '');
INSERT INTO @h VALUES (14, 'BoxB jadi kosong -> tutup ulang ditolak', '0',
    CAST((SELECT COUNT(*) FROM tni.personel WHERE box_id=@BoxB AND deleted_at IS NULL) AS VARCHAR(10)), '');

/* ---------- 5. batal SET -> status DICETAK + dua mutasi BONGKAR ---------- */
DECLARE @SaldoK INT = (SELECT ISNULL(SUM(qty),0) FROM tni.stok_mutasi
                        WHERE pola_kemeja_id=@K3 AND deleted_at IS NULL);
DECLARE @SaldoC INT = (SELECT ISNULL(SUM(qty),0) FROM tni.stok_mutasi
                        WHERE pola_celana_id=@C3 AND deleted_at IS NULL);
DECLARE @TerpakaiSebelum INT = (SELECT COUNT(*) FROM tni.stok_mutasi
                                 WHERE personel_id=@P3 AND jenis_mutasi='TERPAKAI' AND deleted_at IS NULL);

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@P3,
    @Jenis='SET', @Alasan='Kemeja kekecilan', @UserId=@U;
DECLARE @Pb3 INT = (SELECT TOP 1 PembatalanId FROM @r);

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Pembatalan_Manage @Action='SETUJUI', @Id=@Pb3, @UserId=@U;

INSERT INTO @h VALUES (15, 'SETUJUI SET -> status personel', 'DICETAK',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id=@P3), '');
INSERT INTO @h VALUES (16, 'set_at & set_by dikosongkan', '0 kolom terisi',
    CONCAT((SELECT (CASE WHEN set_at IS NULL THEN 0 ELSE 1 END)
                 + (CASE WHEN set_by IS NULL THEN 0 ELSE 1 END)
            FROM tni.personel WHERE personel_id=@P3), ' kolom terisi'), '');
INSERT INTO @h VALUES (17, 'saldo pola kemeja +1', CAST(@SaldoK + 1 AS VARCHAR(10)),
    CAST((SELECT ISNULL(SUM(qty),0) FROM tni.stok_mutasi
           WHERE pola_kemeja_id=@K3 AND deleted_at IS NULL) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (18, 'saldo pola celana +1', CAST(@SaldoC + 1 AS VARCHAR(10)),
    CAST((SELECT ISNULL(SUM(qty),0) FROM tni.stok_mutasi
           WHERE pola_celana_id=@C3 AND deleted_at IS NULL) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (19, 'dua mutasi BONGKAR +1 (kemeja & celana)', '2',
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi
           WHERE personel_id=@P3 AND jenis_mutasi='BONGKAR' AND qty=1 AND deleted_at IS NULL) AS VARCHAR(10)),
    (SELECT TOP 1 alasan FROM tni.stok_mutasi WHERE personel_id=@P3 AND jenis_mutasi='BONGKAR'));
INSERT INTO @h VALUES (20, 'mutasi TERPAKAI TIDAK dihapus', CAST(@TerpakaiSebelum AS VARCHAR(10)),
    CAST((SELECT COUNT(*) FROM tni.stok_mutasi
           WHERE personel_id=@P3 AND jenis_mutasi='TERPAKAI' AND deleted_at IS NULL) AS VARCHAR(10)), '');

/* ---------- 6. scan Set Jadi ulang berhasil ---------- */
DELETE FROM @set;
INSERT INTO @set EXEC tni.SIS_Scan_SetJadi @Kode=@T3, @UserId=@U;
INSERT INTO @h VALUES (21, 'scan Set Jadi ulang setelah batal SET', 'OK',
    (SELECT TOP 1 Hasil FROM @set), (SELECT TOP 1 Pesan FROM @set));
DELETE FROM @set;

/* ---------- 7. LIST & ByPersonel ---------- */
DECLARE @L TABLE (PembatalanId INT, PersonelId INT, Jenis VARCHAR(10), [Status] VARCHAR(20),
                  KodeRef VARCHAR(30), Pangkat VARCHAR(50), Nama VARCHAR(150),
                  SatuanCode VARCHAR(10), SatuanName VARCHAR(150), AreaCode VARCHAR(10),
                  StatusProgres VARCHAR(20), PolaKemejaKode VARCHAR(30), PolaCelanaKode VARCHAR(30),
                  BoxCodeAsal VARCHAR(30), BoxCodeSekarang VARCHAR(30), BoxAsalTertutup BIT,
                  Alasan VARCHAR(500), DiajukanAt DATETIME2, DiajukanOlehNama VARCHAR(150),
                  DiputusAt DATETIME2, DiputusOlehNama VARCHAR(150),
                  CatatanKeputusan VARCHAR(500), TotalCount INT);

INSERT INTO @L EXEC tni.SIS_Pembatalan_List @OrderId=@O, @Status='DISETUJUI';
INSERT INTO @h VALUES (22, 'LIST DISETUJUI memuat 3 pengajuan uji', '3',
    CAST((SELECT COUNT(*) FROM @L WHERE PembatalanId IN (@Pb1,@Pb3,@Pb4)) AS VARCHAR(10)), '');
INSERT INTO @h VALUES (23, 'LIST menyertakan pengaju & pemutus', 'ADA',
    (SELECT CASE WHEN COUNT(*) = 3 THEN 'ADA' ELSE 'KURANG' END FROM @L
      WHERE PembatalanId IN (@Pb1,@Pb3,@Pb4)
        AND DiajukanOlehNama IS NOT NULL AND DiputusOlehNama IS NOT NULL), '');
INSERT INTO @h VALUES (24, 'LIST menyertakan kode box asal', @BoxACode,
    (SELECT BoxCodeAsal FROM @L WHERE PembatalanId=@Pb1), '');

DELETE FROM @L;
INSERT INTO @L EXEC tni.SIS_Pembatalan_ByPersonel @PersonelId=@P3;
INSERT INTO @h VALUES (25, 'ByPersonel mengembalikan riwayat personel', '1',
    CAST((SELECT COUNT(*) FROM @L) AS VARCHAR(10)), '');

/* ---------- 8. pengajuan BOX lama yang masih MENUNGGU ikut ditutup ----------
   (data dari sebelum 2026-10-07; disisipkan langsung). P1 sudah di BoxA lagi (uji 8). */
INSERT INTO tni.pembatalan (personel_id, jenis, alasan, [status], box_id_asal, created_by)
VALUES (@P1, 'BOX', 'Pengajuan lama', 'MENUNGGU', @BoxA, @U);
DECLARE @PbLama INT = CAST(SCOPE_IDENTITY() AS INT);

DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@P1,
    @Jenis='BOX', @Alasan='Coba lagi', @UserId=@U;

INSERT INTO @h VALUES (26, 'pengajuan BOX lama MENUNGGU ikut DISETUJUI', 'DISETUJUI',
    (SELECT [status] FROM tni.pembatalan WHERE pembatalan_id=@PbLama),
    (SELECT catatan_keputusan FROM tni.pembatalan WHERE pembatalan_id=@PbLama));
INSERT INTO @h VALUES (27, 'batal BOX kedua kali -> keluar box lagi', 'SET_JADI',
    (SELECT status_progres FROM tni.v_personel WHERE personel_id=@P1), '');

ROLLBACK TRANSACTION;

/* ============================================================
   FASE B -- jalur penolakan (tanpa transaksi luar)
   Disiapkan manual, dibereskan manual di akhir fase.
   ============================================================ */
DECLARE @SatB INT = (SELECT TOP 1 s.satuan_id FROM tni.satuan s
                      JOIN tni.area_rawatan a ON a.area_id = s.area_id
                     WHERE a.order_id = @O AND s.satuan_code = 'DTJ' AND s.deleted_at IS NULL);

DECLARE @Q TABLE (rn INT, personel_id INT, qr_token VARCHAR(40));
INSERT INTO @Q
SELECT TOP 3 ROW_NUMBER() OVER (ORDER BY no_urut), personel_id, qr_token
FROM tni.personel
WHERE order_id = @O AND satuan_id = @SatB AND deleted_at IS NULL
  AND set_at IS NULL AND boxed_at IS NULL
ORDER BY no_urut;

DECLARE @Q1 INT = (SELECT personel_id FROM @Q WHERE rn=1),   -- belum apa-apa
        @Q2 INT = (SELECT personel_id FROM @Q WHERE rn=2),   -- set jadi + di box
        @Q3 INT = (SELECT personel_id FROM @Q WHERE rn=3);   -- set jadi, box terkirim

DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@SatB, @UserId=@U;
DECLARE @BoxC INT = (SELECT TOP 1 BoxId FROM @Buat);
DELETE FROM @Buat;
INSERT INTO @Buat EXEC tni.SIS_Box_Manage @Action='CREATE', @OrderId=@O, @SatuanId=@SatB, @UserId=@U;
DECLARE @BoxD INT = (SELECT TOP 1 BoxId FROM @Buat), @BoxDCode VARCHAR(30) = (SELECT TOP 1 BoxCode FROM @Buat);

-- Q2 -> set jadi + masuk BoxC (terbuka). Q3 -> set jadi + masuk BoxD, BoxD dikirim.
UPDATE tni.personel SET set_at = SYSDATETIME(), set_by = @U WHERE personel_id IN (@Q2, @Q3);
UPDATE tni.personel SET box_id = @BoxC, urut_dalam_box = 1, boxed_at = SYSDATETIME(), boxed_by = @U
WHERE personel_id = @Q2;
UPDATE tni.personel SET box_id = @BoxD, urut_dalam_box = 1, boxed_at = SYSDATETIME(), boxed_by = @U
WHERE personel_id = @Q3;
UPDATE tni.box SET packed_at = SYSDATETIME(), packed_by = @U, shipped_at = SYSDATETIME(), shipped_by = @U
WHERE box_id = @BoxD;

-- 28. AJUKAN SET untuk personel yang masih di box
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q2, @Jenis='SET', @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (28, 'AJUKAN SET saat masih di box', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (28, 'AJUKAN SET saat masih di box', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 29. AJUKAN BOX untuk box yang sudah TERKIRIM
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q3, @Jenis='BOX', @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (29, 'AJUKAN BOX saat box sudah terkirim', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (29, 'AJUKAN BOX saat box sudah terkirim', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 30. AJUKAN BOX untuk personel yang belum masuk box
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q1, @Jenis='BOX', @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (30, 'AJUKAN BOX saat belum masuk box', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (30, 'AJUKAN BOX saat belum masuk box', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 31. AJUKAN SET untuk personel yang belum set jadi
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q1, @Jenis='SET', @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (31, 'AJUKAN SET saat belum set jadi', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (31, 'AJUKAN SET saat belum set jadi', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 32. AJUKAN tanpa alasan
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q2, @Jenis='BOX', @Alasan='   ', @UserId=@U;
    INSERT INTO @h VALUES (32, 'AJUKAN tanpa alasan', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (32, 'AJUKAN tanpa alasan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 33. AJUKAN jenis ngawur
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q2, @Jenis='HAPUS', @Alasan='x', @UserId=@U;
    INSERT INTO @h VALUES (33, 'AJUKAN jenis tidak dikenal', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (33, 'AJUKAN jenis tidak dikenal', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- siapkan satu pengajuan sah untuk uji dobel & putusan. 2026-10-07: BOX tidak
-- pernah MENUNGGU lagi, jadi pakai jenis SET: Q1 dijadikan set jadi (tidak di box).
UPDATE tni.personel SET set_at = SYSDATETIME(), set_by = @U WHERE personel_id = @Q1;
DELETE FROM @r;
INSERT INTO @r EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q1,
    @Jenis='SET', @Alasan='Kemeja kekecilan', @UserId=@U;
DECLARE @PbB INT = (SELECT TOP 1 PembatalanId FROM @r);

-- 34. pengajuan DOBEL untuk personel & jenis yang sama
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='AJUKAN', @PersonelId=@Q1, @Jenis='SET', @Alasan='lagi', @UserId=@U;
    INSERT INTO @h VALUES (34, 'AJUKAN dobel (sudah ada MENUNGGU)', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (34, 'AJUKAN dobel (sudah ada MENUNGGU)', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 35. TOLAK tanpa catatan
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='TOLAK', @Id=@PbB, @Catatan=NULL, @UserId=@U;
    INSERT INTO @h VALUES (35, 'TOLAK tanpa catatan', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (35, 'TOLAK tanpa catatan', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

INSERT INTO @h VALUES (36, 'status tetap MENUNGGU setelah TOLAK gagal', 'MENUNGGU',
    (SELECT [status] FROM tni.pembatalan WHERE pembatalan_id=@PbB), '');

-- 37. SETUJUI saat kondisi sudah TIDAK VALID lagi (set jadi Q1 dibatalkan manual)
UPDATE tni.personel SET set_at = NULL, set_by = NULL WHERE personel_id = @Q1;

BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='SETUJUI', @Id=@PbB, @UserId=@U;
    INSERT INTO @h VALUES (37, 'SETUJUI saat personel sudah tidak set jadi', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (37, 'SETUJUI saat personel sudah tidak set jadi', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

INSERT INTO @h VALUES (38, 'pengajuan tetap MENUNGGU setelah SETUJUI gagal', 'MENUNGGU',
    (SELECT [status] FROM tni.pembatalan WHERE pembatalan_id=@PbB), '');

-- 39. putusan pada pengajuan yang sudah diputus
EXEC tni.SIS_Pembatalan_Manage @Action='TOLAK', @Id=@PbB, @Catatan='Tidak perlu', @UserId=@U;
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='SETUJUI', @Id=@PbB, @UserId=@U;
    INSERT INTO @h VALUES (39, 'SETUJUI pengajuan yang sudah diputus', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (39, 'SETUJUI pengajuan yang sudah diputus', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 40. id tidak ada
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='SETUJUI', @Id=-1, @UserId=@U;
    INSERT INTO @h VALUES (40, 'SETUJUI id tidak ada', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (40, 'SETUJUI id tidak ada', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

-- 41. action ngawur
BEGIN TRY
    EXEC tni.SIS_Pembatalan_Manage @Action='HAPUS', @Id=@PbB, @UserId=@U;
    INSERT INTO @h VALUES (41, 'Action tidak dikenal', 'DITOLAK', 'LOLOS', 'BUG');
END TRY
BEGIN CATCH
    INSERT INTO @h VALUES (41, 'Action tidak dikenal', 'DITOLAK', 'DITOLAK', ERROR_MESSAGE());
END CATCH

/* ---------- bereskan FASE B ---------- */
DELETE FROM tni.pembatalan WHERE personel_id IN (@Q1, @Q2, @Q3);
DELETE FROM tni.stok_mutasi WHERE personel_id IN (@Q1, @Q2, @Q3);
UPDATE tni.personel
SET set_at = NULL, set_by = NULL, box_id = NULL, urut_dalam_box = NULL,
    boxed_at = NULL, boxed_by = NULL, updated_at = NULL, updated_by = NULL
WHERE personel_id IN (@Q1, @Q2, @Q3);
DELETE FROM tni.box WHERE box_id IN (@BoxC, @BoxD);

/* ============================================================
   HASIL
   ============================================================ */
SELECT no_uji, uji, harapan, hasil,
       CASE WHEN harapan = hasil THEN 'SESUAI' ELSE '*** CEK ***' END AS kesimpulan,
       LEFT(pesan, 68) AS pesan
FROM @h ORDER BY no_uji;

SELECT CONCAT('Uji sesuai harapan: ', (SELECT COUNT(*) FROM @h WHERE harapan = hasil),
              ' dari ', (SELECT COUNT(*) FROM @h)) AS ringkasan;

-- bukti bersih: tidak ada sisa dari uji ini
SELECT (SELECT COUNT(*) FROM tni.pembatalan)                            AS sisa_pembatalan,
       (SELECT COUNT(*) FROM tni.box)                                   AS sisa_box,
       (SELECT COUNT(*) FROM tni.stok_mutasi)                           AS sisa_mutasi,
       (SELECT COUNT(*) FROM tni.personel WHERE set_at IS NOT NULL)     AS sisa_set,
       (SELECT COUNT(*) FROM tni.personel WHERE boxed_at IS NOT NULL)   AS sisa_boxed,
       (SELECT COUNT(*) FROM tni.personel)                              AS total_personel;
GO

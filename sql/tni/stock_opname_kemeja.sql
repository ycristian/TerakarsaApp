/* =============================================================
   PDH TNI AD -- STOCK OPNAME kemeja order aktif (2026-11-10).

   Isi @Opname dengan hasil hitung fisik. Selisih = fisik - saldo sistem
   (saldo = SUM(qty) tni.stok_mutasi, termasuk barang yang dijatah kartu
   tercetak -- barangnya masih ada di rak).

     selisih > 0 -> MASUK  : tni.SIS_Stok_Manage 'SETORAN' (supplier = @Supplier)
                    atau KOREKSI tambah kalau @PlusLewat = 'KOREKSI'
     selisih < 0 -> KELUAR : tni.SIS_Stok_Manage 'KELUAR' KOREKSI arah -1

   Masing-masing jadi satu header (riwayat Setoran / Keluarkan) dan bisa
   dihapus dari UI kalau salah.

   Pola kemeja yang saldonya <> 0 tapi TIDAK ada di @Opname:
     @NolkanTidakDisebut = 0 -> tidak disentuh (hanya ditampilkan)
     @NolkanTidakDisebut = 1 -> dianggap fisik 0 (ikut dikeluarkan)

   Cara pakai:
     1. Jalankan dengan @DryRun = 1 -> hanya preview.
     2. Cek angka, isi @UserId, ganti @DryRun = 0, jalankan lagi.
   ============================================================= */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

DECLARE @DryRun             BIT          = 1;            -- 1 preview | 0 eksekusi
DECLARE @UserId             INT          = NULL;         -- WAJIB: dbo.Users.Id pelaksana opname
DECLARE @Tanggal            DATE         = CAST(SYSDATETIME() AS DATE);
DECLARE @Alasan             VARCHAR(500) = 'Stock opname kemeja ' + CONVERT(VARCHAR(10), CAST(SYSDATETIME() AS DATE), 105);
DECLARE @Supplier           VARCHAR(150) = 'STOCK OPNAME';
DECLARE @PlusLewat          VARCHAR(10)  = 'SETORAN';    -- SETORAN | KOREKSI
DECLARE @NolkanTidakDisebut BIT          = 1;            -- opname 10-11-2026: yang tidak dihitung = tidak ada
DECLARE @TargetTotal        INT          = 355;          -- total kemeja hasil SO; beda -> batal

-- ---------- HASIL HITUNG FISIK ----------
DECLARE @Opname TABLE (size VARCHAR(30) PRIMARY KEY, fisik INT NOT NULL);
INSERT INTO @Opname (size, fisik) VALUES
 ('LD 94 P',   0),   -- dicek: fisik tidak ada
 ('LD 96 P',  82),
 ('LD 98 P',  55),
 ('LD 100 P', 22),
 ('LD 102 P',  8),
 ('LD 104 P', 24),
 ('LD 106 P',  9),
 ('LD 108 P', 37),
 ('LD 110 P', 16),
 ('LD 112 P', 65),
 ('LD 114 P',  3),
 ('LD 116 P',  1),
 ('LD 120 P',  5),
 ('LD 124 P', 28);

DECLARE @OrderId INT = (SELECT TOP 1 order_id FROM tni.orders
                         WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

IF @OrderId IS NULL
BEGIN
    RAISERROR('Tidak ada order aktif.', 16, 1);
    RETURN;
END

IF (SELECT SUM(fisik) FROM @Opname) <> @TargetTotal
BEGIN
    RAISERROR('Jumlah daftar opname tidak sama dengan @TargetTotal -- cek input.', 16, 1);
    RETURN;
END

-- 'LD 96 P' -> kode 'LD_96_P'
DECLARE @Hitung TABLE (kode VARCHAR(30) PRIMARY KEY, fisik INT NOT NULL);
INSERT INTO @Hitung (kode, fisik)
SELECT REPLACE(LTRIM(RTRIM(size)), ' ', '_'), fisik FROM @Opname;

IF EXISTS (SELECT 1 FROM @Hitung h
           WHERE NOT EXISTS (SELECT 1 FROM tni.v_stok_pola s
                              WHERE s.order_id = @OrderId AND s.jenis_item = 'KEMEJA'
                                AND s.kode = h.kode))
BEGIN
    SELECT h.kode AS kode_tidak_dikenal FROM @Hitung h
    WHERE NOT EXISTS (SELECT 1 FROM tni.v_stok_pola s
                       WHERE s.order_id = @OrderId AND s.jenis_item = 'KEMEJA'
                         AND s.kode = h.kode);
    RAISERROR('Ada size yang tidak ditemukan di pola kemeja -- cek ejaan.', 16, 1);
    RETURN;
END

-- ---------- SELISIH ----------
DECLARE @Selisih TABLE (
    pola_id INT PRIMARY KEY, kode VARCHAR(30), is_active BIT,
    saldo INT, dijatah INT, fisik INT, disebut BIT, selisih INT,
    urut_gender INT, urut_varian INT, urut_size INT);

INSERT INTO @Selisih
SELECT s.pola_id, s.kode, s.is_active, s.saldo, s.dijatah,
       COALESCE(h.fisik, 0),
       CASE WHEN h.kode IS NULL THEN 0 ELSE 1 END,
       COALESCE(h.fisik, 0) - s.saldo,
       s.urut_gender, s.urut_varian, s.urut_size
FROM tni.v_stok_pola s
LEFT JOIN @Hitung h ON h.kode = s.kode
WHERE s.order_id = @OrderId
  AND s.jenis_item = 'KEMEJA'
  AND (h.kode IS NOT NULL OR s.saldo <> 0);

-- ---------- PREVIEW ----------
SELECT x.kode,
       x.saldo                                   AS saldo_sistem,
       CASE WHEN x.disebut = 1 THEN x.fisik END  AS fisik,
       CASE WHEN x.disebut = 1 OR @NolkanTidakDisebut = 1 THEN x.selisih END AS selisih,
       CASE WHEN x.disebut = 0 AND @NolkanTidakDisebut = 0 THEN 'TIDAK DISEBUT -- tidak disentuh'
            WHEN x.disebut = 0                             THEN 'TIDAK DISEBUT -- dinolkan'
            WHEN x.selisih > 0 THEN 'MASUK +' + CAST(x.selisih AS VARCHAR(10))
            WHEN x.selisih < 0 THEN 'KELUAR ' + CAST(x.selisih AS VARCHAR(10))
            ELSE 'cocok' END
     + CASE WHEN x.is_active = 0 AND x.selisih <> 0 THEN ' (POLA NONAKTIF: ditolak SP)' ELSE '' END
     + CASE WHEN x.dijatah > 0 THEN ' | dijatah kartu: ' + CAST(x.dijatah AS VARCHAR(10)) ELSE '' END
                                                 AS aksi
FROM @Selisih x
ORDER BY x.urut_gender, x.urut_varian, x.urut_size, x.kode;

DELETE FROM @Selisih WHERE disebut = 0 AND @NolkanTidakDisebut = 0;

DECLARE @TotalSekarang INT = (SELECT ISNULL(SUM(s.saldo), 0) FROM tni.v_stok_pola s
                               WHERE s.order_id = @OrderId AND s.jenis_item = 'KEMEJA');

SELECT @TotalSekarang                                     AS total_kemeja_sekarang,
       SUM(CASE WHEN selisih > 0 THEN selisih ELSE 0 END) AS total_masuk,
       SUM(CASE WHEN selisih < 0 THEN selisih ELSE 0 END) AS total_keluar,
       @TotalSekarang + SUM(selisih)                      AS total_kemeja_setelah,
       @TargetTotal                                       AS target
FROM @Selisih;

IF @DryRun = 1
BEGIN
    PRINT 'DRY RUN -- tidak ada yang disimpan. Set @DryRun = 0 dan @UserId untuk eksekusi.';
    RETURN;
END

IF @UserId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId)
BEGIN
    RAISERROR('@UserId wajib diisi dengan user yang valid.', 16, 1);
    RETURN;
END

IF @PlusLewat NOT IN ('SETORAN','KOREKSI')
BEGIN
    RAISERROR('@PlusLewat harus SETORAN atau KOREKSI.', 16, 1);
    RETURN;
END

-- ---------- EKSEKUSI ----------
DECLARE @ItemsMasuk NVARCHAR(MAX) = (
    SELECT 'KEMEJA' AS jenisItem, pola_id AS polaId, selisih AS qty
    FROM @Selisih WHERE selisih > 0
    FOR JSON PATH);

DECLARE @ItemsKeluar NVARCHAR(MAX) = (
    SELECT 'KEMEJA' AS jenisItem, pola_id AS polaId, -selisih AS qty
    FROM @Selisih WHERE selisih < 0
    FOR JSON PATH);

BEGIN TRY
    BEGIN TRANSACTION;

    IF @ItemsMasuk IS NOT NULL AND @PlusLewat = 'SETORAN'
        EXEC tni.SIS_Stok_Manage
             @Action   = 'SETORAN',
             @OrderId  = @OrderId,
             @Tanggal  = @Tanggal,
             @Items    = @ItemsMasuk,
             @Supplier = @Supplier,
             @UserId   = @UserId;

    IF @ItemsMasuk IS NOT NULL AND @PlusLewat = 'KOREKSI'
        EXEC tni.SIS_Stok_Manage
             @Action      = 'KELUAR',
             @OrderId     = @OrderId,
             @Tanggal     = @Tanggal,
             @Items       = @ItemsMasuk,
             @JenisMutasi = 'KOREKSI',
             @Arah        = 1,
             @Alasan      = @Alasan,
             @UserId      = @UserId;

    IF @ItemsKeluar IS NOT NULL
        EXEC tni.SIS_Stok_Manage
             @Action      = 'KELUAR',
             @OrderId     = @OrderId,
             @Tanggal     = @Tanggal,
             @Items       = @ItemsKeluar,
             @JenisMutasi = 'KOREKSI',
             @Arah        = -1,
             @Alasan      = @Alasan,
             @UserId      = @UserId;

    -- total SEMUA kemeja order aktif harus persis @TargetTotal, kalau tidak batal
    DECLARE @TotalSetelah INT = (SELECT ISNULL(SUM(s.saldo), 0) FROM tni.v_stok_pola s
                                  WHERE s.order_id = @OrderId AND s.jenis_item = 'KEMEJA');
    IF @TotalSetelah <> @TargetTotal
        RAISERROR('Total kemeja setelah opname %d, bukan %d -- dibatalkan.', 16, 1, @TotalSetelah, @TargetTotal);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH

-- ---------- CEK SETELAH ----------
-- saldo harus = fisik untuk semua pola yang dihitung.
SELECT s.kode, s.saldo, x.fisik,
       CASE WHEN s.saldo = x.fisik THEN 'OK' ELSE 'BEDA' END AS cek
FROM tni.v_stok_pola s
JOIN @Selisih x ON x.pola_id = s.pola_id
WHERE s.order_id = @OrderId AND s.jenis_item = 'KEMEJA'
ORDER BY x.urut_gender, x.urut_varian, x.urut_size, x.kode;

/* =============================================================
   PDH TNI AD -- FLUSH stok KEMEJA order aktif (2026-11-10).

   Mengeluarkan seluruh STOK BEBAS kemeja = saldo - dijatah
   (tni.v_stok_pola.stok_bebas). Barang yang "dikunci" kartu yang sudah
   DICETAK tapi belum Set Jadi TIDAK ikut dikeluarkan -- sisa saldo per pola
   setelah flush = jumlah kartu DICETAK pola itu.

   Lewat tni.SIS_Stok_Manage @Action='KELUAR' (KOREKSI, arah -1): satu header
   tni.stok_keluar, tampil di riwayat Keluarkan, bisa dihapus dari UI kalau
   salah (KELUAR_HAPUS).

   Pola yang NONAKTIF ditolak SP -> tidak ikut flush, ditampilkan terpisah.

   Cara pakai:
     1. Jalankan dengan @DryRun = 1 -> hanya preview.
     2. Cek angka, isi @UserId, ganti @DryRun = 0, jalankan lagi.
   ============================================================= */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

DECLARE @DryRun  BIT          = 1;                       -- 1 preview | 0 eksekusi
DECLARE @UserId  INT          = NULL;                    -- WAJIB: dbo.Users.Id pelaksana flush
DECLARE @Tanggal DATE         = CAST(SYSDATETIME() AS DATE);
DECLARE @Alasan  VARCHAR(500) = 'Flush stok kemeja (kecuali yang sudah dijatah kartu tercetak)';

DECLARE @OrderId INT = (SELECT TOP 1 order_id FROM tni.orders
                         WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

IF @OrderId IS NULL
BEGIN
    RAISERROR('Tidak ada order aktif.', 16, 1);
    RETURN;
END

-- ---------- PREVIEW ----------
SELECT s.kode,
       s.is_active,
       s.saldo,
       s.dijatah,
       s.stok_bebas                          AS akan_dikeluarkan,
       s.saldo - s.stok_bebas                AS saldo_setelah_flush,
       CASE WHEN s.is_active = 0 THEN 'DILEWATI: pola nonaktif' END AS catatan
FROM tni.v_stok_pola s
WHERE s.order_id = @OrderId
  AND s.jenis_item = 'KEMEJA'
  AND s.stok_bebas > 0
ORDER BY s.urut_gender, s.urut_varian, s.urut_size, s.kode;

SELECT SUM(CASE WHEN s.is_active = 1 THEN s.stok_bebas ELSE 0 END) AS total_dikeluarkan,
       SUM(CASE WHEN s.is_active = 0 THEN s.stok_bebas ELSE 0 END) AS total_dilewati_nonaktif,
       SUM(s.dijatah)                                              AS total_tetap_dijatah
FROM tni.v_stok_pola s
WHERE s.order_id = @OrderId
  AND s.jenis_item = 'KEMEJA';

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

-- ---------- EKSEKUSI ----------
DECLARE @Items NVARCHAR(MAX) = (
    SELECT 'KEMEJA'      AS jenisItem,
           s.pola_id     AS polaId,
           s.stok_bebas  AS qty
    FROM tni.v_stok_pola s
    WHERE s.order_id = @OrderId
      AND s.jenis_item = 'KEMEJA'
      AND s.is_active = 1
      AND s.stok_bebas > 0
    FOR JSON PATH);

IF @Items IS NULL
BEGIN
    PRINT 'Tidak ada stok bebas kemeja -- tidak ada yang dikeluarkan.';
    RETURN;
END

EXEC tni.SIS_Stok_Manage
     @Action      = 'KELUAR',
     @OrderId     = @OrderId,
     @Tanggal     = @Tanggal,
     @Items       = @Items,
     @JenisMutasi = 'KOREKSI',
     @Arah        = -1,
     @Alasan      = @Alasan,
     @UserId      = @UserId;

-- ---------- CEK SETELAH ----------
-- stok_bebas pola aktif harus 0 (saldo = dijatah).
SELECT s.kode, s.saldo, s.dijatah, s.stok_bebas
FROM tni.v_stok_pola s
WHERE s.order_id = @OrderId
  AND s.jenis_item = 'KEMEJA'
  AND (s.saldo <> 0 OR s.dijatah <> 0)
ORDER BY s.urut_gender, s.urut_varian, s.urut_size, s.kode;

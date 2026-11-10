/* =====================================================================
   fix_79 -- Nomori ulang kode_ref / no_urut personel per satuan
             berdasarkan ABJAD NAMA (sebelumnya urut submitted_at form).

   - Berlaku untuk semua satuan di semua order, hanya baris deleted_at IS NULL.
   - Urutan: nama (collation DB, case-insensitive), seri submitted_at, personel_id.
   - qr_token TIDAK berubah -> QR di kartu yang sudah dicetak tetap valid;
     hanya teks kode di kartu yang jadi usang (cetak ulang).
   - Ditolak bila sudah ada personel yang scan Set Jadi / masuk box di satuan
     yang nomornya akan berubah (kode sudah dipakai fisik di box/daftar).
   - Backup kode lama di tni.bak_79_personel_kode (sekali saja, saat run pertama).
     Kembalikan: lihat blok ROLLBACK di bawah.
   - Aman dijalankan ulang: satuan yang sudah urut abjad tidak berubah.
   ===================================================================== */
-- Wajib ON: tni.personel punya filtered index (sqlcmd default-nya OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ---------- backup kode lama (run pertama saja) ----------
IF OBJECT_ID('tni.bak_79_personel_kode', 'U') IS NULL
BEGIN
    SELECT personel_id,
           kode_ref AS kode_ref_lama,
           no_urut  AS no_urut_lama,
           SYSDATETIME() AS backup_at
    INTO tni.bak_79_personel_kode
    FROM tni.personel;
    PRINT 'Backup kode lama -> tni.bak_79_personel_kode';
END
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('tempdb..#baru') IS NOT NULL DROP TABLE #baru;

SELECT p.personel_id,
       p.order_id,
       p.satuan_id,
       p.kode_ref AS kode_lama,
       p.no_urut  AS urut_lama,
       ROW_NUMBER() OVER (PARTITION BY p.order_id, p.satuan_id
                          ORDER BY p.nama, p.submitted_at, p.personel_id) AS urut_baru,
       s.satuan_code,
       p.print_count,
       p.set_at,
       p.boxed_at
INTO #baru
FROM tni.personel p
JOIN tni.satuan s ON s.satuan_id = p.satuan_id
WHERE p.deleted_at IS NULL;

ALTER TABLE #baru ADD kode_baru VARCHAR(30) COLLATE DATABASE_DEFAULT;

UPDATE #baru
SET kode_baru = CONCAT(satuan_code, '-',
                       CASE WHEN urut_baru > 999
                            THEN CAST(urut_baru AS VARCHAR(10))
                            ELSE RIGHT(CONCAT('000', urut_baru), 3) END);

-- ---------- guard: satuan yang berubah tidak boleh sudah Set Jadi / di box ----------
IF EXISTS (
    SELECT 1
    FROM #baru b
    WHERE (b.set_at IS NOT NULL OR b.boxed_at IS NOT NULL)
      AND EXISTS (SELECT 1 FROM #baru x
                  WHERE x.order_id = b.order_id AND x.satuan_id = b.satuan_id
                    AND x.kode_baru <> x.kode_lama))
BEGIN
    SELECT DISTINCT b.satuan_code, COUNT(*) OVER (PARTITION BY b.satuan_id) AS sudah_set_atau_box
    FROM #baru b
    WHERE b.set_at IS NOT NULL OR b.boxed_at IS NOT NULL;
    RAISERROR('DITOLAK|Ada personel yang sudah Set Jadi / masuk box di satuan yang nomornya berubah -- penomoran ulang dibatalkan.', 16, 1);
    RETURN;
END

-- ---------- kartu sudah dicetak yang kodenya berubah (perlu cetak ulang) ----------
SELECT b.satuan_code, b.kode_lama, b.kode_baru, p.nama, b.print_count
FROM #baru b
JOIN tni.personel p ON p.personel_id = b.personel_id
WHERE b.print_count > 0 AND b.kode_baru <> b.kode_lama
ORDER BY b.satuan_code, b.kode_baru;

-- ---------- terapkan (satu statement -> unique index dicek di akhir statement) ----------
BEGIN TRANSACTION;

UPDATE p
SET kode_ref   = b.kode_baru,
    no_urut    = b.urut_baru,
    updated_at = SYSDATETIME()
FROM tni.personel p
JOIN #baru b ON b.personel_id = p.personel_id
WHERE p.kode_ref <> b.kode_baru OR p.no_urut <> b.urut_baru;

PRINT CONCAT('Personel dinomori ulang: ', @@ROWCOUNT);

COMMIT TRANSACTION;

-- ringkasan
SELECT b.satuan_code,
       COUNT(*) AS jml,
       SUM(CASE WHEN b.kode_baru <> b.kode_lama THEN 1 ELSE 0 END) AS berubah
FROM #baru b
GROUP BY b.satuan_code
ORDER BY b.satuan_code;

DROP TABLE #baru;
GO

/* ---------- ROLLBACK (jalankan manual bila perlu kembali ke kode lama) ----------
UPDATE p
SET kode_ref = k.kode_ref_lama, no_urut = k.no_urut_lama, updated_at = SYSDATETIME()
FROM tni.personel p
JOIN tni.bak_79_personel_kode k ON k.personel_id = p.personel_id;
-- Personel yang di-import SETELAH fix_79 tidak ada di backup dan tidak ikut dikembalikan;
-- pastikan nomornya tidak bentrok dengan kode lama sebelum menjalankan ini.
------------------------------------------------------------------------------- */

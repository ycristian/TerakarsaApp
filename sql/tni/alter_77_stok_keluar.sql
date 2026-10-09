/* =============================================================
   PDH TNI AD -- header PENGELUARAN stok (2026-10-07).

   Permintaan owner: UI/UX Keluarkan disamakan PERSIS dengan Setoran
   (alter_76) -- input banyak baris sekaligus, riwayat satu kartu per
   pengeluaran dengan tabel size, edit master + isi lewat pop up, hapus satu
   pengeluaran sekaligus.

   tni.stok_keluar = header. Master: tanggal, jenis (RUSAK | KOREKSI),
   arah (-1 kurangi | 1 tambah; RUSAK selalu -1), alasan (wajib).
   BEDA dengan setoran: TIDAK ada kunci unik / penggabungan -- tiap simpan
   adalah satu pengeluaran (alasan teks bebas, tidak cocok jadi kunci).
   tni.stok_mutasi.keluar_id menunjuk header; tanggal & alasan baris mutasi
   tetap diisi dan disinkronkan tni.SIS_Stok_Manage; tanda qty = arah header.

   Backfill: mutasi RUSAK/KOREKSI lama dikelompokkan per (order, tanggal,
   jenis, alasan, tanda qty) jadi header.

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('tni.stok_keluar','U') IS NULL
CREATE TABLE tni.stok_keluar(
 keluar_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_stok_keluar_orders foreign key references tni.orders(order_id),
 tanggal date not null,
 jenis_mutasi varchar(20) not null
   constraint CK_tni_stok_keluar_jenis check (jenis_mutasi in ('RUSAK','KOREKSI')),
 arah int not null
   constraint CK_tni_stok_keluar_arah check (arah in (-1, 1)),
 alasan varchar(500) not null,
 perangkat_id int null
   constraint FK_tni_stok_keluar_perangkat foreign key references tni.perangkat(perangkat_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 -- RUSAK selalu pengurangan
 constraint CK_tni_stok_keluar_rusak_kurang check (jenis_mutasi <> 'RUSAK' OR arah = -1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_keluar_order' AND object_id = OBJECT_ID('tni.stok_keluar'))
    CREATE INDEX IX_tni_stok_keluar_order ON tni.stok_keluar(order_id, tanggal) WHERE deleted_at IS NULL;
GO

IF COL_LENGTH('tni.stok_mutasi','keluar_id') IS NULL
    ALTER TABLE tni.stok_mutasi ADD keluar_id int null
        constraint FK_tni_stok_mutasi_keluar foreign key references tni.stok_keluar(keluar_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_mutasi_keluar' AND object_id = OBJECT_ID('tni.stok_mutasi'))
    CREATE INDEX IX_tni_stok_mutasi_keluar ON tni.stok_mutasi(keluar_id) WHERE deleted_at IS NULL;
GO

-- ---------- backfill mutasi RUSAK / KOREKSI lama ----------
SELECT sm.order_id, sm.tanggal, sm.jenis_mutasi,
       ISNULL(NULLIF(LTRIM(RTRIM(sm.alasan)), ''), '-') AS alasan,
       CAST(SIGN(sm.qty) AS INT) AS arah,
       MIN(sm.perangkat_id) AS perangkat_id,
       MIN(sm.created_at)   AS created_at,
       MIN(sm.created_by)   AS created_by
INTO #g
FROM tni.stok_mutasi sm
WHERE sm.jenis_mutasi IN ('RUSAK','KOREKSI')
  AND sm.deleted_at IS NULL
  AND sm.keluar_id IS NULL
GROUP BY sm.order_id, sm.tanggal, sm.jenis_mutasi,
         ISNULL(NULLIF(LTRIM(RTRIM(sm.alasan)), ''), '-'), SIGN(sm.qty);

DECLARE @map TABLE (keluar_id INT, order_id INT, tanggal DATE, jenis_mutasi VARCHAR(20),
                    alasan VARCHAR(500), arah INT);

MERGE tni.stok_keluar AS t
USING #g AS s ON 1 = 0
WHEN NOT MATCHED THEN
    INSERT (order_id, tanggal, jenis_mutasi, arah, alasan, perangkat_id, created_at, created_by)
    VALUES (s.order_id, s.tanggal, s.jenis_mutasi, s.arah, s.alasan, s.perangkat_id, s.created_at, s.created_by)
OUTPUT inserted.keluar_id, s.order_id, s.tanggal, s.jenis_mutasi, s.alasan, s.arah INTO @map;

UPDATE sm
SET keluar_id = m.keluar_id
FROM tni.stok_mutasi sm
JOIN @map m
  ON m.order_id = sm.order_id
 AND m.tanggal = sm.tanggal
 AND m.jenis_mutasi = sm.jenis_mutasi
 AND m.alasan = ISNULL(NULLIF(LTRIM(RTRIM(sm.alasan)), ''), '-')
 AND m.arah = SIGN(sm.qty)
WHERE sm.jenis_mutasi IN ('RUSAK','KOREKSI')
  AND sm.deleted_at IS NULL
  AND sm.keluar_id IS NULL;

DROP TABLE #g;
GO

SELECT (SELECT COUNT(*) FROM tni.stok_keluar WHERE deleted_at IS NULL) AS header_keluar,
       (SELECT COUNT(*) FROM tni.stok_mutasi
         WHERE jenis_mutasi IN ('RUSAK','KOREKSI') AND deleted_at IS NULL AND keluar_id IS NULL) AS keluar_tanpa_header;
GO

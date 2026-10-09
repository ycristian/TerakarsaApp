/* =============================================================
   PDH TNI AD -- header SETORAN stok (2026-10-07).

   Permintaan owner: riwayat setoran tampil PER TANGGAL & SUPPLIER (satu kartu,
   tabel kecil isi size di bawahnya), master (tanggal/supplier) dan isinya bisa
   diedit lewat pop up, dan satu setoran bisa dihapus sekaligus.

   tni.stok_setoran = header. Kunci unik (order_id, tanggal, supplier) --
   setoran kedua dengan tanggal & supplier yang sama DIGABUNG ke header yang
   sudah ada (supplier NULL dihitung sama dengan NULL oleh unique index).
   tni.stok_mutasi.setoran_id menunjuk header; tanggal & supplier di baris
   mutasi tetap diisi dan selalu disinkronkan oleh tni.SIS_Stok_Manage
   (dibaca SIS_Stok_Riwayat per pola).

   Backfill: semua mutasi MASUK lama dikelompokkan per (order, tanggal,
   supplier) jadi header.

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('tni.stok_setoran','U') IS NULL
CREATE TABLE tni.stok_setoran(
 setoran_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_stok_setoran_orders foreign key references tni.orders(order_id),
 tanggal date not null,
 supplier varchar(150) null,               -- teks bebas, opsional
 perangkat_id int null                     -- perangkat pembuat (nama petugas)
   constraint FK_tni_stok_setoran_perangkat foreign key references tni.perangkat(perangkat_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_stok_setoran_kunci' AND object_id = OBJECT_ID('tni.stok_setoran'))
    CREATE UNIQUE INDEX UX_tni_stok_setoran_kunci
        ON tni.stok_setoran(order_id, tanggal, supplier) WHERE deleted_at IS NULL;
GO

IF COL_LENGTH('tni.stok_mutasi','setoran_id') IS NULL
    ALTER TABLE tni.stok_mutasi ADD setoran_id int null
        constraint FK_tni_stok_mutasi_setoran foreign key references tni.stok_setoran(setoran_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_mutasi_setoran' AND object_id = OBJECT_ID('tni.stok_mutasi'))
    CREATE INDEX IX_tni_stok_mutasi_setoran ON tni.stok_mutasi(setoran_id) WHERE deleted_at IS NULL;
GO

-- ---------- backfill mutasi MASUK lama ----------
INSERT INTO tni.stok_setoran (order_id, tanggal, supplier, perangkat_id, created_at, created_by)
SELECT sm.order_id, sm.tanggal, sm.supplier,
       MIN(sm.perangkat_id), MIN(sm.created_at), MIN(sm.created_by)
FROM tni.stok_mutasi sm
WHERE sm.jenis_mutasi = 'MASUK'
  AND sm.deleted_at IS NULL
  AND sm.setoran_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM tni.stok_setoran s
                  WHERE s.order_id = sm.order_id
                    AND s.tanggal = sm.tanggal
                    AND (s.supplier = sm.supplier OR (s.supplier IS NULL AND sm.supplier IS NULL))
                    AND s.deleted_at IS NULL)
GROUP BY sm.order_id, sm.tanggal, sm.supplier;

UPDATE sm
SET setoran_id = s.setoran_id
FROM tni.stok_mutasi sm
JOIN tni.stok_setoran s
  ON s.order_id = sm.order_id
 AND s.tanggal = sm.tanggal
 AND (s.supplier = sm.supplier OR (s.supplier IS NULL AND sm.supplier IS NULL))
 AND s.deleted_at IS NULL
WHERE sm.jenis_mutasi = 'MASUK'
  AND sm.deleted_at IS NULL
  AND sm.setoran_id IS NULL;
GO

SELECT (SELECT COUNT(*) FROM tni.stok_setoran WHERE deleted_at IS NULL) AS header_setoran,
       (SELECT COUNT(*) FROM tni.stok_mutasi
         WHERE jenis_mutasi = 'MASUK' AND deleted_at IS NULL AND setoran_id IS NULL) AS masuk_tanpa_header;
GO

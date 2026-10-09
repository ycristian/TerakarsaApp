/* =============================================================
   PDH TNI AD -- assignment PETUGAS ke PERANGKAT (2026-10-03).

   Permintaan owner: struktur perangkat + petugas per sesi TETAP, tapi
   tiap petugas di-assign ke SATU perangkat. Pemilih petugas di perangkat
   hanya menampilkan petugas milik perangkat itu, dan API menolak header
   X-Tni-Petugas yang bukan milik perangkat pemegang token.

     tni.petugas.perangkat_id  -- NULL = belum di-assign (tidak muncul di
                                  perangkat mana pun).

   Satu petugas -> satu perangkat; satu perangkat -> banyak petugas.

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('tni.petugas','perangkat_id') IS NULL
    ALTER TABLE tni.petugas ADD perangkat_id int null
        constraint FK_tni_petugas_perangkat foreign key references tni.perangkat(perangkat_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_petugas_perangkat' AND object_id = OBJECT_ID('tni.petugas'))
    CREATE INDEX IX_tni_petugas_perangkat ON tni.petugas(perangkat_id) WHERE deleted_at IS NULL;
GO

PRINT 'tni.petugas.perangkat_id siap.';
GO

/* =============================================================
   PDH TNI AD -- supplier pada setoran stok (2026-10-06).

   Permintaan owner: setoran stok mencatat SUPPLIER (teks bebas, opsional).
   Disimpan di setiap baris mutasi MASUK dari setoran itu.

   Sekaligus (lihat sp_Stok.sql): mutasi manual (MASUK / RUSAK / KOREKSI)
   kini BOLEH dihapus (soft delete) dari tab Riwayat -- menggantikan aturan
   Prompt 64 "tidak ada DELETE, betulkan dengan KOREKSI".

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('tni.stok_mutasi','supplier') IS NULL
    ALTER TABLE tni.stok_mutasi ADD supplier varchar(150) null;
GO

PRINT 'tni.stok_mutasi.supplier siap.';
GO

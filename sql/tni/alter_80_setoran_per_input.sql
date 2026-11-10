-- alter_80 (2026-11-09): setoran TIDAK lagi digabung per (order, tanggal, supplier).
--
-- Permintaan owner: Riwayat stok per INPUT, bukan rekap per hari. Setiap simpan
-- setoran = satu header tni.stok_setoran sendiri (jam input = created_at), walau
-- tanggal & supplier-nya sama dengan setoran lain.
--
-- 1. Unique index UX_tni_stok_setoran_kunci dibongkar, diganti index biasa
--    IX_tni_stok_setoran_tanggal (order_id, tanggal) untuk daftar Riwayat.
-- 2. Jalankan ulang sql/tni/sp_Stok.sql SETELAH script ini (SETORAN tidak
--    menggabung lagi; SETORAN_EDIT tidak menolak tanggal/supplier kembar).
--
-- Setoran lama yang sudah terlanjur digabung TIDAK dipecah: qty-nya sudah
-- dijumlahkan ke baris yang sama, rincian per input tidak tersimpan.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_stok_setoran_kunci' AND object_id = OBJECT_ID('tni.stok_setoran'))
    DROP INDEX UX_tni_stok_setoran_kunci ON tni.stok_setoran;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_setoran_tanggal' AND object_id = OBJECT_ID('tni.stok_setoran'))
    CREATE INDEX IX_tni_stok_setoran_tanggal
        ON tni.stok_setoran(order_id, tanggal) WHERE deleted_at IS NULL;
GO

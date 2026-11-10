/* =============================================================
   PDH TNI AD -- tanda PRIORITAS (bintang) per satuan (2026-11-09).

   Permintaan owner: di Perintah Kerja (daftar satuan) ada bintang untuk
   menaikkan satuan ke atas sebagai prioritas. Disimpan di DB supaya semua
   perangkat melihat urutan yang sama.

   prioritas_at terisi = berbintang. prioritas_by = user (tni_system untuk
   perangkat), prioritas_perangkat_id = perangkat yang memberi bintang.
   Dilepas = ketiganya NULL lagi. Diubah HANYA lewat tni.SIS_Satuan_Manage
   (sql/tni/sp_Satuan.sql).

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('tni.satuan','prioritas_at') IS NULL
    ALTER TABLE tni.satuan ADD prioritas_at datetime2 null;
GO
IF COL_LENGTH('tni.satuan','prioritas_by') IS NULL
    ALTER TABLE tni.satuan ADD prioritas_by int null;
GO
IF COL_LENGTH('tni.satuan','prioritas_perangkat_id') IS NULL
    ALTER TABLE tni.satuan ADD prioritas_perangkat_id int null
        constraint FK_tni_satuan_prioritas_perangkat foreign key references tni.perangkat(perangkat_id);
GO

PRINT 'tni.satuan.prioritas_* siap.';
GO

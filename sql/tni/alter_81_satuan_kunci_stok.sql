/* =============================================================
   PDH TNI AD -- KUNCI STOK per satuan (2026-11-11).

   Permintaan owner: satuan yang mau ditutup (mis. Bogor) bisa diberi tanda
   kunci (gembok) di Perintah Kerja. Selama terkunci, stok bebas (belum dicetak)
   DISISIHKAN untuk kebutuhan personel BELUM_CETAK satuan itu, per pola --
   jadi kemeja yang celana pasangannya belum ada tetap ditahan untuk satuan itu
   dan tidak terpakai satuan lain. Beda dengan bintang prioritas (urutan saja).

   kunci_stok_at terisi = terkunci. Satuan yang dikunci DULUAN dapat stok duluan
   bila beberapa satuan butuh pola yang sama (lihat tni.v_stok_kunci, v_stok.sql).
   Diubah HANYA lewat tni.SIS_Satuan_Manage @Action = 'KUNCI_STOK'.

   Kunci hanya berlaku di saran Perintah Kerja + tampilan stok -- cetak & scan
   TIDAK diblok.

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   Jalankan SEBELUM v_stok.sql (view tni.v_stok_kunci memakai kolom ini).
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('tni.satuan','kunci_stok_at') IS NULL
    ALTER TABLE tni.satuan ADD kunci_stok_at datetime2 null;
GO
IF COL_LENGTH('tni.satuan','kunci_stok_by') IS NULL
    ALTER TABLE tni.satuan ADD kunci_stok_by int null;
GO
IF COL_LENGTH('tni.satuan','kunci_stok_perangkat_id') IS NULL
    ALTER TABLE tni.satuan ADD kunci_stok_perangkat_id int null
        constraint FK_tni_satuan_kunci_stok_perangkat foreign key references tni.perangkat(perangkat_id);
GO

PRINT 'tni.satuan.kunci_stok_* siap.';
GO

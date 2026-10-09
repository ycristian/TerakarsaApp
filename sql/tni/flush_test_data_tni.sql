/* =============================================================
   FLUSH DATA TEST -- modul PDH TNI AD (2026-10-07)

   JANGAN DIJALANKAN TANPA DICEK. Default @Commit = 0 -> semua perubahan
   di-ROLLBACK, hanya jumlah baris yang ditampilkan. Ganti ke 1 untuk benar-benar
   menghapus.

   DIHAPUS (HARD DELETE, semua order):
     tni.stok_mutasi    semua mutasi (setoran, terpakai, rusak, koreksi, bongkar)
     tni.stok_setoran   header setoran
     tni.stok_keluar    header pengeluaran
     tni.pembatalan     pengajuan batal set / keluar box
     tni.komplain       komplain ukuran dari halaman QR
     tni.box            semua box (box_no / box_code mulai lagi dari 01)

   DIRESET di tni.personel (kembali ke BELUM_CETAK):
     printed_at/by/perangkat, print_count = 0, set_at/by/perangkat,
     boxed_at/by/perangkat, box_id, urut_dalam_box

   TIDAK DISENTUH: orders, area_rawatan, satuan, pola_kemeja, pola_celana,
     personel (datanya), import_batch, import_staging, perangkat, perangkat_menu.

   OPSIONAL (bagian paling bawah, dikomentari): antrian cetak kartu
     dbo.print_jobs job_type 'TNI_KARTU' -- tabel di luar schema tni.
   ============================================================= */

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Commit BIT = 0;   -- 0 = cek saja (ROLLBACK), 1 = hapus beneran

-- ---------- Sebelum ----------
SELECT 'SEBELUM' AS Tahap,
       (SELECT COUNT(*) FROM tni.stok_mutasi)  AS stok_mutasi,
       (SELECT COUNT(*) FROM tni.stok_setoran) AS stok_setoran,
       (SELECT COUNT(*) FROM tni.stok_keluar)  AS stok_keluar,
       (SELECT COUNT(*) FROM tni.pembatalan)   AS pembatalan,
       (SELECT COUNT(*) FROM tni.komplain)     AS komplain,
       (SELECT COUNT(*) FROM tni.box)          AS box,
       (SELECT COUNT(*) FROM tni.personel
         WHERE printed_at IS NOT NULL OR set_at IS NOT NULL OR boxed_at IS NOT NULL
            OR box_id IS NOT NULL OR print_count > 0) AS personel_ada_progres;

SELECT status_progres, COUNT(*) AS jumlah
FROM tni.v_personel
GROUP BY status_progres
ORDER BY status_progres;

BEGIN TRANSACTION;

    -- urutan mengikuti FK: mutasi -> header stok; pembatalan & personel -> box
    DELETE FROM tni.stok_mutasi;
    DELETE FROM tni.stok_setoran;
    DELETE FROM tni.stok_keluar;
    DELETE FROM tni.pembatalan;
    DELETE FROM tni.komplain;

    UPDATE tni.personel
    SET printed_at           = NULL,
        printed_by           = NULL,
        printed_perangkat_id = NULL,
        print_count          = 0,
        set_at               = NULL,
        set_by               = NULL,
        set_perangkat_id     = NULL,
        boxed_at             = NULL,
        boxed_by             = NULL,
        boxed_perangkat_id   = NULL,
        box_id               = NULL,
        urut_dalam_box       = NULL
    WHERE printed_at IS NOT NULL OR set_at IS NOT NULL OR boxed_at IS NOT NULL
       OR box_id IS NOT NULL OR print_count > 0;

    DELETE FROM tni.box;

    -- ---------- Sesudah ----------
    SELECT 'SESUDAH' AS Tahap,
           (SELECT COUNT(*) FROM tni.stok_mutasi)  AS stok_mutasi,
           (SELECT COUNT(*) FROM tni.stok_setoran) AS stok_setoran,
           (SELECT COUNT(*) FROM tni.stok_keluar)  AS stok_keluar,
           (SELECT COUNT(*) FROM tni.pembatalan)   AS pembatalan,
           (SELECT COUNT(*) FROM tni.komplain)     AS komplain,
           (SELECT COUNT(*) FROM tni.box)          AS box,
           (SELECT COUNT(*) FROM tni.personel
             WHERE printed_at IS NOT NULL OR set_at IS NOT NULL OR boxed_at IS NOT NULL
                OR box_id IS NOT NULL OR print_count > 0) AS personel_ada_progres;

    SELECT status_progres, COUNT(*) AS jumlah
    FROM tni.v_personel
    GROUP BY status_progres
    ORDER BY status_progres;

IF @Commit = 1
BEGIN
    COMMIT TRANSACTION;

    -- ID mulai lagi dari 1 (hanya setelah commit; tabel sudah kosong)
    DBCC CHECKIDENT ('tni.stok_mutasi',  RESEED, 0);
    DBCC CHECKIDENT ('tni.stok_setoran', RESEED, 0);
    DBCC CHECKIDENT ('tni.stok_keluar',  RESEED, 0);
    DBCC CHECKIDENT ('tni.pembatalan',   RESEED, 0);
    DBCC CHECKIDENT ('tni.komplain',     RESEED, 0);
    DBCC CHECKIDENT ('tni.box',          RESEED, 0);

    PRINT 'COMMIT -- data test TNI sudah dihapus.';
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
    PRINT 'ROLLBACK -- tidak ada yang berubah (ganti @Commit = 1 untuk menghapus).';
END
GO

/* ---------- OPSIONAL: antrian cetak kartu TNI (dbo.print_jobs) ----------
   Hanya riwayat job cetak kartu; tidak memengaruhi status personel.
   Cek dulu jumlahnya, hapus bila memang mau bersih.

SELECT COUNT(*) AS job_kartu FROM dbo.print_jobs WHERE job_type = 'TNI_KARTU';
DELETE FROM dbo.print_jobs WHERE job_type = 'TNI_KARTU';
*/

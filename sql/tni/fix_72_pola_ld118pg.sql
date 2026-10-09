-- Fix 72: tambah pola kemeja LD_118_PG + masukkan 1 personel terakhir yang
--         ditolak import karena pola itu belum ada.
--
-- Baris sisa dari batch 2/3: I Dewa Gede Putra Suparta (Serma, Pusdikbekang
-- Pusbekangad), isian form minta kemeja LD_118_PG yang tidak ada di master.
--
-- PENTING -- angka LD_118_PG di bawah adalah INTERPOLASI antara LD_116_PG dan
-- LD_120_PG, BUKAN dari grading Kang Wawan. Seri PG di file grading melangkah
-- 2 cm sampai 116 lalu langsung 120 (108 110 112 114 116 _ 120 124 128 ...),
-- jadi 118 memang bukan langkah grading yang pernah dibuat. Owner memutuskan
-- (2026-10-05) pola ini tetap dibuat supaya data 7279 masuk utuh.
-- ==> Mintakan konfirmasi angkanya ke pembuat pola SEBELUM kain dipotong.
--
-- Catatan ukuran: dada terukur personel ini 114 (perut 118, pinggul 116), jadi
-- LD_114_PG sebetulnya lebih pas; isian form 'LD_118_PG' sepertinya terbaca dari
-- kolom perut, bukan dada. Pola bisa diubah lewat /tni/pola selama belum set jadi.
--
-- Idempotent: IF NOT EXISTS untuk pola, dan putaran kedua import jadi PERBARUI.
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @SeedUserId INT = 1;

IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja WHERE kode = 'LD_118_PG' AND deleted_at IS NULL)
    INSERT INTO tni.pola_kemeja (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu, lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan, lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
    VALUES ('LD_118_PG', NULL, 'PG', 118, 42.5, 50, 118, 124, 126.5, 76.5, 42.5, 60.5, 26.5, NULL, 1, @SeedUserId);
GO

-- ---------- masukkan personelnya lewat SP import yang normal ----------
DECLARE @BatchSumber INT = 3;
DECLARE @OrderId INT, @UserId INT, @Rows NVARCHAR(MAX);

SELECT @OrderId = order_id, @UserId = created_by
FROM tni.import_batch
WHERE batch_id = @BatchSumber AND deleted_at IS NULL;

IF @OrderId IS NULL
BEGIN
    RAISERROR('Batch sumber %d tidak ditemukan.', 16, 1, @BatchSumber);
    RETURN;
END

SELECT @Rows = CONCAT('[', STRING_AGG(CAST(raw_json AS NVARCHAR(MAX)), ','), ']')
FROM tni.import_staging
WHERE batch_id       = @BatchSumber
  AND hasil_validasi = 'TOLAK'
  AND pesan_error LIKE 'Pola kemeja%';

IF @Rows IS NULL
BEGIN
    RAISERROR('Tidak ada baris tertolak pola kemeja di batch %d.', 16, 1, @BatchSumber);
    RETURN;
END

DECLARE @Hasil TABLE (BatchId INT);

INSERT INTO @Hasil (BatchId)
EXEC tni.SIS_Import_Stage
        @OrderId  = @OrderId,
        @NamaFile = 'Grouping Size Kodam Siliwangi.xlsx (fix 72: LD_118_PG)',
        @Rows     = @Rows,
        @UserId   = @UserId;

DECLARE @BatchBaru INT = (SELECT TOP 1 BatchId FROM @Hasil);

PRINT CONCAT('Batch baru: ', @BatchBaru);

DECLARE @Ditolak INT = (SELECT COUNT(*) FROM tni.import_staging
                        WHERE batch_id = @BatchBaru AND hasil_validasi = 'TOLAK');

IF @Ditolak > 0
BEGIN
    SELECT baris_ke, nrp, nama, pesan_error
    FROM tni.import_staging
    WHERE batch_id = @BatchBaru AND hasil_validasi = 'TOLAK';

    RAISERROR('Masih ditolak (%d baris) di batch %d -- commit DIBATALKAN.', 16, 1, @Ditolak, @BatchBaru);
    RETURN;
END

EXEC tni.SIS_Import_Commit @BatchId = @BatchBaru, @UserId = @UserId;
GO

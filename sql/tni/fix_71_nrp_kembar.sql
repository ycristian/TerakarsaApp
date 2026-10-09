-- Fix 71: masukkan 32 personel yang ditolak import karena NRP kembar.
--
-- Latar: batch import 2/3 (Grouping Size Kodam Siliwangi.xlsx, 7279 baris) menolak
-- 33 baris, sehingga tni.personel hanya berisi 7246. 32 dari 33 itu adalah 16 pasang
-- baris dengan NRP sama. SIS_Import_Stage menolak KEDUA sisi tiap pasangan, jadi
-- 32 orang yang BERBEDA tidak pernah masuk -- NRP-nya salah ketik di file sumber.
--
-- Keputusan owner (2026-10-05): masukkan apa adanya; baris kedua tiap pasangan
-- (baris_ke lebih besar) diberi akhiran '*' pada NRP supaya lolos keunikan.
-- NRP bertanda '*' = PERLU DIBETULKAN ke NRP asli setelah dikonfirmasi ke satuan.
--
-- Caranya: raw_json tiap baris masih tersimpan di tni.import_staging, jadi baris itu
-- di-stage ULANG lewat SP import yang normal (bukan INSERT manual ke tni.personel),
-- supaya kode_ref / no_urut / qr_token / validasi tetap dibuat oleh SIS_Import_Commit.
--
-- Idempotent: dijalankan dua kali, putaran kedua jadi aksi PERBARUI (bukan baris baru).
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @BatchSumber INT = 3;          -- batch yang menyimpan raw_json 7279 baris
DECLARE @OrderId     INT,
        @UserId      INT,
        @Rows        NVARCHAR(MAX);

SELECT @OrderId = order_id, @UserId = created_by
FROM tni.import_batch
WHERE batch_id = @BatchSumber AND deleted_at IS NULL;

IF @OrderId IS NULL
BEGIN
    RAISERROR('Batch sumber %d tidak ditemukan.', 16, 1, @BatchSumber);
    RETURN;
END

-- ---------- susun ulang baris: NRP pasangan ke-2 ditambah '*' ----------
;WITH t AS (
    SELECT staging_id, baris_ke, nrp, raw_json,
           rn = ROW_NUMBER() OVER (PARTITION BY nrp ORDER BY baris_ke)
    FROM tni.import_staging
    WHERE batch_id        = @BatchSumber
      AND hasil_validasi  = 'TOLAK'
      AND pesan_error LIKE 'NRP kembar%'
)
SELECT @Rows = CONCAT('[', STRING_AGG(CAST(
           JSON_MODIFY(raw_json, '$.nrp', CASE WHEN rn = 1 THEN nrp ELSE nrp + '*' END)
       AS NVARCHAR(MAX)), ','), ']')
FROM t;

IF @Rows IS NULL
BEGIN
    RAISERROR('Tidak ada baris NRP kembar di batch %d -- tidak ada yang dikerjakan.', 16, 1, @BatchSumber);
    RETURN;
END

-- ---------- stage ulang ----------
DECLARE @Hasil TABLE (BatchId INT);

INSERT INTO @Hasil (BatchId)
EXEC tni.SIS_Import_Stage
        @OrderId  = @OrderId,
        @NamaFile = 'Grouping Size Kodam Siliwangi.xlsx (fix 71: NRP kembar)',
        @Rows     = @Rows,
        @UserId   = @UserId;

DECLARE @BatchBaru INT = (SELECT TOP 1 BatchId FROM @Hasil);

PRINT CONCAT('Batch baru: ', @BatchBaru);

-- ---------- pengaman: jangan commit kalau masih ada yang ditolak ----------
DECLARE @Ditolak INT = (SELECT COUNT(*) FROM tni.import_staging
                        WHERE batch_id = @BatchBaru AND hasil_validasi = 'TOLAK');

IF @Ditolak > 0
BEGIN
    SELECT baris_ke, nrp, nama, pesan_error
    FROM tni.import_staging
    WHERE batch_id = @BatchBaru AND hasil_validasi = 'TOLAK'
    ORDER BY baris_ke;

    RAISERROR('Masih ada %d baris ditolak di batch %d -- commit DIBATALKAN, periksa dulu.',
              16, 1, @Ditolak, @BatchBaru);
    RETURN;
END

EXEC tni.SIS_Import_Commit @BatchId = @BatchBaru, @UserId = @UserId;
GO

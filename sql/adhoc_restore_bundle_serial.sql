/* =============================================================
   ADHOC -- Hidupkan kembali bundle yang sudah dihapus (soft delete),
   berdasarkan SERIAL (2026-11-10).

   Bundle dihapus lewat 3 jalur, semuanya soft delete (deleted_at):
     - SIS_Bundle_Manage DELETE        -> bundle + baris log step Bundling
                                          (delete_reason log = 'Bundle dihapus')
     - SIS_SuperAdmin_Manage BUNDLE_DELETE -> bundle saja (tanpa log hidup)
     - Cutting (hapus hamparan / REMOVE)   -> bundle saja

   Script ini:
     1. Ambil baris TERHAPUS TERBARU per serial.
     2. Tolak kalau bentrok: serial sudah dipakai bundle hidup (UX_bundles_serial),
        kode cutting sudah dipakai (UX_bundles_cutting_code), nomor anak bentrok
        (UX_bundles_root_sequence), hamparan/artikel/size/induk masih terhapus.
     3. Clear deleted_at/deleted_by/delete_reason bundle, isi updated_at/updated_by.
     4. Hidupkan juga baris log yang ikut terhapus BERSAMA bundle itu
        (delete_reason = 'Bundle dihapus', deleted_by sama, selisih waktu <= 5 detik).
        Log yang dihapus terpisah (sebelum/sesudah) TIDAK disentuh.

   Cara pakai:
     1. Isi @Serials (pisah koma), jalankan dengan @DryRun = 1 -> preview.
     2. Cek kolom catatan, isi @UserId, ganti @DryRun = 0, jalankan lagi.
   ============================================================= */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @DryRun  BIT          = 1;     -- 1 preview | 0 eksekusi
DECLARE @UserId  INT          = NULL;  -- WAJIB saat eksekusi: dbo.Users.Id pelaksana
DECLARE @Serials VARCHAR(MAX) = '';    -- mis. 'B26-005742, B26-005743'

-- ---------- KANDIDAT ----------
IF OBJECT_ID('tempdb..#cand') IS NOT NULL DROP TABLE #cand;

-- Tabel eksplisit (bukan SELECT INTO): OUTER APPLY + SELECT INTO mewarisi NOT NULL
-- kolom bundles -> error 681 untuk serial yang tidak ditemukan.
CREATE TABLE #cand(
    input_serial     VARCHAR(50)  NOT NULL,
    bundle_id        INT          NULL,
    serial           VARCHAR(20)  NULL,
    article_id       INT          NULL,
    article_size_id  INT          NULL,
    qty              INT          NULL,
    source           VARCHAR(10)  NULL,
    cutting_code     VARCHAR(30)  NULL,
    spread_id        INT          NULL,
    parent_bundle_id INT          NULL,
    root_bundle_id   INT          NULL,
    sequence_no      INT          NULL,
    deleted_at       DATETIME2    NULL,
    deleted_by       INT          NULL,
    delete_reason    VARCHAR(255) NULL,
    catatan          VARCHAR(200) NULL);

INSERT INTO #cand(input_serial, bundle_id, serial, article_id, article_size_id, qty, source,
                  cutting_code, spread_id, parent_bundle_id, root_bundle_id, sequence_no,
                  deleted_at, deleted_by, delete_reason)
SELECT t.input_serial,
       b.bundle_id, b.serial, b.article_id, b.article_size_id, b.qty, b.source,
       b.cutting_code, b.spread_id, b.parent_bundle_id, b.root_bundle_id, b.sequence_no,
       b.deleted_at, b.deleted_by, b.delete_reason
FROM (SELECT DISTINCT LTRIM(RTRIM(value)) AS input_serial
      FROM STRING_SPLIT(@Serials, ',')
      WHERE LTRIM(RTRIM(value)) <> '') t
OUTER APPLY (SELECT TOP 1 x.*
             FROM bundles x
             WHERE x.serial = t.input_serial AND x.deleted_at IS NOT NULL
             ORDER BY x.deleted_at DESC, x.bundle_id DESC) b;

IF NOT EXISTS (SELECT 1 FROM #cand)
BEGIN
    RAISERROR('@Serials kosong.', 16, 1);
    RETURN;
END

-- Urutan = prioritas: alasan pertama yang cocok yang dipakai.
UPDATE c SET catatan =
    CASE
        WHEN c.bundle_id IS NULL AND EXISTS (SELECT 1 FROM bundles h WHERE h.serial = c.input_serial AND h.deleted_at IS NULL)
            THEN 'DILEWATI: bundle ini masih hidup'
        WHEN c.bundle_id IS NULL
            THEN 'DILEWATI: serial tidak ditemukan'
        WHEN EXISTS (SELECT 1 FROM bundles h WHERE h.serial = c.serial AND h.deleted_at IS NULL)
            THEN 'DITOLAK: serial sudah dipakai bundle hidup lain'
        WHEN c.cutting_code IS NOT NULL AND EXISTS (SELECT 1 FROM bundles h
                 WHERE h.article_id = c.article_id AND h.cutting_code = c.cutting_code AND h.deleted_at IS NULL)
            THEN 'DITOLAK: kode cutting ' + c.cutting_code + ' sudah dipakai bundle hidup (hamparan dinomori ulang)'
        WHEN c.root_bundle_id <> 0 AND EXISTS (SELECT 1 FROM bundles h
                 WHERE h.root_bundle_id = c.root_bundle_id AND h.sequence_no = c.sequence_no AND h.deleted_at IS NULL)
            THEN 'DITOLAK: nomor anak (root/sequence) sudah dipakai bundle hidup'
        WHEN c.parent_bundle_id IS NOT NULL AND EXISTS (SELECT 1 FROM bundles p
                 WHERE p.bundle_id = c.parent_bundle_id AND p.deleted_at IS NOT NULL)
            THEN 'DITOLAK: bundle induk masih terhapus -- hidupkan induknya dulu'
        WHEN c.spread_id IS NOT NULL AND EXISTS (SELECT 1 FROM spreads s
                 WHERE s.spread_id = c.spread_id AND s.deleted_at IS NOT NULL)
            THEN 'DITOLAK: hamparan sudah dihapus'
        WHEN EXISTS (SELECT 1 FROM articles a WHERE a.article_id = c.article_id AND a.deleted_at IS NOT NULL)
            THEN 'DITOLAK: artikel sudah dihapus'
        WHEN EXISTS (SELECT 1 FROM article_sizes z WHERE z.article_size_id = c.article_size_id AND z.deleted_at IS NOT NULL)
            THEN 'DITOLAK: size artikel sudah dihapus'
        ELSE 'OK'
    END
FROM #cand c;

-- Log yang terhapus bersamaan dengan bundle (jalur SIS_Bundle_Manage DELETE).
IF OBJECT_ID('tempdb..#logs') IS NOT NULL DROP TABLE #logs;

SELECT awl.workflow_log_id, awl.bundle_id
INTO #logs
FROM #cand c
INNER JOIN article_workflow_logs awl ON awl.bundle_id = c.bundle_id
WHERE c.catatan = 'OK'
  AND awl.deleted_at IS NOT NULL
  AND awl.delete_reason = 'Bundle dihapus'
  AND awl.deleted_by = c.deleted_by
  AND ABS(DATEDIFF(SECOND, awl.deleted_at, c.deleted_at)) <= 5;

-- ---------- PREVIEW ----------
SELECT c.input_serial,
       c.catatan,
       c.bundle_id,
       CONCAT(a.article_name, ' / ', spd.size_name)                              AS artikel_size,
       c.qty,
       c.source,
       c.cutting_code,
       c.deleted_at,
       c.deleted_by,
       c.delete_reason,
       (SELECT COUNT(*) FROM #logs l WHERE l.bundle_id = c.bundle_id)            AS log_ikut_dihidupkan,
       (SELECT COUNT(*) FROM bundles o WHERE o.serial = c.input_serial
            AND o.deleted_at IS NOT NULL AND o.bundle_id <> c.bundle_id)         AS baris_terhapus_lain_serial_sama
FROM #cand c
LEFT JOIN articles a      ON a.article_id = c.article_id
LEFT JOIN article_sizes z ON z.article_size_id = c.article_size_id
LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = z.size_pack_detail_id
ORDER BY CASE WHEN c.catatan = 'OK' THEN 0 ELSE 1 END, c.input_serial;

IF @DryRun = 1
BEGIN
    PRINT 'DRY RUN -- tidak ada yang disimpan. Set @DryRun = 0 dan @UserId untuk eksekusi.';
    RETURN;
END

IF @UserId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId)
BEGIN
    RAISERROR('@UserId wajib diisi dengan user yang valid.', 16, 1);
    RETURN;
END

IF NOT EXISTS (SELECT 1 FROM #cand WHERE catatan = 'OK')
BEGIN
    PRINT 'Tidak ada bundle yang bisa dihidupkan.';
    RETURN;
END

-- ---------- EKSEKUSI ----------
BEGIN TRAN;

    UPDATE b
    SET deleted_at    = NULL,
        deleted_by    = NULL,
        delete_reason = NULL,
        updated_at    = SYSDATETIME(),
        updated_by    = @UserId
    FROM bundles b
    INNER JOIN #cand c ON c.bundle_id = b.bundle_id
    WHERE c.catatan = 'OK' AND b.deleted_at IS NOT NULL;

    UPDATE awl
    SET deleted_at    = NULL,
        deleted_by    = NULL,
        delete_reason = NULL
    FROM article_workflow_logs awl
    INNER JOIN #logs l ON l.workflow_log_id = awl.workflow_log_id;

COMMIT TRAN;

-- ---------- CEK SETELAH ----------
SELECT b.bundle_id, b.serial, b.qty, b.deleted_at, b.updated_at, b.updated_by,
       (SELECT COUNT(*) FROM article_workflow_logs awl
         WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL) AS log_hidup
FROM bundles b
INNER JOIN #cand c ON c.bundle_id = b.bundle_id
WHERE c.catatan = 'OK';

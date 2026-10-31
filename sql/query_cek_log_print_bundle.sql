-- Ad hoc (read-only): siapa yang minta cetak stiker satu bundle, urut permintaan TERBARU dulu.
--
-- Isi @Bundle dengan salah satu dari: serial (B26-005742), kode hamparan cutting
-- (H06-M-03), atau nomor bundle (bundle_no, mis. 5742). Pencocokan LIKE, jadi
-- potongan kode juga boleh ('005742'). NULL = semua bundle (dibatasi @TopN).
-- @HanyaReprint = 1 -> buang cetakan pertama, tampilkan REPRINT saja.
--
-- Job type yang dihitung sebagai "minta print stiker bundle":
--   BUNDLE_LABEL          -- /bundles, station Buat Bundle, reprint, bundle anak (Prompt 82)
--   CUTTING_BUNDLE_LABEL  -- stiker hamparan module Cutting (SIS_CuttingBundle_Print)
--
-- CETAK PERTAMA vs REPRINT: print_jobs TIDAK menyimpan pembedanya -- SIS_Bundle_Manage
-- (cetak otomatis saat bundle dibuat), SIS_Bundle_ReprintLabel, SIS_BundleSplit_Manage
-- (stiker bundle anak) dan SIS_CuttingBundle_Print semuanya INSERT job_type yang sama.
-- Jadi kolom Jenis di bawah DITURUNKAN, bukan dibaca:
--   klik pertama bundle itu DAN <= 5 detik dari bundles.created_at  -> 'Cetak pertama'
--   sisanya                                                        -> 'Reprint ke-N'
-- Satu klik = beberapa baris (SP INSERT satu baris per lembar, created_at identik),
-- jadi nomor klik dihitung dari created_at yang berbeda -- bukan dari jumlah baris.
-- Catatan: bundle yang dibuat lewat /bundles dengan PrintCopies = 0 tidak punya cetakan
-- otomatis, jadi cetakan manual pertamanya tetap terbaca 'Reprint ke-1'.
--
-- PERHATIAN soal "siapa": print_jobs hanya menyimpan created_by (tabel Users).
-- Permintaan dari perangkat station TIDAK membawa identitas operator -- semuanya
-- tercatat sebagai user sistem station_system (lihat StationDeviceController,
-- _systemUserId). Untuk baris itu kolom Peminta akan selalu 'station_system';
-- operator per sesi tidak pernah disimpan di print_jobs.
--
-- READ-ONLY (tidak membuat/mengubah apa pun).
SET NOCOUNT ON;

DECLARE @Bundle       VARCHAR(50) = 'B26-005742';   -- serial / cutting_code / bundle_no; NULL = semua
DECLARE @HanyaReprint BIT         = 0;              -- 1 = reprint saja
DECLARE @TopN         INT         = 200;

;WITH Jobs AS (
    SELECT pj.print_job_id, pj.job_type, pj.[status], pj.created_at, pj.created_by,
           pj.printed_at, pj.retry_count, pj.error_message, pj.print_device_id,
           pj.ref_id,
           DENSE_RANK() OVER (PARTITION BY pj.ref_id, pj.job_type
                              ORDER BY pj.created_at)            AS KlikNo,
           DATEDIFF(SECOND, b.created_at, pj.created_at)          AS DetikSetelahBundleLahir
    FROM print_jobs pj
    INNER JOIN bundles b ON b.bundle_id = pj.ref_id
    WHERE pj.deleted_at IS NULL
      AND pj.job_type IN ('BUNDLE_LABEL', 'CUTTING_BUNDLE_LABEL')
      AND (@Bundle IS NULL
           OR b.serial       LIKE '%' + @Bundle + '%'
           OR b.cutting_code LIKE '%' + @Bundle + '%'
           OR CAST(b.bundle_no AS VARCHAR(20)) = @Bundle)
), Flagged AS (
    -- Apakah bundle ini punya cetakan OTOMATIS di klik pertama? Flag dihitung per bundle,
    -- supaya baris klik ke-3 pun tahu klik pertamanya auto atau bukan.
    SELECT j.*,
           MAX(CASE WHEN j.KlikNo = 1 AND j.DetikSetelahBundleLahir <= 5 THEN 1 ELSE 0 END)
               OVER (PARTITION BY j.ref_id, j.job_type)           AS AdaCetakOtomatis
    FROM Jobs j
), Labeled AS (
    SELECT f.*,
           CASE WHEN f.KlikNo = 1 AND f.AdaCetakOtomatis = 1 THEN 0 ELSE 1 END AS IsReprint,
           CASE WHEN f.KlikNo = 1 AND f.AdaCetakOtomatis = 1 THEN 'Cetak pertama'
                ELSE 'Reprint ke-' + CAST(f.KlikNo - f.AdaCetakOtomatis AS VARCHAR(10))
           END                                                    AS Jenis
    FROM Flagged f
)
-- ---------- 1. Detail tiap permintaan (terbaru dulu) ----------
SELECT TOP (@TopN)
       j.created_at                             AS WaktuMinta,
       j.Jenis                                  AS Jenis,          -- diturunkan, lihat header
       j.KlikNo                                 AS KlikKe,         -- 1 = permintaan pertama bundle ini
       u.FullName                               AS Peminta,
       u.Username                               AS PemintaUsername,
       u.Role                                   AS PemintaRole,
       j.job_type                               AS JenisJob,
       j.[status]                               AS StatusJob,
       j.printed_at                             AS WaktuCetak,
       j.retry_count                            AS Retry,
       j.error_message                          AS Error,
       pd.device_name                           AS Printer,        -- diisi saat KLAIM (Prompt 48)
       b.serial                                 AS Serial,
       b.bundle_no                              AS NoBundle,
       b.cutting_code                           AS KodeCutting,
       b.sequence_no                            AS NoAnak,          -- 0 = induk utama
       b.[status]                               AS StatusBundle,
       b.qty                                    AS Qty,
       b.created_at                             AS BundleDibuat,
       p.project_name                           AS Project,
       a.article_name                           AS Artikel,
       spd.size_name                            AS Ukuran,
       j.print_job_id                           AS PrintJobId,
       b.bundle_id                              AS BundleId
FROM Labeled j
INNER JOIN bundles b           ON b.bundle_id = j.ref_id
INNER JOIN articles a          ON a.article_id = b.article_id
INNER JOIN projects p          ON p.project_id = a.project_id
INNER JOIN article_sizes asz   ON asz.article_size_id = b.article_size_id
INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
LEFT  JOIN Users u             ON u.Id = j.created_by
LEFT  JOIN print_devices pd    ON pd.print_device_id = j.print_device_id
WHERE (@HanyaReprint = 0 OR j.IsReprint = 1)
ORDER BY j.created_at DESC, j.print_job_id DESC;

-- ---------- 2. Rekap per peminta: cetak pertama vs reprint ----------
;WITH Jobs AS (
    SELECT pj.print_job_id, pj.job_type, pj.created_at, pj.created_by, pj.ref_id,
           DENSE_RANK() OVER (PARTITION BY pj.ref_id, pj.job_type
                              ORDER BY pj.created_at)   AS KlikNo,
           DATEDIFF(SECOND, b.created_at, pj.created_at) AS DetikSetelahBundleLahir
    FROM print_jobs pj
    INNER JOIN bundles b ON b.bundle_id = pj.ref_id
    WHERE pj.deleted_at IS NULL
      AND pj.job_type IN ('BUNDLE_LABEL', 'CUTTING_BUNDLE_LABEL')
      AND (@Bundle IS NULL
           OR b.serial       LIKE '%' + @Bundle + '%'
           OR b.cutting_code LIKE '%' + @Bundle + '%'
           OR CAST(b.bundle_no AS VARCHAR(20)) = @Bundle)
), Flagged AS (
    SELECT j.*,
           MAX(CASE WHEN j.KlikNo = 1 AND j.DetikSetelahBundleLahir <= 5 THEN 1 ELSE 0 END)
               OVER (PARTITION BY j.ref_id, j.job_type)  AS AdaCetakOtomatis
    FROM Jobs j
)
SELECT u.FullName                                AS Peminta,
       j.job_type                                AS JenisJob,
       CASE WHEN j.KlikNo = 1 AND j.AdaCetakOtomatis = 1
            THEN 'Cetak pertama' ELSE 'Reprint' END AS Jenis,
       COUNT(*)                                  AS JumlahLembar,
       COUNT(DISTINCT j.created_at)              AS JumlahKlik,
       MIN(j.created_at)                         AS PertamaMinta,
       MAX(j.created_at)                         AS TerakhirMinta
FROM Flagged j
LEFT JOIN Users u ON u.Id = j.created_by
WHERE (@HanyaReprint = 0
       OR NOT (j.KlikNo = 1 AND j.AdaCetakOtomatis = 1))
GROUP BY u.FullName, j.job_type,
         CASE WHEN j.KlikNo = 1 AND j.AdaCetakOtomatis = 1
              THEN 'Cetak pertama' ELSE 'Reprint' END
ORDER BY MAX(j.created_at) DESC;

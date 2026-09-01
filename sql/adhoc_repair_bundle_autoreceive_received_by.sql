/* =============================================================
   adhoc_repair_bundle_autoreceive_received_by.sql
   Perbaikan sekali jalan atas bug aturan #15/#18 di sp_Bundle_Manage.sql.

   Masalah: saat bundle dibuat/diedit dan step tujuan (mis. Sew+QC) ber-
   auto_receive = 1, log Bundling-nya ditandai diterima dengan
   received_by_resource_id = resource divisi BUNDLING sendiri (pelaksana yang
   mengemas bundle), bukan resource Line/penjahit divisi TUJUAN (bundles.resource_id).
   Akibat: sp_WorkflowLog_Manage "penerima mengikat pelaksana" (Prompt 40 SS7)
   mengunci pelaksana step berikutnya harus = received_by_resource_id itu --
   tidak akan pernah cocok (resource itu bukan anggota divisi tujuan), bundle
   buntu permanen ("Bundle ini atas nama X. Batalkan penerimaan dulu...").

   Beda dengan repair_40_received_by.sql (itu utk data lama sebelum Prompt 40,
   dipetakan lewat counterpart_resource_id): baris di sini SEMUA berasal dari
   log Bundling implisit (article_workflows.is_bundling = 1) dengan
   received_remark = 'Otomatis: auto-terima', dan bundles.resource_id (Line
   yang ditugaskan saat bundle dibuat) SUDAH BENAR sejak awal -- jadi
   perbaikannya cukup salin bundles.resource_id ke received_by_resource_id,
   tanpa perlu lookup counterpart.

   Baris yang bundles.resource_id-nya TERNYATA juga bukan milik divisi tujuan
   (kasus lain, di luar bug ini) TIDAK disentuh -- perlu diperiksa manual.

   Idempotent: sekali dijalankan, tidak ada lagi baris yang cocok kriteria.
   Jalankan BAGIAN 1 (pratinjau) dulu, periksa hasilnya, baru BAGIAN 2.
   ============================================================= */

SET NOCOUNT ON;
GO

IF OBJECT_ID('tempdb..#fix') IS NOT NULL DROP TABLE #fix;

SELECT
    l.workflow_log_id,
    l.bundle_id,
    b.serial,
    l.received_by_resource_id AS old_received_by,
    rr.resource_name          AS old_received_by_name,
    rr.division_id            AS old_received_by_division_id,
    b.resource_id             AS new_received_by,
    rb.resource_name          AS new_received_by_name,
    l.target_division_id,
    dt.division_name          AS target_division_name
INTO #fix
FROM article_workflow_logs l
INNER JOIN article_workflows aw ON aw.article_workflow_id = l.article_workflow_id
INNER JOIN bundles b            ON b.bundle_id = l.bundle_id
INNER JOIN divisions dt         ON dt.division_id = l.target_division_id
LEFT JOIN resources rr          ON rr.resource_id = l.received_by_resource_id
LEFT JOIN resources rb          ON rb.resource_id = b.resource_id
                                AND rb.deleted_at IS NULL
                                AND rb.division_id = l.target_division_id
WHERE l.deleted_at IS NULL
  AND aw.is_bundling = 1
  AND l.received_remark = 'Otomatis: auto-terima'
  AND l.received_at IS NOT NULL
  AND l.target_division_id IS NOT NULL
  AND (rr.division_id IS NULL OR rr.division_id <> l.target_division_id)  -- tanda salah isi
  AND rb.resource_id IS NOT NULL;                                        -- hanya yg bisa dipastikan benar
GO

/* =============================================================
   BAGIAN 1 — PRATINJAU. Periksa dulu, jangan langsung lanjut.
   ============================================================= */

SELECT * FROM #fix ORDER BY target_division_name, workflow_log_id;

-- Baris bug yang TIDAK ikut diperbaiki di sini (bundles.resource_id juga tidak
-- cocok divisi tujuan) -- perlu diperiksa manual, pola sama dengan repair_40.
SELECT l.workflow_log_id, l.bundle_id, b.serial, l.received_by_resource_id, rr.resource_name AS old_received_by_name,
       b.resource_id AS bundle_resource_id, rb2.resource_name AS bundle_resource_name, l.target_division_id, dt.division_name
FROM article_workflow_logs l
INNER JOIN article_workflows aw ON aw.article_workflow_id = l.article_workflow_id
INNER JOIN bundles b            ON b.bundle_id = l.bundle_id
INNER JOIN divisions dt         ON dt.division_id = l.target_division_id
LEFT JOIN resources rr          ON rr.resource_id = l.received_by_resource_id
LEFT JOIN resources rb2         ON rb2.resource_id = b.resource_id
WHERE l.deleted_at IS NULL
  AND aw.is_bundling = 1
  AND l.received_remark = 'Otomatis: auto-terima'
  AND l.received_at IS NOT NULL
  AND l.target_division_id IS NOT NULL
  AND (rr.division_id IS NULL OR rr.division_id <> l.target_division_id)
  AND NOT EXISTS (SELECT 1 FROM #fix f WHERE f.workflow_log_id = l.workflow_log_id);
GO

/* =============================================================
   BAGIAN 2 — EKSEKUSI.
   Hapus blok komentar di bawah HANYA setelah pratinjau dinilai benar.
   ============================================================= */
/*
BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE l
    SET l.received_by_resource_id = f.new_received_by,
        l.received_remark = LEFT(
            ISNULL(NULLIF(l.received_remark, '') + ' | ', '')
            + 'Penerima dikoreksi (adhoc_repair_bundle_autoreceive)', 500)
    FROM article_workflow_logs l
    INNER JOIN #fix f ON f.workflow_log_id = l.workflow_log_id;

    PRINT 'Baris dikoreksi penerimanya : ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO
*/

/* =============================================================
   BAGIAN 3 — VERIFIKASI. Jalankan setelah BAGIAN 2.
   Harus mengembalikan 0 baris (untuk baris yang tercakup #fix).
   ============================================================= */

SELECT COUNT(*) AS sisa_baris_salah
FROM article_workflow_logs l
INNER JOIN article_workflows aw ON aw.article_workflow_id = l.article_workflow_id
INNER JOIN bundles b            ON b.bundle_id = l.bundle_id
INNER JOIN resources rr         ON rr.resource_id = l.received_by_resource_id
WHERE l.deleted_at IS NULL
  AND aw.is_bundling = 1
  AND l.received_remark LIKE 'Otomatis: auto-terima%'
  AND l.received_at IS NOT NULL
  AND l.target_division_id IS NOT NULL
  AND rr.division_id <> l.target_division_id;
GO

IF OBJECT_ID('tempdb..#fix') IS NOT NULL DROP TABLE #fix;
GO

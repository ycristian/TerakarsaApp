/* =============================================================
   repair_40_received_by.sql
   Perbaikan sekali jalan atas efek Prompt 34.

   Masalah: auto-receive Prompt 34 mengisi received_by_resource_id dengan
   resource PENGIRIM, padahal baris itu target_division_id-nya divisi lain.
   Akibatnya: laporan salah atribusi, dan setelah Prompt 40 aktif baris-baris
   ini akan buntu (aturan "hanya penerima yang boleh kirim hasil" tidak akan
   pernah terpenuhi, karena penerimanya resource divisi lain).

   Tanda baris bermasalah (dipakai sebagai penanda, bukan received_remark):
     divisi dari received_by_resource_id  <>  target_division_id

   Prioritas perbaikan per baris:
     1. COUNTERPART   -> counterpart_resource_id resource pengirim, valid di divisi tujuan
     2. TUNGGAL       -> divisi tujuan hanya punya SATU resource hidup+aktif
     3. RESET         -> tidak bisa ditentukan; received_at & received_by dikosongkan,
                         baris kembali ke antrean "Menunggu Diterima" (manual)

   JALANKAN SETELAH:
     - alter_40_resource_counterpart.sql
     - counterpart sudah diisi lewat UI (langkah 4 urutan deploy Prompt 40)
   Kalau counterpart belum diisi, langkah 1 tidak akan kena dan lebih banyak
   baris jatuh ke RESET -- tidak merusak, tapi menambah kerja manual di lantai.

   Idempotent: sekali dijalankan, tidak ada lagi baris yang cocok kriteria.
   Jalankan BAGIAN 1 (pratinjau) dulu, periksa hasilnya, baru BAGIAN 2.
   ============================================================= */

SET NOCOUNT ON;
GO

/* ---------- Kumpulkan baris bermasalah + rencana perbaikannya ---------- */

IF OBJECT_ID('tempdb..#fix') IS NOT NULL DROP TABLE #fix;

SELECT
    l.workflow_log_id,
    l.bundle_id,
    l.resource_id                AS sender_resource_id,
    rs.resource_name             AS sender_resource_name,
    ds.division_name             AS sender_division_name,
    l.received_by_resource_id    AS old_received_by,
    rr.resource_name             AS old_received_by_name,
    l.target_division_id,
    dt.division_name             AS target_division_name,
    -- 1. counterpart resource pengirim, wajib hidup+aktif+divisi tujuan
    cp.resource_id               AS counterpart_id,
    -- 2. resource tunggal di divisi tujuan (NULL kalau 0 atau >1)
    solo.resource_id             AS solo_id
INTO #fix
FROM article_workflow_logs l
INNER JOIN divisions dt        ON dt.division_id = l.target_division_id
INNER JOIN resources  rr       ON rr.resource_id = l.received_by_resource_id
LEFT JOIN  resources  rs       ON rs.resource_id = l.resource_id
                              AND rs.deleted_at IS NULL
LEFT JOIN  divisions  ds       ON ds.division_id = rs.division_id
LEFT JOIN  resources  cp       ON cp.resource_id = rs.counterpart_resource_id
                              AND cp.deleted_at IS NULL
                              AND cp.is_active = 1
                              AND cp.division_id = l.target_division_id
OUTER APPLY (
    SELECT MIN(r2.resource_id) AS resource_id
    FROM resources r2
    WHERE r2.division_id = l.target_division_id
      AND r2.deleted_at IS NULL
      AND r2.is_active = 1
    HAVING COUNT(*) = 1
) solo
WHERE l.deleted_at IS NULL
  AND l.received_at IS NOT NULL
  AND l.received_by_resource_id IS NOT NULL
  AND l.target_division_id IS NOT NULL
  AND rr.division_id <> l.target_division_id;   -- <-- tanda salah isi

ALTER TABLE #fix ADD
    new_received_by INT NULL,
    fix_mode        VARCHAR(12) NULL;

UPDATE #fix
SET new_received_by = COALESCE(counterpart_id, solo_id),
    fix_mode = CASE
                   WHEN counterpart_id IS NOT NULL THEN 'COUNTERPART'
                   WHEN solo_id        IS NOT NULL THEN 'TUNGGAL'
                   ELSE 'RESET'
               END;
GO

/* =============================================================
   BAGIAN 1 — PRATINJAU. Periksa dulu, jangan langsung lanjut.
   ============================================================= */

-- Ringkasan per divisi tujuan & jenis perbaikan
SELECT target_division_name,
       fix_mode,
       COUNT(*) AS jumlah_baris
FROM #fix
GROUP BY target_division_name, fix_mode
ORDER BY target_division_name, fix_mode;

-- Pemetaan yang akan dipakai (periksa: Line A1 -> Trim A1, dst)
SELECT DISTINCT
       sender_division_name  AS dari_divisi,
       sender_resource_name  AS dari_resource,
       old_received_by_name  AS penerima_lama_SALAH,
       target_division_name  AS ke_divisi,
       fix_mode,
       rn.resource_name      AS penerima_baru
FROM #fix f
LEFT JOIN resources rn ON rn.resource_id = f.new_received_by
ORDER BY dari_divisi, dari_resource, ke_divisi;

-- Rincian baris yang akan dikembalikan ke penerimaan manual
SELECT workflow_log_id, bundle_id, sender_resource_name, target_division_name
FROM #fix
WHERE fix_mode = 'RESET'
ORDER BY target_division_name, workflow_log_id;
GO

/* =============================================================
   BAGIAN 2 — EKSEKUSI.
   Hapus blok komentar di bawah HANYA setelah pratinjau dinilai benar.
   ============================================================= */
/*
BEGIN TRY
    BEGIN TRANSACTION;

    -- 2a. Baris yang penerimanya bisa ditentukan: cukup ganti penerimanya,
    --     received_at dibiarkan apa adanya (waktu terima historis tetap utuh).
    UPDATE l
    SET l.received_by_resource_id = f.new_received_by,
        l.received_remark = LEFT(
            ISNULL(NULLIF(l.received_remark, '') + ' | ', '')
            + 'Penerima dikoreksi (repair_40, ' + f.fix_mode + ')', 500)
    FROM article_workflow_logs l
    INNER JOIN #fix f ON f.workflow_log_id = l.workflow_log_id
    WHERE f.new_received_by IS NOT NULL;

    PRINT 'Baris dikoreksi penerimanya : ' + CAST(@@ROWCOUNT AS VARCHAR(10));

    -- 2b. Tidak bisa ditentukan: kembalikan ke antrean "Menunggu Diterima".
    UPDATE l
    SET l.received_at = NULL,
        l.received_by_resource_id = NULL,
        l.received_remark = NULL
    FROM article_workflow_logs l
    INNER JOIN #fix f ON f.workflow_log_id = l.workflow_log_id
    WHERE f.new_received_by IS NULL;

    PRINT 'Baris dikembalikan ke manual : ' + CAST(@@ROWCOUNT AS VARCHAR(10));

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
   Harus mengembalikan 0 baris.
   ============================================================= */

SELECT COUNT(*) AS sisa_baris_salah
FROM article_workflow_logs l
INNER JOIN resources rr ON rr.resource_id = l.received_by_resource_id
WHERE l.deleted_at IS NULL
  AND l.received_at IS NOT NULL
  AND l.target_division_id IS NOT NULL
  AND rr.division_id <> l.target_division_id;
GO

IF OBJECT_ID('tempdb..#fix') IS NOT NULL DROP TABLE #fix;
GO

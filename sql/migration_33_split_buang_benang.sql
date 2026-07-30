-- Prompt 33: pemisahan step gabungan "Sew + Trim + QC" menjadi dua step
-- berurutan -- "Sew + QC" (rename step lama) + "Trim" (step baru, requires_bundle
-- mengikuti definisi template, divisi Trim).
--
-- CATATAN PENAMAAN: prompt asli menyebut step baru "Buang Benang" / divisi
-- BUANG_BENANG, tapi di DB aktual istilah yang dipakai adalah "Trim" -- workflow
-- TEMPLATE (workflow_template_steps) bahkan SUDAH duluan dipecah jadi "Sew + QC" +
-- "Trim" (divisi Trim, division_id 9) sebelum migrasi data ini dibuat. Artikel yang
-- SUDAH dibuat sebelum template diedit masih membawa snapshot lama gabungan
-- "Sew + Trim + QC" di article_workflows -- itulah yang di-split migrasi ini.
-- Karena template sudah dalam bentuk final, SECTION 2 di bawah akan otomatis 0
-- baris (tidak ada apa pun untuk diubah di template) -- itu BENAR, bukan bug.
--
-- MURNI MIGRASI DATA. Tidak ada perubahan kode C#/stored procedure/struktur tabel --
-- steps & divisi sepenuhnya data-driven (article_workflows/workflow_template_steps/
-- divisions), jadi script ini cukup INSERT/UPDATE data yang sudah ada.
--
-- Cara pakai:
--   1. BACKUP DATABASE dulu.
--   2. Jalankan SECTION 0 saja dulu, REVIEW hasilnya (lihat catatan per query) --
--      terutama pastikan @OldStepName di bawah cocok PERSIS dengan step_name aktual
--      di DB (query 0.1). Kalau nama bervariasi antar artikel, JANGAN lanjut --
--      konfirmasi dulu ke Ivander baru sesuaikan script.
--   3. Cek @MigrationUser (user id admin) di DECLARE bagian SECTION 1-5 di bawah.
--   4. Jalankan SECTION 1-5 (satu transaksi, auto-rollback kalau ada error).
--   5. Jalankan SECTION 6, bandingkan dengan hasil SECTION 0 (terutama 0.3 vs 6.6).
--   6. Station untuk divisi Trim -- cek dulu apakah sudah ada (divisi ini sudah lama
--      ada, division_id 9), kalau belum baru buat via UI Station Manage.
--
-- Idempotent: Section 1 (seed divisi, di sini sebenarnya cuma reuse divisi Trim yang
-- sudah ada) pakai IF NOT EXISTS. Section 2-5 mencocokkan baris lewat
-- step_name = @OldStepName -- begitu berhasil sekali, step itu berganti nama jadi
-- @NewOldName sehingga run kedua otomatis tidak menemukan apa pun (no-op).
-- Kegagalan di tengah jalan otomatis ROLLBACK seluruh Section 1-5 (satu transaksi),
-- jadi tidak pernah ada state setengah jalan yang tersimpan.
--
-- CLEANUP run percobaan sebelumnya: run pertama migrasi ini (sebelum ketahuan nama
-- step aktual beda) sempat membuat divisi nyasar 'BUANG_BENANG' (division_id 10)
-- yang TIDAK dipakai apa pun (Section 2-5 waktu itu 0 baris). Hapus dulu manual kalau
-- belum:
--   UPDATE divisions SET deleted_at = SYSDATETIME(), deleted_by = 1
--   WHERE division_code = 'BUANG_BENANG' AND deleted_at IS NULL;

SET NOCOUNT ON;

-- =====================================================================================
-- SECTION 0 -- variabel & verifikasi awal (READ-ONLY, jalankan & review dulu)
-- =====================================================================================

DECLARE @OldStepName   VARCHAR(150) = 'Sew + Trim + QC'; -- terkonfirmasi persis lewat query 0.1 (36 artikel)
DECLARE @NewOldName    VARCHAR(150) = 'Sew + QC';        -- sudah ada di template, samakan persis
DECLARE @NewStepName   VARCHAR(150) = 'Trim';             -- sudah ada di template, samakan persis
DECLARE @NewDivCode    VARCHAR(30)  = 'Trim';             -- divisi sudah ada (division_id 9), lihat query 0.1d
DECLARE @NewDivName    VARCHAR(150) = 'Trim';

-- 0.1: Semua step_name hidup di article_workflows + jumlah artikel/baris per nama --
-- WAJIB dicek @OldStepName di atas match PERSIS salah satu baris di sini.
SELECT aw.step_name, COUNT(DISTINCT aw.article_id) AS ArticleCount, COUNT(*) AS StepRowCount
FROM article_workflows aw
INNER JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
WHERE aw.deleted_at IS NULL
GROUP BY aw.step_name
ORDER BY aw.step_name;

-- 0.1b: sama untuk template (workflow_template_steps) -- semua workflow_template
-- hidup yang perlu diedit ikut Section 2.
SELECT wts.step_name, COUNT(*) AS TemplateStepCount
FROM workflow_template_steps wts
WHERE wts.deleted_at IS NULL
GROUP BY wts.step_name
ORDER BY wts.step_name;

-- 0.1c: pencarian fuzzy jaga-jaga ada variasi penulisan (typo/spasi) yang tidak
-- persis sama dengan @OldStepName tapi jelas dimaksudkan step yang sama.
SELECT DISTINCT aw.step_name, COUNT(*) OVER (PARTITION BY aw.step_name) AS Cnt
FROM article_workflows aw
WHERE aw.deleted_at IS NULL AND aw.step_name LIKE '%Trim%';

-- 0.1d: divisi yang dipakai step template 'Trim' yang sudah ada -- Section 1 HARUS
-- reuse divisi ini (jangan sampai bikin divisi baru terpisah).
SELECT wts.step_id, wts.workflow_template_id, wts.division_id, d.division_code, d.division_name,
       wts.sort_order, wts.requires_bundle
FROM workflow_template_steps wts
INNER JOIN divisions d ON d.division_id = wts.division_id
WHERE wts.step_name = 'Trim' AND wts.deleted_at IS NULL;

-- 0.2: artikel yang step lamanya adalah STEP TERAKHIR (perlakuan khusus Section 5).
SELECT aw.article_id, a.article_name, aw.step_name, aw.sort_order
FROM article_workflows aw
INNER JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
WHERE aw.deleted_at IS NULL AND aw.step_name = @OldStepName
  AND aw.sort_order = (
        SELECT MAX(aw2.sort_order) FROM article_workflows aw2
        WHERE aw2.article_id = aw.article_id AND aw2.deleted_at IS NULL
      )
ORDER BY a.article_name;

-- 0.3: snapshot posisi bundle (SIS_Report_BundleWip, semua project) -- SIMPAN/EXPORT
-- hasil ini, dibandingkan manual dengan query 6.6 yang identik setelah migrasi.
EXEC SIS_Report_BundleWip;

-- 0.3b: snapshot stock siap-packing per artikel/size (logika sama dengan
-- SIS_Pack_StockAvailable Prompt 25, digabung semua project sekaligus supaya tidak
-- perlu loop @ProjectId) -- SIMPAN/EXPORT, dibandingkan dengan query 6.6b setelah migrasi.
;WITH LastStep AS (
    SELECT a.article_id, a.project_id,
           (SELECT TOP 1 aw.article_workflow_id
            FROM article_workflows aw
            WHERE aw.article_id = a.article_id AND aw.deleted_at IS NULL
            ORDER BY aw.sort_order DESC) AS LastStepId
    FROM articles a WHERE a.deleted_at IS NULL
),
Done AS (
    SELECT ls.article_id AS ArticleId,
           COALESCE(awl.article_size_id, b.article_size_id) AS ArticleSizeId,
           SUM(awl.qty_ok) AS QtyDone
    FROM LastStep ls
    INNER JOIN article_workflow_logs awl ON awl.article_workflow_id = ls.LastStepId AND awl.deleted_at IS NULL
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    GROUP BY ls.article_id, COALESCE(awl.article_size_id, b.article_size_id)
),
Packed AS (
    SELECT pi.article_id AS ArticleId, pi.article_size_id AS ArticleSizeId,
           SUM(COALESCE(pi.qty_actual, pi.qty_plan)) AS QtyPacked
    FROM pack_items pi
    INNER JOIN packs p ON p.pack_id = pi.pack_id AND p.deleted_at IS NULL
    WHERE pi.deleted_at IS NULL
    GROUP BY pi.article_id, pi.article_size_id
)
SELECT a.project_id AS ProjectId, a.article_id AS ArticleId, a.article_name AS ArticleName,
       asz.article_size_id AS ArticleSizeId, spd.size_name AS SizeName,
       ISNULL(d.QtyDone, 0) AS QtyDone, ISNULL(pk.QtyPacked, 0) AS QtyPacked,
       ISNULL(d.QtyDone, 0) - ISNULL(pk.QtyPacked, 0) AS QtyAvailable
FROM article_sizes asz
INNER JOIN articles a ON a.article_id = asz.article_id AND a.deleted_at IS NULL
INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
LEFT JOIN Done d ON d.ArticleId = a.article_id AND d.ArticleSizeId = asz.article_size_id
LEFT JOIN Packed pk ON pk.ArticleId = a.article_id AND pk.ArticleSizeId = asz.article_size_id
WHERE asz.deleted_at IS NULL
ORDER BY a.project_id, a.article_name, spd.sort_order;
GO

-- =====================================================================================
-- SECTION 1-5 -- MIGRASI (satu transaksi, auto-rollback bila error)
-- =====================================================================================

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN;

    DECLARE @OldStepName   VARCHAR(150) = 'Sew + Trim + QC'; -- HARUS sama dgn Section 0
    DECLARE @NewOldName    VARCHAR(150) = 'Sew + QC';
    DECLARE @NewStepName   VARCHAR(150) = 'Trim';
    DECLARE @NewDivCode    VARCHAR(30)  = 'Trim';
    DECLARE @NewDivName    VARCHAR(150) = 'Trim';
    DECLARE @MigrationUser INT          = 1; -- user id admin (created_by/updated_by) -- CEK dulu ini benar id admin
    DECLARE @MigrationRemark VARCHAR(500) = N'Migrasi: pemisahan step Trim (Prompt 33)';
    DECLARE @AutoReceiveRemark VARCHAR(500) = N'Otomatis: migrasi pemisahan step';

    IF @MigrationUser IS NULL
    BEGIN
        RAISERROR('Isi dulu @MigrationUser (user id admin) sebelum menjalankan migrasi ini.', 16, 1);
        RETURN;
    END

    -- ===================== SECTION 1: seed divisi baru =====================
    DECLARE @NewDivisionId INT;

    IF NOT EXISTS (SELECT 1 FROM divisions WHERE division_code = @NewDivCode AND deleted_at IS NULL)
    BEGIN
        INSERT INTO divisions (division_code, division_name, created_at, created_by)
        VALUES (@NewDivCode, @NewDivName, SYSDATETIME(), @MigrationUser);
    END

    SELECT @NewDivisionId = division_id FROM divisions WHERE division_code = @NewDivCode AND deleted_at IS NULL;

    IF @NewDivisionId IS NULL
    BEGIN
        RAISERROR('Gagal membuat/menemukan divisi %s.', 16, 1, @NewDivCode);
        RETURN;
    END

    -- requires_bundle step baru ikut definisi step template 'Trim' yang sudah ada
    -- (bukan hardcode) -- kalau belum ada baris template yang cocok, fallback ke 1
    -- (requires_bundle, sesuai desain step ber-bundle Prompt 33).
    DECLARE @NewStepRequiresBundle BIT;
    SELECT TOP 1 @NewStepRequiresBundle = requires_bundle
    FROM workflow_template_steps
    WHERE step_name = @NewStepName AND division_id = @NewDivisionId AND deleted_at IS NULL;
    SET @NewStepRequiresBundle = ISNULL(@NewStepRequiresBundle, 1);

    -- ===================== SECTION 2: update workflow template =====================
    -- Tangkap dulu step template yang cocok SEBELUM di-rename (nama dipakai sbg kunci
    -- matching -- begitu di-rename run berikutnya otomatis 0 baris = idempotent).
    IF OBJECT_ID('tempdb..#tmpl_match') IS NOT NULL DROP TABLE #tmpl_match;
    SELECT step_id, workflow_template_id, sort_order AS old_sort_order
    INTO #tmpl_match
    FROM workflow_template_steps
    WHERE step_name = @OldStepName AND deleted_at IS NULL;

    -- 2.1: rename step lama -> Sew+QC
    UPDATE wts
    SET step_name = @NewOldName, updated_at = SYSDATETIME(), updated_by = @MigrationUser
    FROM workflow_template_steps wts
    INNER JOIN #tmpl_match m ON m.step_id = wts.step_id;

    -- 2.2: geser +1 sort_order step hidup template itu yang berada di atas step lama
    UPDATE wts
    SET sort_order = wts.sort_order + 1, updated_at = SYSDATETIME(), updated_by = @MigrationUser
    FROM workflow_template_steps wts
    INNER JOIN #tmpl_match m ON m.workflow_template_id = wts.workflow_template_id
    WHERE wts.deleted_at IS NULL AND wts.sort_order > m.old_sort_order;

    -- 2.3: insert step Trim tepat setelah Sew+QC (no-op di DB ini -- template sudah
    -- lebih dulu dipecah manual, #tmpl_match akan 0 baris, lihat catatan di header file)
    INSERT INTO workflow_template_steps (workflow_template_id, step_name, division_id, sort_order, requires_bundle, created_at, created_by)
    SELECT m.workflow_template_id, @NewStepName, @NewDivisionId, m.old_sort_order + 1, @NewStepRequiresBundle, SYSDATETIME(), @MigrationUser
    FROM #tmpl_match m;

    -- ===================== SECTION 3: update workflow artikel =====================
    -- Sama pola dengan Section 2, tapi per artikel (article_workflows) -- #step_map
    -- jadi kunci untuk Section 4/5 (per baris log, bukan lagi cari ulang lewat nama
    -- karena step lama sudah ganti nama setelah UPDATE di bawah).
    IF OBJECT_ID('tempdb..#step_map') IS NOT NULL DROP TABLE #step_map;
    SELECT article_workflow_id AS old_article_workflow_id, article_id,
           sort_order AS old_sort_order,
           CAST(NULL AS INT) AS new_article_workflow_id,
           CASE WHEN sort_order = (
                SELECT MAX(aw2.sort_order) FROM article_workflows aw2
                WHERE aw2.article_id = aw.article_id AND aw2.deleted_at IS NULL
           ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS is_last_step
    INTO #step_map
    FROM article_workflows aw
    WHERE step_name = @OldStepName AND deleted_at IS NULL;

    -- 3.1: rename step lama -> Sew+QC (per artikel)
    UPDATE aw
    SET step_name = @NewOldName, updated_at = SYSDATETIME(), updated_by = @MigrationUser
    FROM article_workflows aw
    INNER JOIN #step_map m ON m.old_article_workflow_id = aw.article_workflow_id;

    -- 3.2: resequence -- geser +1 step hidup artikel yang sama di atas step lama.
    -- (Step Bundling implisit selalu sebelum step ber-bundle pertama, jadi sort_order-nya
    -- selalu <= old_sort_order -- tidak pernah ikut tergeser di sini.)
    UPDATE aw
    SET sort_order = aw.sort_order + 1, updated_at = SYSDATETIME(), updated_by = @MigrationUser
    FROM article_workflows aw
    INNER JOIN #step_map m ON m.article_id = aw.article_id
    WHERE aw.deleted_at IS NULL AND aw.sort_order > m.old_sort_order;

    -- 3.3: insert step Trim per artikel, article_workflow_id baru ditangkap
    -- via OUTPUT lalu ditulis balik ke #step_map (dipakai Section 4/5).
    DECLARE @InsertedSteps TABLE (article_workflow_id INT, article_id INT);

    INSERT INTO article_workflows (article_id, workflow_template_id, step_name, division_id, sort_order, requires_bundle, is_bundling, created_at, created_by)
    OUTPUT inserted.article_workflow_id, inserted.article_id INTO @InsertedSteps(article_workflow_id, article_id)
    SELECT m.article_id, NULL, @NewStepName, @NewDivisionId, m.old_sort_order + 1, @NewStepRequiresBundle, 0, SYSDATETIME(), @MigrationUser
    FROM #step_map m;

    UPDATE m
    SET m.new_article_workflow_id = i.article_workflow_id
    FROM #step_map m
    INNER JOIN @InsertedSteps i ON i.article_id = m.article_id;

    -- ===================== SECTION 4/5: backfill log =====================
    -- Prinsip sama untuk kedua kelompok (non-step-terakhir & step-terakhir): baris
    -- BARU di Trim = "sisi keluar" (menyalin qty_ok, target & received APA
    -- ADANYA dari baris lama -- utk step terakhir dipaksa NULL, meniru konvensi step
    -- terakhir asli), baris LAMA di-update jadi "sisi masuk" ke Trim (target
    -- = divisi baru, auto-received kalau sebelumnya belum). Per BARIS (bukan per
    -- bundle) supaya baris susulan Prompt 14b ikut terbackfill masing-masing.

    -- 4a/5a: insert baris baru Trim -- non-step-terakhir menyalin sisi keluar
    -- baris lama apa adanya; step-terakhir dipaksa target/received NULL (step terakhir
    -- baru, konvensi SIS_WorkflowLog_Manage: target NULL = tidak pernah "diterima").
    INSERT INTO article_workflow_logs (
        article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
        qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_reject_rework, qty_lost,
        log_type, remark, received_at, received_by_resource_id, received_remark, target_division_id,
        created_at, created_by
    )
    SELECT
        m.new_article_workflow_id, awl.bundle_id, NULL, @NewDivisionId, NULL, NULL,
        awl.qty_ok, 0, 0, 0, 0, 0,
        'NORMAL', @MigrationRemark,
        CASE WHEN m.is_last_step = 1 THEN NULL ELSE awl.received_at END,
        CASE WHEN m.is_last_step = 1 THEN NULL ELSE awl.received_by_resource_id END,
        CASE WHEN m.is_last_step = 1 THEN NULL ELSE awl.received_remark END,
        CASE WHEN m.is_last_step = 1 THEN NULL ELSE awl.target_division_id END,
        SYSDATETIME(), @MigrationUser
    FROM article_workflow_logs awl
    INNER JOIN #step_map m ON m.old_article_workflow_id = awl.article_workflow_id
    WHERE awl.deleted_at IS NULL;

    -- 4b/5b: update baris lama -- jadi "sisi masuk" ke Trim. target_division_id
    -- selalu jadi divisi baru (baik dulu NULL/step-terakhir maupun sudah ada tujuan);
    -- received_at diisi otomatis (= created_at baris itu) kalau masih kosong, karena
    -- pekerjaannya dulu satu step (serah & terima dianggap sesaat). Baris yang SUDAH
    -- diterima (received_at NOT NULL, kasus non-step-terakhir) dibiarkan apa adanya.
    UPDATE awl
    SET target_division_id = @NewDivisionId,
        received_at = ISNULL(awl.received_at, awl.created_at),
        received_remark = CASE WHEN awl.received_at IS NULL THEN @AutoReceiveRemark ELSE awl.received_remark END,
        updated_at = SYSDATETIME(),
        updated_by = @MigrationUser
    FROM article_workflow_logs awl
    INNER JOIN #step_map m ON m.old_article_workflow_id = awl.article_workflow_id
    WHERE awl.deleted_at IS NULL;

    -- ===================== ringkasan pra-commit =====================
    DECLARE @TemplateStepsMatched INT = (SELECT COUNT(*) FROM #tmpl_match);
    DECLARE @ArticleStepsMatched INT = (SELECT COUNT(*) FROM #step_map);
    DECLARE @LastStepArticles INT = (SELECT COUNT(*) FROM #step_map WHERE is_last_step = 1);
    DECLARE @LogRowsBackfilled INT = (SELECT COUNT(*) FROM article_workflow_logs WHERE remark = @MigrationRemark AND deleted_at IS NULL);
    DECLARE @LogRowsOldTouched INT = (
        SELECT COUNT(*) FROM article_workflow_logs awl
        INNER JOIN #step_map m ON m.old_article_workflow_id = awl.article_workflow_id
        WHERE awl.deleted_at IS NULL
    );

    PRINT 'Divisi Trim: division_id = ' + CAST(@NewDivisionId AS VARCHAR(10));
    PRINT 'Template steps diubah (Section 2): ' + CAST(@TemplateStepsMatched AS VARCHAR(10));
    PRINT 'Article workflow steps diubah (Section 3): ' + CAST(@ArticleStepsMatched AS VARCHAR(10))
        + ' (step terakhir: ' + CAST(@LastStepArticles AS VARCHAR(10)) + ')';
    PRINT 'Baris log lama tersentuh (sisi masuk): ' + CAST(@LogRowsOldTouched AS VARCHAR(10));
    PRINT 'Baris log baru dibackfill ke Trim (sisi keluar): ' + CAST(@LogRowsBackfilled AS VARCHAR(10));
    IF @LogRowsOldTouched <> @LogRowsBackfilled
        PRINT 'PERINGATAN: jumlah sisi masuk vs sisi keluar TIDAK SAMA -- review sebelum percaya hasil migrasi ini.';

    COMMIT TRAN;
    PRINT 'Migrasi Prompt 33 selesai & di-COMMIT.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'Migrasi GAGAL, seluruh perubahan di-ROLLBACK. Detail error:';
    THROW;
END CATCH
GO

-- =====================================================================================
-- SECTION 6 -- verifikasi akhir (READ-ONLY, jalankan setelah COMMIT di atas)
-- =====================================================================================

DECLARE @OldStepName6   VARCHAR(150) = 'Sew + Trim + QC';
DECLARE @NewOldName6    VARCHAR(150) = 'Sew + QC';
DECLARE @MigrationUser6 INT          = 1; -- isi sama dengan @MigrationUser di atas
DECLARE @MigrationRemark6 VARCHAR(500) = N'Migrasi: pemisahan step Trim (Prompt 33)';

-- 6.1: tidak ada artikel hidup dengan step bernama step lama tersisa -- HARUS 0.
SELECT COUNT(*) AS SisaStepLama
FROM article_workflows aw
INNER JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
WHERE aw.deleted_at IS NULL AND aw.step_name = @OldStepName6;

-- 6.2: sort_order per artikel unik & berurutan tanpa lubang -- HARUS 0 baris.
;WITH Chk AS (
    SELECT aw.article_id, COUNT(*) AS Cnt, COUNT(DISTINCT aw.sort_order) AS DistinctCnt,
           MIN(aw.sort_order) AS MinSort, MAX(aw.sort_order) AS MaxSort
    FROM article_workflows aw
    INNER JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
    WHERE aw.deleted_at IS NULL
    GROUP BY aw.article_id
)
SELECT * FROM Chk
WHERE Cnt <> DistinctCnt OR (MaxSort - MinSort + 1) <> Cnt;

-- 6.3: jumlah baris backfill Trim vs jumlah baris hidup step lama (sisi
-- masuk, ditandai updated_by = @MigrationUser6 pada step Sew+QC) -- HARUS SAMA persis.
SELECT
    (SELECT COUNT(*) FROM article_workflow_logs WHERE remark = @MigrationRemark6 AND deleted_at IS NULL) AS BaruDiTrim,
    (
        SELECT COUNT(*) FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE aw.step_name = @NewOldName6 AND awl.deleted_at IS NULL AND awl.updated_by = @MigrationUser6
    ) AS LamaDiSewQC;

-- 6.4: tidak ada baris hidup step Sew+QC dengan received_at IS NULL (semua sudah
-- auto-received oleh Trim) -- HARUS 0 pada saat verifikasi tepat setelah
-- migrasi (setelahnya angka ini wajar > 0 seiring produksi baru berjalan normal).
SELECT COUNT(*) AS SewQcMasihPendingReceive
FROM article_workflow_logs awl
INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
WHERE aw.step_name = @NewOldName6 AND awl.deleted_at IS NULL AND awl.received_at IS NULL;

-- 6.5: sanity rantai -- tidak ada baris log hidup dengan target_division_id yang
-- bukan divisi step berikutnya bundle/artikelnya -- HARUS 0 baris.
SELECT awl.workflow_log_id, awl.article_workflow_id, awl.target_division_id, aw.article_id, aw.sort_order
FROM article_workflow_logs awl
INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
WHERE awl.deleted_at IS NULL AND awl.target_division_id IS NOT NULL
  AND awl.target_division_id <> (
        SELECT TOP 1 aw2.division_id FROM article_workflows aw2
        WHERE aw2.article_id = aw.article_id AND aw2.deleted_at IS NULL AND aw2.sort_order > aw.sort_order
        ORDER BY aw2.sort_order ASC
      );

-- 6.6: snapshot posisi bundle SESUDAH migrasi -- bandingkan manual dengan hasil 0.3.
-- Stock packing & posisi semua bundle TIDAK BOLEH berubah; baris yang tadinya
-- pending dari step gabungan kini tampil pending dari Trim menuju divisi
-- tujuan yang sama.
EXEC SIS_Report_BundleWip;

-- 6.6b: snapshot stock siap-packing SESUDAH migrasi -- bandingkan manual dengan 0.3b
-- (query identik).
;WITH LastStep AS (
    SELECT a.article_id, a.project_id,
           (SELECT TOP 1 aw.article_workflow_id
            FROM article_workflows aw
            WHERE aw.article_id = a.article_id AND aw.deleted_at IS NULL
            ORDER BY aw.sort_order DESC) AS LastStepId
    FROM articles a WHERE a.deleted_at IS NULL
),
Done AS (
    SELECT ls.article_id AS ArticleId,
           COALESCE(awl.article_size_id, b.article_size_id) AS ArticleSizeId,
           SUM(awl.qty_ok) AS QtyDone
    FROM LastStep ls
    INNER JOIN article_workflow_logs awl ON awl.article_workflow_id = ls.LastStepId AND awl.deleted_at IS NULL
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    GROUP BY ls.article_id, COALESCE(awl.article_size_id, b.article_size_id)
),
Packed AS (
    SELECT pi.article_id AS ArticleId, pi.article_size_id AS ArticleSizeId,
           SUM(COALESCE(pi.qty_actual, pi.qty_plan)) AS QtyPacked
    FROM pack_items pi
    INNER JOIN packs p ON p.pack_id = pi.pack_id AND p.deleted_at IS NULL
    WHERE pi.deleted_at IS NULL
    GROUP BY pi.article_id, pi.article_size_id
)
SELECT a.project_id AS ProjectId, a.article_id AS ArticleId, a.article_name AS ArticleName,
       asz.article_size_id AS ArticleSizeId, spd.size_name AS SizeName,
       ISNULL(d.QtyDone, 0) AS QtyDone, ISNULL(pk.QtyPacked, 0) AS QtyPacked,
       ISNULL(d.QtyDone, 0) - ISNULL(pk.QtyPacked, 0) AS QtyAvailable
FROM article_sizes asz
INNER JOIN articles a ON a.article_id = asz.article_id AND a.deleted_at IS NULL
INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
LEFT JOIN Done d ON d.ArticleId = a.article_id AND d.ArticleSizeId = asz.article_size_id
LEFT JOIN Packed pk ON pk.ArticleId = a.article_id AND pk.ArticleSizeId = asz.article_size_id
WHERE asz.deleted_at IS NULL
ORDER BY a.project_id, a.article_name, spd.sort_order;
GO

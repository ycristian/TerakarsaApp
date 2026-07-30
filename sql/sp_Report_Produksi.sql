-- Prompt 30: Laporan Produksi Periode Gajian -- READ-ONLY, tidak menulis apa pun ke database.
-- Periode gajian = [@PeriodStart, @PeriodEnd) — Sabtu 10:00 s/d Sabtu 10:00 berikutnya,
-- dihitung di client (tidak perlu SP daftar periode).
--
-- Definisi (WAJIB konsisten, lihat claude prompt/prompt_30_report_produksi.md):
-- "Log milik divisi" = article_workflow_logs.division_id = @DivisionId (step yang
-- MENGERJAKAN, bukan step tujuan).
--   - Qty Done   = SUM qty_ok, timing: target_division_id NOT NULL -> received_at dalam
--                  periode; target_division_id NULL (step terakhir) -> created_at dalam periode.
--   - Menunggu QC = SUM qty_ok, target_division_id NOT NULL, created_at < PeriodEnd DAN
--                  (received_at IS NULL OR received_at >= PeriodEnd) -- snapshot akhir periode.
--   - Reject     = Prompt 31 (2026-07-25), REVISI: sekarang SUM kelima kategori (qty_reject_print
--                  + qty_reject_fabric + qty_reject_sewing + qty_reject_rework + qty_lost), sama
--                  dengan sp_Article_Wip.sql -- Prompt 30 aslinya sengaja HANYA 3 kategori
--                  (print+fabric+sewing), tapi user minta breakdown lebih detail termasuk
--                  Hilang, jadi total Reject direvisi ikut 5 kategori supaya total = sum
--                  breakdown-nya sendiri (tidak ada kategori yang "hilang" dari total).
--                  Kelima kategori JUGA dikembalikan sebagai kolom terpisah (QtyRejectPrint,
--                  QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost) di kedua SP,
--                  timing SAMA dengan Qty Done (per kategori, bukan cuma totalnya).
--                  Prompt 36 (2026-07-29): tambah kolom RejectDetail (NVARCHAR) via STRING_AGG,
--                  ringkasan teks kategori yang qty > 0 saja mis. "Fabric: 7, Print: 2", urut
--                  qty terbesar dulu -- dipakai UI supaya tidak perlu 5 kolom terpisah lagi.
--                  Kolom breakdown per-kategori TETAP dikembalikan (dipakai client utk
--                  agregasi ulang di baris Total/ringkasan artikel yang dihitung di C#).
--   - WIP        = qty sudah diterima divisi ini tapi belum dicatat hasilnya, snapshot akhir
--                  periode, dihitung per step (article_workflow_id) milik divisi:
--                    Masuk    = SUM qty_ok log STEP SEBELUMNYA (predecessor dalam article yang
--                               sama) dengan target_division_id = @DivisionId, received_at < PeriodEnd.
--                    Tercatat = SUM(qty_ok + 5 kategori reject/lost) log STEP INI, created_at < PeriodEnd
--                               -- Prompt 31: diperluas dari 3 ke 5 kategori supaya konsisten dengan
--                               definisi Reject baru (bundle yg qty_lost/rework-nya sudah dicatat
--                               tidak lagi dihitung nyangkut di WIP selamanya).
--                    WIP = MAX(Masuk - Tercatat, 0). Step pertama (tanpa predecessor) -> tidak
--                    ada baris WIP.
--                  Desain (2026-07-24, tidak eksplisit di prompt): cabang perhitungan dipilih
--                  dari REQUIRES_BUNDLE PREDECESSOR, bukan step ini sendiri:
--                    - predecessor requires_bundle = 1 -> WIP dihitung PER BUNDLE (predecessor
--                      log sudah bundle_id-keyed, jadi bundle individual bisa dilacak: qty
--                      masuk per bundle - qty tercatat per bundle di step ini; Pelaksana =
--                      resource bawaan bundle, lihat poin Pelaksana di bawah -- BUKAN lagi
--                      received_by_resource_id predecessor, direvisi 2026-07-25).
--                    - predecessor requires_bundle = 0 ATAU predecessor tidak ada -> kalau
--                      predecessor tidak ada: TIDAK ADA WIP sama sekali (step awal workflow).
--                      Kalau predecessor ada tapi non-bundle (step ini = step Bundling implisit,
--                      ATAU dua step non-bundle berurutan): WIP dihitung PER SIZE
--                      (article_size_id) karena predecessor belum py bundle_id -- bundle-nya
--                      belum eksis. PelaksanaKey baris ini SELALU NULL ("Tanpa Nama") -- tidak
--                      ada bundle utk dijadikan rujukan employee_name/resource_id.
--                      SizeName step-ini (Tercatat) diambil dari cl.article_size_id kalau ada,
--                      atau dari bundles.article_size_id via cl.bundle_id (utk step Bundling,
--                      log-nya sendiri sudah bundle-keyed).
--   - Line/Resource (kolom pengelompokan) = bundles.resource_id via bundle_id. Log non-bundle
--     (bundle_id NULL) & baris WIP per-size -> grup "Tanpa Line" (LineResourceId NULL).
--   - Pelaksana (tab), REVISI 2026-07-25 (menggantikan definisi literal prompt "awl.resource_id"):
--     utk baris ber-bundle (DirectAtoms bundle_id NOT NULL, & BundleWip) SELALU pakai resource
--     BAWAAN BUNDLE -- ISNULL(employees.employee_name via bundles.employee_id, resources.resource_name
--     via bundles.resource_id) -- BUKAN article_workflow_logs.resource_id. Alasan (temuan user,
--     dikonfirmasi lewat query manual): stasiun step Sew+Trim+QC boleh cross-resource
--     (stations.allow_resource_change = 1), jadi awl.resource_id cuma mencatat resource mana
--     yg KEBETULAN dipakai login stasiun saat logging (bisa beda line), BUKAN siapa yg
--     sebenarnya bertanggung jawab atas bundle itu -- yg benar tetap resource bawaan bundle.
--     Utk baris TANPA bundle (step non-bundle, mis. Cutting -- tidak ada bundle rujukan),
--     tetap fallback ke resources.resource_name via awl.resource_id.
--     PelaksanaKey adalah TEKS (bukan resource_id int) supaya baris tanpa employee_id (fallback
--     ke resource_name Line) tetap bisa digabung/GROUP BY konsisten dengan baris ber-employee
--     (lihat SIS_Report_ProduksiDetail).
--     Prompt 32: employees.employee_name (via bundles.employee_id) diutamakan DI ATAS
--     resource_name Line -- fallback ke resource_name kalau employee_id NULL (bundle lama/belum
--     dipetakan ke master employee). Prompt 35: bundles.resource_person_name (fallback nama
--     lama, teks bebas) DIHAPUS dari rantai fallback ini -- kolom itu sudah direname jadi
--     bundles.remarks (catatan bebas, bukan identitas lagi), jadi bundle lama yang belum
--     dipetakan ke employee_id kini hanya tampil sebagai nama Line-nya di laporan ini.
--   - log_type ADJUSTMENT ikut disertakan tanpa filter khusus (SUM qty apa adanya) -- pola
--     yang sama seperti sp_Article_Wip.sql: baris ADJUSTMENT adalah mutasi netral (total 0)
--     antar kategori qty, jadi SUM biasa otomatis menghasilkan angka terkoreksi.
--
-- Agregat (SIS_Report_ProduksiAgg) dan detail (SIS_Report_ProduksiDetail) dihitung dari CTE
-- yang SAMA strukturnya (diduplikasi di masing-masing SP, bukan di-share -- pola yang sama
-- dengan sp_Report_Bundle.sql), hanya beda level GROUP BY akhir supaya totalnya selalu
-- konsisten satu sama lain.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Report_ProduksiAgg
    @DivisionId   INT,
    @ResourceId   INT = NULL,
    @PeriodStart  DATETIME2,
    @PeriodEnd    DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH StepPrev AS (
        SELECT
            aw.article_workflow_id,
            aw.article_id,
            aw.sort_order,
            (SELECT TOP 1 p.article_workflow_id FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_article_workflow_id,
            (SELECT TOP 1 p.requires_bundle FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_requires_bundle
        FROM article_workflows aw
        WHERE aw.deleted_at IS NULL AND aw.division_id = @DivisionId
    ),

    -- (A) Baris log nyata milik divisi -- kontribusi Qty Done / Menunggu QC / Reject (5 kategori).
    DirectAtoms AS (
        SELECT
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.resource_id ELSE NULL END AS LineResourceId,
            a.project_id AS PoId,
            aw.article_id AS ArticleId,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_ok ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_ok ELSE 0 END
            END AS QtyDone,
            CASE
                WHEN awl.target_division_id IS NOT NULL
                     AND awl.created_at < @PeriodEnd
                     AND (awl.received_at IS NULL OR awl.received_at >= @PeriodEnd)
                THEN awl.qty_ok ELSE 0
            END AS QtyMenungguQc,
            0 AS QtyWip,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_print ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_print ELSE 0 END
            END AS QtyRejectPrint,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_fabric ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_fabric ELSE 0 END
            END AS QtyRejectFabric,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_sewing ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_sewing ELSE 0 END
            END AS QtyRejectSewing,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_rework ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_rework ELSE 0 END
            END AS QtyRejectRework,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_lost ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_lost ELSE 0 END
            END AS QtyLost
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        INNER JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        WHERE awl.deleted_at IS NULL AND aw.division_id = @DivisionId
    ),

    -- (B) WIP per bundle -- predecessor step sudah bundle-keyed.
    BundleMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.bundle_id AS BundleId,
               SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL
           AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd
           AND pl.bundle_id IS NOT NULL
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, pl.bundle_id
    ),
    BundleTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, cl.bundle_id AS BundleId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, cl.bundle_id
    ),
    BundleWip AS (
        SELECT
            b.resource_id AS LineResourceId,
            a.project_id AS PoId,
            a.article_id AS ArticleId,
            0 AS QtyDone, 0 AS QtyMenungguQc,
            CASE WHEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0 THEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) ELSE 0 END AS QtyWip,
            0 AS QtyRejectPrint, 0 AS QtyRejectFabric, 0 AS QtyRejectSewing, 0 AS QtyRejectRework, 0 AS QtyLost
        FROM BundleMasuk bm
        LEFT JOIN BundleTercatat bt ON bt.StepArticleWorkflowId = bm.StepArticleWorkflowId AND bt.BundleId = bm.BundleId
        INNER JOIN bundles b ON b.bundle_id = bm.BundleId AND b.deleted_at IS NULL
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        WHERE (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0
    ),

    -- (C) WIP per size -- predecessor non-bundle (mis. step Bundling menerima dari Cutting).
    SizeMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.article_size_id AS ArticleSizeId,
               SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, pl.article_size_id
    ),
    SizeTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId,
               ISNULL(cl.article_size_id, bb.article_size_id) AS ArticleSizeId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        LEFT JOIN bundles bb ON bb.bundle_id = cl.bundle_id AND bb.deleted_at IS NULL
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, ISNULL(cl.article_size_id, bb.article_size_id)
    ),
    SizeWip AS (
        SELECT
            CAST(NULL AS INT) AS LineResourceId,
            a.project_id AS PoId,
            asz.article_id AS ArticleId,
            0 AS QtyDone, 0 AS QtyMenungguQc,
            CASE WHEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0 THEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) ELSE 0 END AS QtyWip,
            0 AS QtyRejectPrint, 0 AS QtyRejectFabric, 0 AS QtyRejectSewing, 0 AS QtyRejectRework, 0 AS QtyLost
        FROM SizeMasuk sm
        LEFT JOIN SizeTercatat st ON st.StepArticleWorkflowId = sm.StepArticleWorkflowId AND st.ArticleSizeId = sm.ArticleSizeId
        INNER JOIN article_sizes asz ON asz.article_size_id = sm.ArticleSizeId
        INNER JOIN articles a ON a.article_id = asz.article_id AND a.deleted_at IS NULL
        WHERE (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0
    ),

    Atoms AS (
        SELECT LineResourceId, PoId, ArticleId, QtyDone, QtyMenungguQc, QtyWip,
               QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost
        FROM DirectAtoms
        UNION ALL
        SELECT LineResourceId, PoId, ArticleId, QtyDone, QtyMenungguQc, QtyWip,
               QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost
        FROM BundleWip
        UNION ALL
        SELECT LineResourceId, PoId, ArticleId, QtyDone, QtyMenungguQc, QtyWip,
               QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost
        FROM SizeWip
    )

    -- Prompt 36: RG = agregat mentah (sama seperti sebelumnya), lalu di-CROSS APPLY ke
    -- STRING_AGG supaya breakdown 5 kategori reject tampil sbg satu kolom teks ringkas
    -- ("Fabric: 7, Print: 2") -- menggantikan 5 kolom terpisah yang bikin tabel kebanyakan
    -- kolom (kategori dgn qty 0 disembunyikan, diurutkan qty terbesar dulu).
    RG AS (
        SELECT
            t.LineResourceId,
            ISNULL(lr.resource_name, N'Tanpa Line') AS LineResourceName,
            t.PoId,
            p.no_po AS PoNumber,
            p.project_name AS PoName,
            t.ArticleId,
            ar.article_name AS ArticleName,
            SUM(t.QtyDone) AS QtyDone,
            SUM(t.QtyMenungguQc) AS QtyMenungguQc,
            SUM(t.QtyWip) AS QtyWip,
            SUM(t.QtyRejectPrint) AS QtyRejectPrint,
            SUM(t.QtyRejectFabric) AS QtyRejectFabric,
            SUM(t.QtyRejectSewing) AS QtyRejectSewing,
            SUM(t.QtyRejectRework) AS QtyRejectRework,
            SUM(t.QtyLost) AS QtyLost,
            SUM(t.QtyRejectPrint + t.QtyRejectFabric + t.QtyRejectSewing + t.QtyRejectRework + t.QtyLost) AS QtyReject
        FROM Atoms t
        INNER JOIN projects p ON p.project_id = t.PoId AND p.deleted_at IS NULL
        INNER JOIN articles ar ON ar.article_id = t.ArticleId
        LEFT JOIN resources lr ON lr.resource_id = t.LineResourceId
        WHERE (@ResourceId IS NULL OR t.LineResourceId = @ResourceId)
        GROUP BY t.LineResourceId, ISNULL(lr.resource_name, N'Tanpa Line'), t.PoId, p.no_po, p.project_name, t.ArticleId, ar.article_name
        HAVING SUM(t.QtyDone) > 0 OR SUM(t.QtyMenungguQc) > 0 OR SUM(t.QtyWip) > 0
            OR SUM(t.QtyRejectPrint + t.QtyRejectFabric + t.QtyRejectSewing + t.QtyRejectRework + t.QtyLost) > 0
    )

    SELECT
        g.LineResourceId, g.LineResourceName, g.PoId, g.PoNumber, g.PoName, g.ArticleId, g.ArticleName,
        g.QtyDone, g.QtyMenungguQc, g.QtyWip,
        g.QtyRejectPrint, g.QtyRejectFabric, g.QtyRejectSewing, g.QtyRejectRework, g.QtyLost, g.QtyReject,
        rd.RejectDetail
    FROM RG g
    CROSS APPLY (
        SELECT STRING_AGG(CONCAT(v.Label, N': ', v.Qty), N', ') WITHIN GROUP (ORDER BY v.Qty DESC) AS RejectDetail
        FROM (VALUES
            (N'Print', g.QtyRejectPrint), (N'Fabric', g.QtyRejectFabric), (N'Sewing', g.QtyRejectSewing),
            (N'Rework', g.QtyRejectRework), (N'Hilang', g.QtyLost)
        ) AS v(Label, Qty)
        WHERE v.Qty > 0
    ) rd
    ORDER BY g.LineResourceName, g.PoNumber, g.ArticleName;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Report_ProduksiDetail
    @DivisionId   INT,
    @ResourceId   INT = NULL,
    @PeriodStart  DATETIME2,
    @PeriodEnd    DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH StepPrev AS (
        SELECT
            aw.article_workflow_id,
            aw.article_id,
            aw.sort_order,
            (SELECT TOP 1 p.article_workflow_id FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_article_workflow_id,
            (SELECT TOP 1 p.requires_bundle FROM article_workflows p
             WHERE p.article_id = aw.article_id AND p.deleted_at IS NULL AND p.sort_order < aw.sort_order
             ORDER BY p.sort_order DESC) AS prev_requires_bundle
        FROM article_workflows aw
        WHERE aw.deleted_at IS NULL AND aw.division_id = @DivisionId
    ),

    -- PelaksanaKey (2026-07-25, revisi): utk baris ber-bundle SELALU ikut resource bawaan
    -- bundle (bundles.resource_id/employee_id) -- BUKAN awl.resource_id. Alasan:
    -- station SW+Trim+QC boleh cross-resource (stations.allow_resource_change = 1), jadi
    -- awl.resource_id cuma mencatat resource mana yg KEBETULAN dipakai login stasiun saat
    -- itu, bukan siapa yg benar-benar bertanggung jawab atas bundle tsb -- yg benar tetap
    -- resource bawaan si bundle. awl.resource_id cuma dipakai sbg fallback utk baris TANPA
    -- bundle (step non-bundle, mis. Cutting -- tidak ada bundle utk dijadikan rujukan).
    -- PelaksanaKey adalah TEKS (bukan resource_id int) supaya baris ber-employee & baris
    -- fallback-ke-Line tetap bisa digabung satu tab lewat GROUP BY nama yang sama.
    DirectAtoms AS (
        SELECT
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.resource_id ELSE NULL END AS LineResourceId,
            -- Prompt 32: employee_name (master employees) diutamakan di atas resource_name Line.
            -- Prompt 35: fallback ke resource_person_name (teks bebas lama) DIHAPUS -- kolom itu
            -- sudah jadi bundles.remarks (bukan identitas lagi).
            CASE WHEN awl.bundle_id IS NOT NULL
                     THEN ISNULL(ben.employee_name, brn.resource_name)
                 ELSE arn.resource_name
            END AS PelaksanaKey,
            a.project_id AS PoId,
            aw.article_id AS ArticleId,
            awl.bundle_id AS BundleId,
            b.bundle_no AS BundleNo,
            b.serial AS BundleSerial,
            CASE WHEN awl.bundle_id IS NOT NULL THEN b.article_size_id ELSE awl.article_size_id END AS ArticleSizeId,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_ok ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_ok ELSE 0 END
            END AS QtyDone,
            CASE
                WHEN awl.target_division_id IS NOT NULL
                     AND awl.created_at < @PeriodEnd
                     AND (awl.received_at IS NULL OR awl.received_at >= @PeriodEnd)
                THEN awl.qty_ok ELSE 0
            END AS QtyMenungguQc,
            0 AS QtyWip,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_print ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_print ELSE 0 END
            END AS QtyRejectPrint,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_fabric ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_fabric ELSE 0 END
            END AS QtyRejectFabric,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_sewing ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_sewing ELSE 0 END
            END AS QtyRejectSewing,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_reject_rework ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_reject_rework ELSE 0 END
            END AS QtyRejectRework,
            CASE
                WHEN awl.target_division_id IS NULL
                    THEN CASE WHEN awl.created_at >= @PeriodStart AND awl.created_at < @PeriodEnd THEN awl.qty_lost ELSE 0 END
                ELSE CASE WHEN awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd THEN awl.qty_lost ELSE 0 END
            END AS QtyLost
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        INNER JOIN articles a ON a.article_id = aw.article_id AND a.deleted_at IS NULL
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        LEFT JOIN resources brn ON brn.resource_id = b.resource_id     -- nama Line bundle (fallback Pelaksana bundle)
        LEFT JOIN resources arn ON arn.resource_id = awl.resource_id   -- nama resource log (Pelaksana baris non-bundle)
        LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL  -- Prompt 32
        WHERE awl.deleted_at IS NULL AND aw.division_id = @DivisionId
    ),

    BundleMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.bundle_id AS BundleId,
               SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL
           AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd
           AND pl.bundle_id IS NOT NULL
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, pl.bundle_id
    ),
    BundleTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, cl.bundle_id AS BundleId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 1
        GROUP BY s.article_workflow_id, cl.bundle_id
    ),
    BundleWip AS (
        SELECT
            b.resource_id AS LineResourceId,
            -- Prompt 32/35: employee_name diutamakan di atas resource_name Line (lihat DirectAtoms).
            ISNULL(ben.employee_name, brn.resource_name) AS PelaksanaKey,
            a.project_id AS PoId,
            a.article_id AS ArticleId,
            b.bundle_id AS BundleId,
            b.bundle_no AS BundleNo,
            b.serial AS BundleSerial,
            b.article_size_id AS ArticleSizeId,
            0 AS QtyDone, 0 AS QtyMenungguQc,
            CASE WHEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0 THEN (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) ELSE 0 END AS QtyWip,
            0 AS QtyRejectPrint, 0 AS QtyRejectFabric, 0 AS QtyRejectSewing, 0 AS QtyRejectRework, 0 AS QtyLost
        FROM BundleMasuk bm
        LEFT JOIN BundleTercatat bt ON bt.StepArticleWorkflowId = bm.StepArticleWorkflowId AND bt.BundleId = bm.BundleId
        INNER JOIN bundles b ON b.bundle_id = bm.BundleId AND b.deleted_at IS NULL
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        LEFT JOIN resources brn ON brn.resource_id = b.resource_id
        LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL
        WHERE (bm.MasukQty - ISNULL(bt.TercatatQty, 0)) > 0
    ),

    SizeMasuk AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId, pl.article_size_id AS ArticleSizeId,
               SUM(pl.qty_ok) AS MasukQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs pl
            ON pl.article_workflow_id = s.prev_article_workflow_id
           AND pl.deleted_at IS NULL AND pl.target_division_id = @DivisionId
           AND pl.received_at IS NOT NULL AND pl.received_at < @PeriodEnd
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, pl.article_size_id
    ),
    SizeTercatat AS (
        SELECT s.article_workflow_id AS StepArticleWorkflowId,
               ISNULL(cl.article_size_id, bb.article_size_id) AS ArticleSizeId,
               SUM(cl.qty_ok + cl.qty_reject_print + cl.qty_reject_fabric + cl.qty_reject_sewing
                   + cl.qty_reject_rework + cl.qty_lost) AS TercatatQty
        FROM StepPrev s
        INNER JOIN article_workflow_logs cl
            ON cl.article_workflow_id = s.article_workflow_id
           AND cl.deleted_at IS NULL AND cl.created_at < @PeriodEnd
        LEFT JOIN bundles bb ON bb.bundle_id = cl.bundle_id AND bb.deleted_at IS NULL
        WHERE s.prev_requires_bundle = 0
        GROUP BY s.article_workflow_id, ISNULL(cl.article_size_id, bb.article_size_id)
    ),
    SizeWip AS (
        SELECT
            CAST(NULL AS INT) AS LineResourceId,
            CAST(NULL AS VARCHAR(150)) AS PelaksanaKey,
            a.project_id AS PoId,
            asz.article_id AS ArticleId,
            CAST(NULL AS INT) AS BundleId,
            CAST(NULL AS INT) AS BundleNo,
            CAST(NULL AS VARCHAR(20)) AS BundleSerial,
            asz.article_size_id AS ArticleSizeId,
            0 AS QtyDone, 0 AS QtyMenungguQc,
            CASE WHEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0 THEN (sm.MasukQty - ISNULL(st.TercatatQty, 0)) ELSE 0 END AS QtyWip,
            0 AS QtyRejectPrint, 0 AS QtyRejectFabric, 0 AS QtyRejectSewing, 0 AS QtyRejectRework, 0 AS QtyLost
        FROM SizeMasuk sm
        LEFT JOIN SizeTercatat st ON st.StepArticleWorkflowId = sm.StepArticleWorkflowId AND st.ArticleSizeId = sm.ArticleSizeId
        INNER JOIN article_sizes asz ON asz.article_size_id = sm.ArticleSizeId
        INNER JOIN articles a ON a.article_id = asz.article_id AND a.deleted_at IS NULL
        WHERE (sm.MasukQty - ISNULL(st.TercatatQty, 0)) > 0
    ),

    Atoms AS (
        SELECT LineResourceId, PelaksanaKey, PoId, ArticleId, BundleId, BundleNo, BundleSerial, ArticleSizeId,
               QtyDone, QtyMenungguQc, QtyWip, QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost
        FROM DirectAtoms
        UNION ALL
        SELECT LineResourceId, PelaksanaKey, PoId, ArticleId, BundleId, BundleNo, BundleSerial, ArticleSizeId,
               QtyDone, QtyMenungguQc, QtyWip, QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost
        FROM BundleWip
        UNION ALL
        SELECT LineResourceId, PelaksanaKey, PoId, ArticleId, BundleId, BundleNo, BundleSerial, ArticleSizeId,
               QtyDone, QtyMenungguQc, QtyWip, QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost
        FROM SizeWip
    )

    -- PelaksanaName = ISNULL(t.PelaksanaKey, 'Tanpa Nama'). PelaksanaKey sudah dihitung
    -- final per-atom di tiap CTE (bukan agregat) -- baris ber-bundle SELALU dari resource
    -- bawaan bundle (employee_name lalu resource_name Line-nya), baris tanpa bundle
    -- dari resource_name log itu sendiri. Identitas Pelaksana berbasis TEKS (bukan
    -- resource_id) supaya baris ber-employee & baris fallback-ke-Line tetap bisa satu tab.
    -- Prompt 36: RD = agregat mentah per bundle/size (sama seperti sebelumnya), lalu
    -- di-CROSS APPLY ke STRING_AGG -- lihat catatan yang sama di SIS_Report_ProduksiAgg.
    RD AS (
        SELECT
            t.LineResourceId,
            ISNULL(lr.resource_name, N'Tanpa Line') AS LineResourceName,
            ISNULL(t.PelaksanaKey, N'Tanpa Nama') AS PelaksanaName,
            t.PoId,
            p.no_po AS PoNumber,
            p.project_name AS PoName,
            t.ArticleId,
            ar.article_name AS ArticleName,
            t.BundleId,
            t.BundleNo,
            t.BundleSerial,
            ISNULL(spd.size_name, N'-') AS SizeName,
            SUM(t.QtyDone) AS QtyDone,
            SUM(t.QtyMenungguQc) AS QtyMenungguQc,
            SUM(t.QtyWip) AS QtyWip,
            SUM(t.QtyRejectPrint) AS QtyRejectPrint,
            SUM(t.QtyRejectFabric) AS QtyRejectFabric,
            SUM(t.QtyRejectSewing) AS QtyRejectSewing,
            SUM(t.QtyRejectRework) AS QtyRejectRework,
            SUM(t.QtyLost) AS QtyLost,
            SUM(t.QtyRejectPrint + t.QtyRejectFabric + t.QtyRejectSewing + t.QtyRejectRework + t.QtyLost) AS QtyReject
        FROM Atoms t
        INNER JOIN projects p ON p.project_id = t.PoId AND p.deleted_at IS NULL
        INNER JOIN articles ar ON ar.article_id = t.ArticleId
        LEFT JOIN resources lr ON lr.resource_id = t.LineResourceId
        LEFT JOIN article_sizes asz ON asz.article_size_id = t.ArticleSizeId
        LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE (@ResourceId IS NULL OR t.LineResourceId = @ResourceId)
        GROUP BY t.LineResourceId, ISNULL(lr.resource_name, N'Tanpa Line'),
                 ISNULL(t.PelaksanaKey, N'Tanpa Nama'),
                 t.PoId, p.no_po, p.project_name, t.ArticleId, ar.article_name,
                 t.BundleId, t.BundleNo, t.BundleSerial, ISNULL(spd.size_name, N'-')
        HAVING SUM(t.QtyDone) > 0 OR SUM(t.QtyMenungguQc) > 0 OR SUM(t.QtyWip) > 0
            OR SUM(t.QtyRejectPrint + t.QtyRejectFabric + t.QtyRejectSewing + t.QtyRejectRework + t.QtyLost) > 0
    )

    SELECT
        g.LineResourceId, g.LineResourceName, g.PelaksanaName, g.PoId, g.PoNumber, g.PoName,
        g.ArticleId, g.ArticleName, g.BundleId, g.BundleNo, g.BundleSerial, g.SizeName,
        g.QtyDone, g.QtyMenungguQc, g.QtyWip,
        g.QtyRejectPrint, g.QtyRejectFabric, g.QtyRejectSewing, g.QtyRejectRework, g.QtyLost, g.QtyReject,
        rd.RejectDetail
    FROM RD g
    CROSS APPLY (
        SELECT STRING_AGG(CONCAT(v.Label, N': ', v.Qty), N', ') WITHIN GROUP (ORDER BY v.Qty DESC) AS RejectDetail
        FROM (VALUES
            (N'Print', g.QtyRejectPrint), (N'Fabric', g.QtyRejectFabric), (N'Sewing', g.QtyRejectSewing),
            (N'Rework', g.QtyRejectRework), (N'Hilang', g.QtyLost)
        ) AS v(Label, Qty)
        WHERE v.Qty > 0
    ) rd
    ORDER BY g.LineResourceName, g.PelaksanaName, g.PoNumber, g.ArticleName, g.BundleNo;
END;
GO

-- Dropdown filter Resource (Line) di halaman /reports/produksi: resource hidup divisi
-- terpilih yang PERNAH jadi bundles.resource_id (bukan sekadar resource aktif divisi --
-- endpoint active-by-division/{id} sudah ada tapi digate module MASTER_RESOURCE, tidak cocok
-- utk user yang hanya punya REPORT_PRODUKSI).
CREATE OR ALTER PROCEDURE SIS_Report_ProduksiResources
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT r.resource_id AS Id, r.resource_name AS ResourceName
    FROM resources r
    WHERE r.division_id = @DivisionId AND r.deleted_at IS NULL
      AND EXISTS (
          SELECT 1 FROM bundles b WHERE b.resource_id = r.resource_id AND b.deleted_at IS NULL
      )
    ORDER BY r.resource_name ASC;
END;
GO

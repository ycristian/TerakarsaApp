-- Query operasional untuk halaman stasiun (/station), semua berbasis @DivisionId
-- (divisi diambil dari token perangkat, lihat SIS_Station_GetByToken).
-- Lookup resource aktif per divisi pakai SP yang sudah ada: SIS_Resource_GetActiveByDivision.
--
-- Model log Prompt 12b (1 baris per serah-terima, tanpa kolom status):
--   SIS_Station_PendingReceives: sederhana sekali -- baris hidup mana pun (level artikel
--   maupun per-bundle) dengan target_division_id = @DivisionId dan received_at IS NULL.
--   Menerima baris ini artinya update received_at/received_by_resource_id (action RECEIVE
--   di SIS_WorkflowLog_Manage), memakai workflow_log_id, bukan lagi article_workflow_id.
--
--   SIS_Station_ActiveWork: step non-bundle (requires_bundle = 0) milik divisi ini -- tampil
--   untuk artikel yang project-nya masih aktif (manual_status bukan COMPLETED/CANCELLED,
--   sama seperti sp_Report_DivisionWip.sql) DAN sudah berstatus STARTED/ON_GOING/ON_HOLD
--   (derived_status bukan NOT_STARTED -- lihat sp_Project_Select.sql: manual_status terisi,
--   ATAU start_date sudah tiba/lewat, ATAU project sudah punya log workflow), bukan antrian
--   sekali-pakai (baris non-bundle bebas dicatat berulang kapan pun, lihat komentar di
--   sp_WorkflowLog_Manage.sql). Kartu "Buat Bundle" (is_bundling = 1, Prompt 24) di UNION
--   ALL kedua ikut gate yang sama -- project yang belum dimulai belum boleh mulai bundling.
--   Prompt 23: dihidupkan lagi sebagai sumber kartu permanen (artikel x step) di tab WIP --
--   sejak 12c sempat tak terpakai. Daftar ukuran (FOR JSON) kini menyertakan qty_order
--   (article_sizes.qty) + total qty_ok tercatat step ini per ukuran, supaya client bisa
--   menampilkan grid Kirim Hasil (kolom Order/Tercatat) tanpa round-trip tambahan.
--
--   SIS_Station_PendingHandover: kebalikan dari PendingReceives -- baris yang DIBUAT oleh
--   divisi ini sendiri (division_id = @DivisionId), sudah punya tujuan serah, tapi BELUM
--   diterima divisi tujuan (received_at IS NULL). Selama belum diterima, divisi pembuat
--   masih boleh merevisi datanya (action UPDATE di SIS_WorkflowLog_Manage) -- begitu
--   diterima (received_at terisi lewat RECEIVE), baris terkunci dan hilang dari daftar ini.
--   Prompt 23: SEKARANG juga menyertakan baris step TERAKHIR artikel milik divisi ini
--   (target_division_id NULL, tidak ada tujuan serah -- lihat SIS_Bundle_ScanInfo) selama
--   masih dalam jendela revisi H+1 (hari dibuat + 1 hari kalender), supaya operator bisa
--   menemukan & membetulkan baris itu dari tab OUT tanpa perlu scan ulang QR bundle.
--   IsLastStep membedakan kasus ini di hasil -- baris IsLastStep = 1 TIDAK punya tujuan
--   serah untuk direvisi (client harus sembunyikan field Divisi Tujuan/Penjahit & tombol
--   Batal Serah, pakai UPDATE biasa bukan REVISE_HANDOVER).
--
--   SIS_Station_RecentReceived (Prompt 15): 20 baris terakhir yang DITERIMA divisi ini
--   (target_division_id = @DivisionId, received_at NOT NULL) -- dasar tab "Baru Diterima"
--   dan tombol batal terima (action UNRECEIVE di SIS_WorkflowLog_Manage). CanUnreceive
--   mencerminkan pemeriksaan step-berikutnya yang sama dipakai UNRECEIVE, supaya tombol
--   bisa dinonaktifkan di UI tanpa round-trip tambahan.
--
-- Prompt 12e -- redesign kiosk /station jadi 3 status (Masuk/Dikerjakan/Dikirim):
--   SIS_Station_InProgress: bundle status "Dikerjakan" di divisi ini -- definisi identik
--   dengan status DIKERJAKAN di sp_Report_Bundle.sql (baris log TERAKHIR hidup bundle:
--   received_at IS NOT NULL DAN target_division_id = @DivisionId, artinya belum ada baris
--   step berikutnya). TANPA TOP -- ini queue kerja utama operator, bukan riwayat.
--   WorkflowLogId di sini = baris yang DITERIMA (dipakai utk Batal Terima/UNRECEIVE).
--   NextArticleWorkflowId/NextStepName = step ber-bundle berikutnya yang harus diselesaikan
--   (dipakai sebagai @ArticleWorkflowId saat submit Serahkan lewat endpoint complete existing,
--   action CREATE di SIS_WorkflowLog_Manage -- TIDAK ada endpoint/SP baru utk Serahkan itu
--   sendiri). NextDivisionName = tujuan serah berikutnya (murni informasi, dikunci ulang
--   oleh server saat submit, sama seperti SIS_Bundle_ScanInfo).
--
--   SIS_Station_Counts: 3 angka (Masuk/Dikerjakan/Dikirim) utk strip kartu angka besar di
--   atas /station. Masuk & Dikirim pakai definisi yang sama dengan SIS_Station_PendingReceives
--   & SIS_Station_PendingHandover (level baris log, boleh bundle atau non-bundle); Dikerjakan
--   pakai definisi yang sama dengan SIS_Station_InProgress (level bundle).
--
--   Tab "Dikirim" (dulu "Diserahkan") memakai ULANG SIS_Station_PendingHandover -- sejak
--   Prompt 23 juga menampilkan baris step terakhir (H+1, lihat komentar di atas), bukan
--   lagi cuma baris yang ada tujuan serah. Tidak dibuat SP SIS_Station_Outbound terpisah
--   supaya tidak duplikasi logika.
--
--   Prompt 23: SIS_Station_InProgress kini juga menyertakan style/color artikel (murni data
--   tambahan, tidak mengubah alur kartu bundle) supaya pencarian teks WAJIB di tab WIP bisa
--   menyaring kartu bundle dan kartu non-bundle dengan field yang sama. SIS_Station_Counts
--   DikerjakanCount kini menjumlahkan kartu bundle (definisi SIS_Station_InProgress) DENGAN
--   kartu non-bundle (definisi SIS_Station_ActiveWork), supaya angka WIP di strip atas
--   konsisten dengan isi tab gabungan.
--
-- Prompt 24: SIS_Station_ActiveWork sekarang UNION dua sumber kartu WIP -- step non-bundle
--   (IsBundling = 0, seperti sebelumnya) DAN step Bundling implisit (is_bundling = 1,
--   IsBundling = 1) milik @DivisionId, yaitu kartu "Buat Bundle" di station divisi Bundling.
--   Baris IsBundling = 1 TIDAK membawa SizesJson (detail per size diambil client lewat
--   SIS_Article_BundleSummary saat modal dibuka) -- sebagai gantinya bawa ringkasan
--   BundleCount/TotalBundleQty/TotalOrderQty untuk teks ringkas di kartu. SIS_Station_Counts
--   DikerjakanCount diperluas sejalan (requires_bundle = 0 OR is_bundling = 1).
--   SIS_Station_PendingHandover kini juga membawa ArticleId, IsBundling, dan data penjahit
--   bundle (BundleResourceId/BundleResourceName/BundleResourcePersonName, DIBEDAKAN dari
--   ResourceName yang di baris Bundling berarti pelaksana BUNDLING, bukan penjahit) --
--   dipakai tombol Edit bundle di tab OUT (menggantikan Revisi/Batal Serah utk baris ini).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Station_PendingReceives
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: default_resource_id stasiun (NULL = stasiun
                                -- tidak terkunci ke Line manapun, lihat SIS_Station_Counts)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT awl.workflow_log_id AS WorkflowLogId, awl.article_workflow_id AS ArticleWorkflowId,
           p.project_name AS ProjectName, a.article_name AS ArticleName,
           a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
           awl.qty_ok AS QtyOk, awl.created_at AS SentAt,
           d.division_name AS FromDivisionName,
           awl.bundle_id AS BundleId, b.bundle_no AS BundleNo, b.serial AS Serial,
           spd.size_name AS SizeName,
           awl.updated_at AS UpdatedAt
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN resources br ON br.resource_id = b.resource_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE awl.target_division_id = @DivisionId
      AND awl.received_at IS NULL
      AND awl.deleted_at IS NULL
      -- Prompt 22b: stasiun terkunci ke satu Line (resource) hanya melihat bundle yang
      -- ditugaskan ke Line itu; item non-bundle atau bundle tanpa Line, dan stasiun yang
      -- tidak terkunci (@ResourceId NULL), tetap tampil seperti sebelumnya.
      -- Fix: Line hanya relevan kalau resource Line itu SATU DIVISI dengan stasiun ini
      -- (mis. Line A1/A2 sama-sama di Sew+Trim+QC) -- di situ splitting antar Line
      -- memang dimaksudkan. Kalau Line bundle beda divisi dari stasiun ini (mis. bundle
      -- ditugaskan ke Line A1 tapi sedang menuju stasiun DTF/Packing yang dikunci ke
      -- resource "Team"-nya sendiri, bukan Line), filter Line tidak relevan -- jangan
      -- disembunyikan, karena resource stasiun tujuan memang tidak akan pernah sama
      -- dengan Line pengirim.
      AND (@ResourceId IS NULL OR b.resource_id IS NULL OR b.resource_id = @ResourceId OR br.division_id <> @DivisionId)
    ORDER BY awl.created_at ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_ActiveWork
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT * FROM (
        SELECT aw.article_workflow_id AS ArticleWorkflowId,
               a.article_id AS ArticleId,
               p.project_name AS ProjectName, a.article_name AS ArticleName,
               a.style AS Style, a.color AS Color,
               aw.step_name AS StepName,
               CAST(0 AS BIT) AS IsBundling,
               CASE WHEN aw.sort_order = (
                   SELECT MAX(aw3.sort_order) FROM article_workflows aw3
                   WHERE aw3.article_id = aw.article_id AND aw3.deleted_at IS NULL
               ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep,
               (
                   SELECT TOP 1 aw4.division_id
                   FROM article_workflows aw4
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionId,
               (
                   SELECT TOP 1 d4.division_name
                   FROM article_workflows aw4
                   INNER JOIN divisions d4 ON d4.division_id = aw4.division_id
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionName,
               (
                   SELECT asz.article_size_id AS Id, spd.size_name AS SizeName, asz.qty AS QtyOrder,
                          ISNULL((
                              SELECT SUM(awl.qty_ok)
                              FROM article_workflow_logs awl
                              WHERE awl.article_workflow_id = aw.article_workflow_id
                                AND awl.article_size_id = asz.article_size_id
                                AND awl.deleted_at IS NULL
                          ), 0) AS QtyRecorded
                   FROM article_sizes asz
                   INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
                   WHERE asz.article_id = aw.article_id AND asz.deleted_at IS NULL
                   ORDER BY spd.sort_order
                   FOR JSON PATH
               ) AS SizesJson,
               CAST(NULL AS INT) AS BundleCount,
               CAST(NULL AS INT) AS TotalBundleQty,
               CAST(NULL AS INT) AS TotalOrderQty,
               aw.sort_order AS SortOrder
        FROM article_workflows aw
        INNER JOIN articles a ON a.article_id = aw.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        WHERE aw.division_id = @DivisionId
          AND aw.deleted_at IS NULL
          AND aw.requires_bundle = 0
          AND p.deleted_at IS NULL
          AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
          AND (
                p.manual_status IS NOT NULL
                OR (p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE))
                OR EXISTS (
                    SELECT 1 FROM article_workflow_logs awl2
                    INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
                    INNER JOIN articles a2 ON a2.article_id = aw2.article_id
                    WHERE a2.project_id = p.project_id
                      AND awl2.deleted_at IS NULL AND aw2.deleted_at IS NULL AND a2.deleted_at IS NULL
                )
              )

        UNION ALL

        -- Prompt 24: kartu "Buat Bundle" -- step Bundling implisit (is_bundling = 1) milik
        -- divisi ini. Tanpa SizesJson (detail per size lewat SIS_Article_BundleSummary saat
        -- modal dibuka) -- cukup ringkasan jumlah bundle vs order untuk teks kartu.
        SELECT aw.article_workflow_id AS ArticleWorkflowId,
               a.article_id AS ArticleId,
               p.project_name AS ProjectName, a.article_name AS ArticleName,
               a.style AS Style, a.color AS Color,
               aw.step_name AS StepName,
               CAST(1 AS BIT) AS IsBundling,
               CASE WHEN aw.sort_order = (
                   SELECT MAX(aw3.sort_order) FROM article_workflows aw3
                   WHERE aw3.article_id = aw.article_id AND aw3.deleted_at IS NULL
               ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep,
               (
                   SELECT TOP 1 aw4.division_id
                   FROM article_workflows aw4
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionId,
               (
                   SELECT TOP 1 d4.division_name
                   FROM article_workflows aw4
                   INNER JOIN divisions d4 ON d4.division_id = aw4.division_id
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionName,
               CAST(NULL AS NVARCHAR(MAX)) AS SizesJson,
               (
                   SELECT COUNT(*) FROM bundles b
                   INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
                   WHERE asz.article_id = aw.article_id AND b.deleted_at IS NULL
               ) AS BundleCount,
               (
                   SELECT ISNULL(SUM(b.qty), 0) FROM bundles b
                   INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
                   WHERE asz.article_id = aw.article_id AND b.deleted_at IS NULL
               ) AS TotalBundleQty,
               (
                   SELECT ISNULL(SUM(asz.qty), 0) FROM article_sizes asz
                   WHERE asz.article_id = aw.article_id AND asz.deleted_at IS NULL
               ) AS TotalOrderQty,
               aw.sort_order AS SortOrder
        FROM article_workflows aw
        INNER JOIN articles a ON a.article_id = aw.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        WHERE aw.division_id = @DivisionId
          AND aw.deleted_at IS NULL
          AND aw.is_bundling = 1
          AND p.deleted_at IS NULL
          AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
          AND (
                p.manual_status IS NOT NULL
                OR (p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE))
                OR EXISTS (
                    SELECT 1 FROM article_workflow_logs awl2
                    INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
                    INNER JOIN articles a2 ON a2.article_id = aw2.article_id
                    WHERE a2.project_id = p.project_id
                      AND awl2.deleted_at IS NULL AND aw2.deleted_at IS NULL AND a2.deleted_at IS NULL
                )
              )
    ) x
    ORDER BY ProjectName ASC, ArticleName ASC, SortOrder ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_PendingHandover
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: default_resource_id stasiun -- baris ini DIBUAT
                                -- oleh divisi ini sendiri, jadi awl.resource_id = pelaksana
                                -- (dipaksa = resource stasiun saat stasiun terkunci, lihat
                                -- EffectiveResourceId), bukan bundles.resource_id seperti di
                                -- PendingReceives/InProgress (itu Line TUJUAN, ini Line PENGIRIM).
AS
BEGIN
    SET NOCOUNT ON;

    SELECT awl.workflow_log_id AS WorkflowLogId, awl.article_workflow_id AS ArticleWorkflowId,
           a.article_id AS ArticleId,
           p.project_name AS ProjectName, a.article_name AS ArticleName,
           a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
           -- Prompt 24: true kalau baris ini log step Bundling implisit (bundle dibuat lewat
           -- kartu "Buat Bundle") -- client memakai ini utk ganti Revisi/Batal Serah jadi Edit.
           aw.is_bundling AS IsBundling,
           awl.bundle_id AS BundleId, b.bundle_no AS BundleNo, b.serial AS Serial,
           awl.article_size_id AS ArticleSizeId, spd.size_name AS SizeName,
           awl.qty_ok AS QtyOk, awl.qty_reject_print AS QtyRejectPrint,
           awl.qty_reject_fabric AS QtyRejectFabric, awl.qty_reject_sewing AS QtyRejectSewing,
           awl.remark AS Remark,
           td.division_name AS TargetDivisionName,
           -- Prompt 23: baris step terakhir (target_division_id NULL, jendela H+1) -- lihat
           -- komentar besar di atas file.
           CASE WHEN awl.target_division_id IS NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep,
           r.resource_name AS ResourceName,
           awl.created_at AS CreatedAt,
           awl.updated_at AS UpdatedAt,
           CASE WHEN awl.bundle_id IS NULL THEN (
               SELECT asz2.article_size_id AS Id, spd2.size_name AS SizeName
               FROM article_sizes asz2
               INNER JOIN size_pack_details spd2 ON spd2.size_pack_detail_id = asz2.size_pack_detail_id
               WHERE asz2.article_id = aw.article_id AND asz2.deleted_at IS NULL
               ORDER BY spd2.sort_order
               FOR JSON PATH
           ) ELSE NULL END AS SizesJson,
           -- Prompt 12e: opsi divisi tujuan utk form Revisi (REVISE_HANDOVER) -- daftar
           -- distinct divisi yang dipakai step manapun di workflow artikel ini.
           (
               SELECT DISTINCT aw3.division_id AS Id, d3.division_name AS DivisionName
               FROM article_workflows aw3
               INNER JOIN divisions d3 ON d3.division_id = aw3.division_id
               WHERE aw3.article_id = a.article_id AND aw3.deleted_at IS NULL
               FOR JSON PATH
           ) AS TargetDivisionOptionsJson,
           -- Prompt 24: data penjahit BUNDLE (bundles.resource_id/resource_person_name) --
           -- DIBEDAKAN dari ResourceName di atas yang untuk baris Bundling berarti pelaksana
           -- bundling (awl.resource_id), bukan penjahit. Dipakai prefill modal Edit bundle.
           b.resource_id AS BundleResourceId,
           bres.resource_name AS BundleResourceName,
           b.resource_person_name AS BundleResourcePersonName
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    LEFT JOIN resources bres ON bres.resource_id = b.resource_id
    WHERE awl.division_id = @DivisionId
      AND awl.deleted_at IS NULL
      AND (
            (awl.target_division_id IS NOT NULL AND awl.received_at IS NULL)
            OR (awl.target_division_id IS NULL
                AND CAST(SYSDATETIME() AS DATE) <= CAST(DATEADD(DAY, 1, awl.created_at) AS DATE))
          )
      AND (@ResourceId IS NULL OR awl.resource_id IS NULL OR awl.resource_id = @ResourceId)
    ORDER BY awl.created_at DESC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_RecentReceived
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: filter ke received_by_resource_id (siapa yang
                                -- menerima), dipaksa = resource stasiun saat terkunci --
                                -- konsisten dengan tombol Batal Terima yang cuma masuk akal
                                -- untuk baris yang diterima Line ini sendiri.
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 20
           awl.workflow_log_id AS WorkflowLogId,
           b.bundle_no AS BundleNo, b.serial AS Serial,
           a.article_name AS ArticleName,
           spd.size_name AS SizeName,
           aw.step_name AS StepName,
           d.division_name AS DivisionAsalName,
           awl.qty_ok AS QtyOk,
           awl.received_at AS ReceivedAt,
           r.resource_name AS ReceivedByResourceName,
           CASE WHEN awl.bundle_id IS NOT NULL AND EXISTS (
               SELECT 1
               FROM article_workflow_logs awl2
               INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
               WHERE awl2.bundle_id = awl.bundle_id AND awl2.deleted_at IS NULL
                 AND aw2.article_id = aw.article_id AND aw2.sort_order > aw.sort_order
           ) THEN CAST(0 AS BIT) ELSE CAST(1 AS BIT) END AS CanUnreceive
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = awl.received_by_resource_id
    WHERE awl.target_division_id = @DivisionId
      AND awl.received_at IS NOT NULL
      AND awl.deleted_at IS NULL
      AND (@ResourceId IS NULL OR awl.received_by_resource_id IS NULL OR awl.received_by_resource_id = @ResourceId)
    ORDER BY awl.received_at DESC;
END;
GO

-- Prompt 12e: tab "Dikerjakan" -- lihat komentar definisi di atas file. Base = baris log
-- bundle TERAKHIR (hidup) per bundle (pola sama dengan sp_Report_Bundle.sql Base CTE, tanpa
-- kolom yang tidak dipakai di sini).
CREATE OR ALTER PROCEDURE SIS_Station_InProgress
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: lihat komentar SIS_Station_PendingReceives
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Base AS (
        SELECT
            b.bundle_id, b.serial, b.bundle_no, b.qty,
            a.article_id, a.article_name, a.style, a.color,
            p.project_name,
            spd.size_name,
            ISNULL(b.resource_person_name, rr.resource_name) AS tailor_name,
            ll.workflow_log_id AS last_log_id,
            ll.received_at AS last_received_at,
            ll.target_division_id AS last_target_division_id,
            law.sort_order AS last_sort_order
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources rr ON rr.resource_id = b.resource_id
        OUTER APPLY (
            SELECT TOP 1 awl.workflow_log_id, awl.article_workflow_id, awl.received_at, awl.target_division_id
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
            ORDER BY aw.sort_order DESC, awl.created_at DESC
        ) ll
        LEFT JOIN article_workflows law ON law.article_workflow_id = ll.article_workflow_id
        WHERE b.deleted_at IS NULL
          AND ll.received_at IS NOT NULL
          AND ll.target_division_id = @DivisionId
          -- Fix: lihat komentar Line vs divisi di SIS_Station_PendingReceives.
          AND (@ResourceId IS NULL OR b.resource_id IS NULL OR b.resource_id = @ResourceId OR rr.division_id <> @DivisionId)
    )
    SELECT
        bs.last_log_id AS WorkflowLogId,
        bs.bundle_id AS BundleId,
        bs.serial AS Serial,
        bs.bundle_no AS BundleNo,
        bs.project_name AS ProjectName,
        bs.article_name AS ArticleName,
        bs.style AS Style, bs.color AS Color,
        bs.size_name AS SizeName,
        bs.qty AS Qty,
        bs.tailor_name AS TailorName,
        bs.last_received_at AS ReceivedAt,
        nxt.article_workflow_id AS NextArticleWorkflowId,
        nxt.step_name AS NextStepName,
        nd.division_name AS NextDivisionName,
        CASE WHEN nxt.sort_order = (
            SELECT MAX(sort_order) FROM article_workflows WHERE article_id = bs.article_id AND deleted_at IS NULL
        ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep
    FROM Base bs
    OUTER APPLY (
        SELECT TOP 1 aw.article_workflow_id, aw.step_name, aw.sort_order
        FROM article_workflows aw
        WHERE aw.article_id = bs.article_id AND aw.deleted_at IS NULL AND aw.requires_bundle = 1
          AND aw.sort_order > bs.last_sort_order
        ORDER BY aw.sort_order ASC
    ) nxt
    OUTER APPLY (
        SELECT TOP 1 aw2.division_id
        FROM article_workflows aw2
        WHERE aw2.article_id = bs.article_id AND aw2.deleted_at IS NULL AND aw2.sort_order > nxt.sort_order
        ORDER BY aw2.sort_order ASC
    ) nd2
    LEFT JOIN divisions nd ON nd.division_id = nd2.division_id
    ORDER BY bs.project_name ASC, bs.article_name ASC, bs.bundle_no ASC;
END;
GO

-- Prompt 12e: strip 3 angka (Masuk/Dikerjakan/Dikirim) di atas /station. Masuk & Dikirim
-- pakai definisi baris yang sama dengan SIS_Station_PendingReceives/PendingHandover;
-- Dikerjakan pakai definisi bundle yang sama dengan SIS_Station_InProgress di atas.
CREATE OR ALTER PROCEDURE SIS_Station_Counts
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: lihat komentar SIS_Station_PendingReceives
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (
            SELECT COUNT(*)
            FROM article_workflow_logs awl
            LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
            LEFT JOIN resources br ON br.resource_id = b.resource_id
            WHERE awl.target_division_id = @DivisionId AND awl.received_at IS NULL AND awl.deleted_at IS NULL
              -- Fix: lihat komentar Line vs divisi di SIS_Station_PendingReceives.
              AND (@ResourceId IS NULL OR b.resource_id IS NULL OR b.resource_id = @ResourceId OR br.division_id <> @DivisionId)
        ) AS MasukCount,
        (
            SELECT COUNT(*) FROM (
                SELECT b.bundle_id
                FROM bundles b
                LEFT JOIN resources br ON br.resource_id = b.resource_id
                OUTER APPLY (
                    SELECT TOP 1 awl.received_at, awl.target_division_id
                    FROM article_workflow_logs awl
                    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
                    WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
                    ORDER BY aw.sort_order DESC, awl.created_at DESC
                ) ll
                WHERE b.deleted_at IS NULL AND ll.received_at IS NOT NULL AND ll.target_division_id = @DivisionId
                  AND (@ResourceId IS NULL OR b.resource_id IS NULL OR b.resource_id = @ResourceId OR br.division_id <> @DivisionId)
            ) x
        )
        +
        (
            -- Prompt 23: tambahkan kartu non-bundle (artikel x step), definisi sama dengan
            -- SIS_Station_ActiveWork -- tanpa filter Line (kartu non-bundle tidak terikat Line).
            -- Prompt 24: ikut hitung kartu "Buat Bundle" (is_bundling = 1), selaras dengan
            -- UNION baru di SIS_Station_ActiveWork.
            SELECT COUNT(*)
            FROM article_workflows aw
            INNER JOIN articles a ON a.article_id = aw.article_id
            INNER JOIN projects p ON p.project_id = a.project_id
            WHERE aw.division_id = @DivisionId AND aw.deleted_at IS NULL
              AND (aw.requires_bundle = 0 OR aw.is_bundling = 1)
              AND p.deleted_at IS NULL AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
        ) AS DikerjakanCount,
        (
            -- Prompt 23: selaraskan dengan SIS_Station_PendingHandover -- ikut hitung baris
            -- step terakhir (H+1) supaya angka OUT cocok dengan isi tabnya.
            SELECT COUNT(*) FROM article_workflow_logs
            WHERE division_id = @DivisionId AND deleted_at IS NULL
              AND (
                    (target_division_id IS NOT NULL AND received_at IS NULL)
                    OR (target_division_id IS NULL
                        AND CAST(SYSDATETIME() AS DATE) <= CAST(DATEADD(DAY, 1, created_at) AS DATE))
                  )
              AND (@ResourceId IS NULL OR resource_id IS NULL OR resource_id = @ResourceId)
        ) AS DikirimCount;
END;
GO

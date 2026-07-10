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
--   SIS_Station_ActiveWork: step non-bundle (requires_bundle = 0) milik divisi ini --
--   SELALU tampil untuk semua artikel yang project-nya masih hidup, bukan antrian
--   sekali-pakai (baris non-bundle bebas dicatat berulang kapan pun, lihat komentar di
--   sp_WorkflowLog_Manage.sql). Sertakan daftar ukuran artikel (FOR JSON) supaya client
--   bisa menampilkan dropdown Size tanpa round-trip tambahan.
--
--   SIS_Station_PendingHandover: kebalikan dari PendingReceives -- baris yang DIBUAT oleh
--   divisi ini sendiri (division_id = @DivisionId), sudah punya tujuan serah, tapi BELUM
--   diterima divisi tujuan (received_at IS NULL). Selama belum diterima, divisi pembuat
--   masih boleh merevisi datanya (action UPDATE di SIS_WorkflowLog_Manage) -- begitu
--   diterima (received_at terisi lewat RECEIVE), baris terkunci dan hilang dari daftar ini.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Station_PendingReceives
    @DivisionId INT
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
           spd.size_name AS SizeName
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE awl.target_division_id = @DivisionId
      AND awl.received_at IS NULL
      AND awl.deleted_at IS NULL
    ORDER BY awl.created_at ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_ActiveWork
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT aw.article_workflow_id AS ArticleWorkflowId,
           p.project_name AS ProjectName, a.article_name AS ArticleName,
           a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
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
               SELECT asz.article_size_id AS Id, spd.size_name AS SizeName
               FROM article_sizes asz
               INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
               WHERE asz.article_id = aw.article_id AND asz.deleted_at IS NULL
               ORDER BY spd.sort_order
               FOR JSON PATH
           ) AS SizesJson
    FROM article_workflows aw
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    WHERE aw.division_id = @DivisionId
      AND aw.deleted_at IS NULL
      AND aw.requires_bundle = 0
      AND p.deleted_at IS NULL
    ORDER BY p.project_name ASC, a.article_name ASC, aw.sort_order ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_PendingHandover
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT awl.workflow_log_id AS WorkflowLogId, awl.article_workflow_id AS ArticleWorkflowId,
           p.project_name AS ProjectName, a.article_name AS ArticleName,
           a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
           awl.bundle_id AS BundleId, b.bundle_no AS BundleNo, b.serial AS Serial,
           awl.article_size_id AS ArticleSizeId, spd.size_name AS SizeName,
           awl.qty_ok AS QtyOk, awl.qty_reject_print AS QtyRejectPrint,
           awl.qty_reject_fabric AS QtyRejectFabric, awl.qty_reject_sewing AS QtyRejectSewing,
           awl.qty_rework AS QtyRework, awl.remark AS Remark,
           td.division_name AS TargetDivisionName,
           r.resource_name AS ResourceName,
           awl.created_at AS CreatedAt,
           CASE WHEN awl.bundle_id IS NULL THEN (
               SELECT asz2.article_size_id AS Id, spd2.size_name AS SizeName
               FROM article_sizes asz2
               INNER JOIN size_pack_details spd2 ON spd2.size_pack_detail_id = asz2.size_pack_detail_id
               WHERE asz2.article_id = aw.article_id AND asz2.deleted_at IS NULL
               ORDER BY spd2.sort_order
               FOR JSON PATH
           ) ELSE NULL END AS SizesJson
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    WHERE awl.division_id = @DivisionId
      AND awl.target_division_id IS NOT NULL
      AND awl.received_at IS NULL
      AND awl.deleted_at IS NULL
    ORDER BY awl.created_at DESC;
END;
GO

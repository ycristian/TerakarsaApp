-- Pengambilan data article_workflow_logs (SELECT saja, tidak menyentuh data).
-- Mutasi (create/receive/delete) ada di sp_WorkflowLog_Manage.sql (SIS_WorkflowLog_Manage).
-- Dipakai di halaman Edit Article (riwayat log workflow, read-only).
-- Model 1-baris (Prompt 12b): tidak ada kolom status lagi -- "diterima" diturunkan dari
-- received_at. Menyertakan article_size_id/size_name (baris non-bundle) dan trio
-- received_* (received_at, received_by (nama), received_remark).
-- Prompt 12d: identitas dipisah -- PENCATAT = CreatedByName (users, JOIN created_by),
-- PELAKSANA = ResourceName (resources, JOIN resource_id, sudah ada). Trio revisi
-- (UpdatedAt/UpdatedByName/UpdatedByResourceName) LEFT JOIN, terisi hanya kalau baris
-- pernah di-UPDATE (lihat sp_WorkflowLog_Manage.sql).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkflowLog_ListByArticle
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT awl.workflow_log_id AS Id, awl.article_workflow_id AS ArticleWorkflowId,
           aw.step_name AS StepName, aw.sort_order AS SortOrder,
           awl.bundle_id AS BundleId, b.serial AS BundleSerial,
           awl.article_size_id AS ArticleSizeId, spd.size_name AS SizeName,
           awl.division_id AS DivisionId, d.division_name AS DivisionName,
           awl.resource_id AS ResourceId, r.resource_name AS ResourceName,
           awl.qty_ok AS QtyOk, awl.qty_reject_print AS QtyRejectPrint,
           awl.qty_reject_fabric AS QtyRejectFabric, awl.qty_reject_sewing AS QtyRejectSewing,
           awl.remark AS Remark,
           awl.target_division_id AS TargetDivisionId, td.division_name AS TargetDivisionName,
           awl.received_at AS ReceivedAt, rr.resource_name AS ReceivedByResourceName,
           awl.received_remark AS ReceivedRemark,
           awl.created_at AS CreatedAt, awl.created_by AS CreatedBy, cu.FullName AS CreatedByName,
           awl.updated_at AS UpdatedAt, uu.FullName AS UpdatedByName, ur.resource_name AS UpdatedByResourceName
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    LEFT JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN resources rr ON rr.resource_id = awl.received_by_resource_id
    LEFT JOIN Users cu ON cu.Id = awl.created_by
    LEFT JOIN Users uu ON uu.Id = awl.updated_by
    LEFT JOIN resources ur ON ur.resource_id = awl.updated_by_resource_id
    WHERE aw.article_id = @ArticleId AND awl.deleted_at IS NULL
    ORDER BY aw.sort_order ASC, awl.created_at ASC;
END;
GO

-- Prompt 14: info kuota qty untuk UI (form add/edit hasil step ber-bundle) -- dipakai
-- SEBELUM submit untuk menampilkan "Masuk / Tercatat / Sisa". Logika sama persis dengan
-- validasi kuota di sp_WorkflowLog_Manage.sql (SIS_WorkflowLog_Manage, action CREATE/UPDATE).
CREATE OR ALTER PROCEDURE SIS_WorkflowLog_QuotaInfo
    @ArticleWorkflowId INT,
    @BundleId          INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ArticleId INT, @SortOrder INT;
    SELECT @ArticleId = article_id, @SortOrder = sort_order
    FROM article_workflows WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL;

    DECLARE @FirstBundleSort INT;
    SELECT @FirstBundleSort = MIN(sort_order)
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1;

    DECLARE @QtyMasuk INT;
    IF @SortOrder = @FirstBundleSort
        SELECT @QtyMasuk = qty FROM bundles WHERE bundle_id = @BundleId;
    ELSE
    BEGIN
        DECLARE @PrevArticleWorkflowId INT;
        SELECT TOP 1 @PrevArticleWorkflowId = article_workflow_id
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND requires_bundle = 1 AND sort_order < @SortOrder
        ORDER BY sort_order DESC;

        SELECT @QtyMasuk = ISNULL(SUM(qty_ok), 0)
        FROM article_workflow_logs
        WHERE article_workflow_id = @PrevArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;
    END

    SET @QtyMasuk = ISNULL(@QtyMasuk, 0);

    DECLARE @QtySudah INT;
    SELECT @QtySudah = ISNULL(SUM(qty_ok + qty_reject_print + qty_reject_fabric + qty_reject_sewing), 0)
    FROM article_workflow_logs
    WHERE article_workflow_id = @ArticleWorkflowId AND bundle_id = @BundleId AND deleted_at IS NULL;

    SELECT @QtyMasuk AS QtyMasuk, @QtySudah AS QtySudah, (@QtyMasuk - @QtySudah) AS Sisa;
END;
GO

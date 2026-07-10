-- Pengambilan data article_workflow_logs (SELECT saja, tidak menyentuh data).
-- Mutasi (create/receive/delete) ada di sp_WorkflowLog_Manage.sql (SIS_WorkflowLog_Manage).
-- Dipakai di halaman Edit Article (riwayat log workflow, read-only).
-- Model 1-baris (Prompt 12b): tidak ada kolom status lagi -- "diterima" diturunkan dari
-- received_at. Menyertakan article_size_id/size_name (baris non-bundle) dan trio
-- received_* (received_at, received_by (nama), received_remark).

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
           awl.qty_rework AS QtyRework, awl.remark AS Remark,
           awl.target_division_id AS TargetDivisionId, td.division_name AS TargetDivisionName,
           awl.received_at AS ReceivedAt, rr.resource_name AS ReceivedByResourceName,
           awl.received_remark AS ReceivedRemark,
           awl.created_at AS CreatedAt, awl.created_by AS CreatedBy
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    LEFT JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN resources rr ON rr.resource_id = awl.received_by_resource_id
    WHERE aw.article_id = @ArticleId AND awl.deleted_at IS NULL
    ORDER BY aw.sort_order ASC, awl.created_at ASC;
END;
GO

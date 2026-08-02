-- Pengambilan data article_workflows (SELECT saja, tidak menyentuh data).
-- Mutasi (APPLY/SAVE) ada di sp_ArticleWorkflow_Manage.sql (SIS_ArticleWorkflow_Manage).
-- Nama template asal disertakan per baris (denormalized) supaya client bisa
-- menampilkan info "Template asal" tanpa round-trip tambahan.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_ArticleWorkflow_ListByArticle
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT aw.article_workflow_id AS Id, aw.article_id AS ArticleId,
           aw.workflow_template_id AS WorkflowTemplateId, wt.workflow_name AS WorkflowTemplateName,
           aw.step_name AS StepName, aw.division_id AS DivisionId, d.division_name AS DivisionName,
           aw.sort_order AS SortOrder, aw.requires_bundle AS RequiresBundle, aw.auto_receive AS AutoReceive,
           aw.print_kupon AS PrintKupon, aw.is_bundling AS IsBundling
    FROM article_workflows aw
    INNER JOIN divisions d ON d.division_id = aw.division_id
    LEFT JOIN workflow_templates wt ON wt.workflow_template_id = aw.workflow_template_id
    WHERE aw.article_id = @ArticleId AND aw.deleted_at IS NULL
    ORDER BY aw.sort_order ASC, aw.article_workflow_id ASC;
END;
GO

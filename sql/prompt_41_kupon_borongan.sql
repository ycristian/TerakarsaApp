-- Prompt 41: Kupon Borongan & Rekap Penjahit -- tambah flag print_kupon di step workflow.
-- v1 hanya valid utk step bertipe bundle (requires_bundle = 1) -- ditegakkan di
-- SIS_WorkflowTemplate_Manage & SIS_ArticleWorkflow_Manage, bukan di sini. Idempotent.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('workflow_template_steps') AND name = 'print_kupon'
)
BEGIN
    ALTER TABLE workflow_template_steps ADD print_kupon bit not null default 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('article_workflows') AND name = 'print_kupon'
)
BEGIN
    ALTER TABLE article_workflows ADD print_kupon bit not null default 0;
END
GO

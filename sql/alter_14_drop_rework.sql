-- Prompt 14: hapus qty_rework dari article_workflow_logs -- skenarionya belum ada dan
-- membuat rantai qty antar step ambigu (lihat sp_WorkflowLog_Manage.sql untuk validasi
-- kuota qty yang menggantikannya). Idempotent -- aman dijalankan berulang.

IF EXISTS (
    SELECT 1 FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID('article_workflow_logs') AND c.name = 'qty_rework'
)
BEGIN
    DECLARE @ConstraintName SYSNAME;
    SELECT @ConstraintName = dc.name
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID('article_workflow_logs') AND c.name = 'qty_rework';

    EXEC('ALTER TABLE article_workflow_logs DROP CONSTRAINT ' + @ConstraintName);
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'qty_rework')
    ALTER TABLE article_workflow_logs DROP COLUMN qty_rework;
GO

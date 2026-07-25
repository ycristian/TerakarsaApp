-- Prompt 28: qty_reject_rework, qty_lost, log_type di article_workflow_logs.
-- Idempotent -- aman dijalankan berkali-kali. Tidak perlu backfill (default 0 / 'NORMAL'
-- sudah benar untuk data lama).

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'qty_reject_rework'
)
BEGIN
    ALTER TABLE article_workflow_logs
        ADD qty_reject_rework int not null constraint DF_awl_qty_reject_rework default 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'qty_lost'
)
BEGIN
    ALTER TABLE article_workflow_logs
        ADD qty_lost int not null constraint DF_awl_qty_lost default 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'log_type'
)
BEGIN
    ALTER TABLE article_workflow_logs
        ADD log_type varchar(15) not null constraint DF_awl_log_type default 'NORMAL';
END
GO

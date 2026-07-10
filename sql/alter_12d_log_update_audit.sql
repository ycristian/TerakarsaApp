-- Migrasi Prompt 12d: jejak revisi (UPDATE) pada article_workflow_logs, dipisah dari
-- pencatat (created_by, user login) vs pelaksana (resource_id). Trio updated_* hanya
-- diisi action UPDATE (revisi sebelum diterima); log tetap tidak boleh diubah setelah
-- received_at terisi. Idempotent, aman dijalankan berulang.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'updated_at')
BEGIN
    ALTER TABLE article_workflow_logs ADD updated_at datetime2 null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'updated_by')
BEGIN
    ALTER TABLE article_workflow_logs ADD updated_by int null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'updated_by_resource_id')
BEGIN
    ALTER TABLE article_workflow_logs ADD updated_by_resource_id int null
        CONSTRAINT FK_awl_updated_by_resource FOREIGN KEY REFERENCES resources(resource_id);
END
GO

-- Prompt 47: index penunjang modul Log Aktivitas -- filter rentang tanggal langsung pada
-- created_at/received_at (tanpa agregasi/GROUP BY di atasnya, beda dari index FK yang sudah
-- ada di sql/create_tables_tmos_final.sql: IX_awl_bundle, IX_awl_article_workflow).

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_created_at' AND object_id = OBJECT_ID('article_workflow_logs'))
    CREATE INDEX IX_awl_created_at ON article_workflow_logs(created_at) WHERE deleted_at IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_received_at' AND object_id = OBJECT_ID('article_workflow_logs'))
    CREATE INDEX IX_awl_received_at ON article_workflow_logs(received_at) WHERE deleted_at IS NULL;
GO

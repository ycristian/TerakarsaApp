-- Migrasi Prompt 12b: model article_workflow_logs disederhanakan jadi 1 baris per
-- serah-terima. INSERT (dulu 'COMPLETED') = pekerjaan step selesai; penerimaan (dulu
-- baris terpisah berstatus 'RECEIVED') kini mengisi received_at/received_by_resource_id/
-- received_remark pada baris yang sama. Kolom [status] dihapus -- status selalu
-- diturunkan dari ada/tidaknya received_at. Data log lama adalah data uji, boleh
-- dikosongkan. Idempotent, aman dijalankan berulang.

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'status')
BEGIN
    DELETE FROM article_workflow_logs;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'status')
BEGIN
    ALTER TABLE article_workflow_logs DROP COLUMN [status];
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'article_size_id')
BEGIN
    ALTER TABLE article_workflow_logs ADD article_size_id int null
        CONSTRAINT FK_awl_article_sizes FOREIGN KEY REFERENCES article_sizes(article_size_id);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'received_remark')
BEGIN
    ALTER TABLE article_workflow_logs ADD received_remark varchar(500) null;
END
GO

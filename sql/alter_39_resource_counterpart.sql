-- Migrasi Prompt 39: pemetaan resource pasangan (mis. Line A1 di Sewing -> Trim A1 di
-- Buang Benang), dipakai auto-terima dan saran pelaksana di station. Idempotent.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('resources') AND name = 'counterpart_resource_id')
BEGIN
    ALTER TABLE resources ADD counterpart_resource_id int null
        CONSTRAINT FK_resources_counterpart FOREIGN KEY REFERENCES resources(resource_id);
END
GO

-- Prompt 40: kolom resources.counterpart_resource_id sudah dibuat di Prompt 39
-- (alter_39_resource_counterpart.sql). Script ini murni jaga-jaga idempotent kalau
-- dijalankan di database yang belum pernah menjalankan alter_39 -- TIDAK menambah
-- kolom/constraint baru. Aturan "counterpart valid" yang lebih ketat (harus persis
-- division_id = divisi tujuan yang sedang diperiksa) ditegakkan di kode SP
-- (SIS_WorkflowLog_Manage, SIS_Bundle_ScanInfo, dst.), bukan di skema.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('resources') AND name = 'counterpart_resource_id')
BEGIN
    ALTER TABLE resources ADD counterpart_resource_id int null
        CONSTRAINT FK_resources_counterpart FOREIGN KEY REFERENCES resources(resource_id);
END
GO

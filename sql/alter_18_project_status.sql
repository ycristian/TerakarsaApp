-- Prompt 18: kolom status project (manual_status NULL = otomatis Not Started/On Going,
-- diturunkan di sp_Project_Select.sql -- tidak disimpan sebagai data).
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('projects') AND name = 'manual_status')
BEGIN
    ALTER TABLE projects ADD manual_status varchar(20) null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('projects') AND name = 'status_reason')
BEGIN
    ALTER TABLE projects ADD status_reason varchar(255) null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('projects') AND name = 'status_changed_at')
BEGIN
    ALTER TABLE projects ADD status_changed_at datetime2 null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('projects') AND name = 'status_changed_by')
BEGIN
    ALTER TABLE projects ADD status_changed_by int null;
END
GO

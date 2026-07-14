-- Tambah kolom catatan (remarks) dan penanda urgent di projects.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('projects') AND name = 'remarks'
)
BEGIN
    ALTER TABLE projects ADD remarks varchar(500) NULL;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('projects') AND name = 'is_urgent'
)
BEGIN
    ALTER TABLE projects ADD is_urgent bit NOT NULL DEFAULT 0;
END
GO

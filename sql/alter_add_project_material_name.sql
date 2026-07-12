-- Tambah kolom nama bahan (fabric type) di projects.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('projects') AND name = 'material_name'
)
BEGIN
    ALTER TABLE projects ADD material_name varchar(150) NULL;
END
GO

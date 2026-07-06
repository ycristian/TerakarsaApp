-- Registrasi module baru untuk grup collapsible "Master Data" di sidebar,
-- digabung ke section "App Setting" yang sudah ada (Category = 'App Setting',
-- SubCategory = 'Master Data'). Jalankan setelah alter_modules_add_subcategory.sql.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'MASTER_DIVISION')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('MASTER_DIVISION', 'Divisi', 'App Setting', 'Master Data', 'divisions', 'fe fe-layers', 100, 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'MASTER_POSITION')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('MASTER_POSITION', 'Jabatan', 'App Setting', 'Master Data', 'positions', 'fe fe-briefcase', 110, 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'MASTER_RESOURCE_TYPE')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('MASTER_RESOURCE_TYPE', 'Tipe Resource', 'App Setting', 'Master Data', 'resource-types', 'fe fe-tool', 120, 1, GETDATE());
GO

-- Perbaikan untuk module yang sudah kadung dibuat sebelum SubCategory ada
-- (Category lama = 'Master Data', SubCategory kosong). Aman dijalankan berulang.
UPDATE Modules
SET Category = 'App Setting',
    SubCategory = 'Master Data'
WHERE Code IN ('MASTER_DIVISION', 'MASTER_POSITION', 'MASTER_RESOURCE_TYPE')
  AND (Category <> 'App Setting' OR SubCategory IS NULL OR SubCategory <> 'Master Data');
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code IN ('MASTER_DIVISION', 'MASTER_POSITION', 'MASTER_RESOURCE_TYPE')
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO

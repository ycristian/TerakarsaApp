-- Registrasi module MASTER_EMPLOYEE untuk grup collapsible "Master Data" di sidebar,
-- digabung ke section "App Setting" yang sudah ada (Category = 'App Setting',
-- SubCategory = 'Master Data'). Jalankan setelah seed_master_data_modules.sql
-- dan seed_master_resource_module.sql (employees butuh Resource untuk dropdown).
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'MASTER_EMPLOYEE')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('MASTER_EMPLOYEE', 'Karyawan', 'App Setting', 'Master Data', 'employees', 'fe fe-users', 150, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'MASTER_EMPLOYEE'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
